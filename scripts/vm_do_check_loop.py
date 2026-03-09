#!/usr/bin/env python3

from typing import List, Optional

import subprocess
import os
import sys
import re
import time

from argparse import ArgumentParser

from azure.storage.blob import BlobServiceClient
from azure.identity import DefaultAzureCredential

from datetime import datetime, timezone

from c_aci_testing.tools.vm_cp_into import vm_cp_into


def must_get_env(name) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Environment variable {name} is not set.")
    return value


DEPLOYMENT_NAME = must_get_env("DEPLOYMENT_NAME")
SUBSCRIPTION = must_get_env("SUBSCRIPTION")
RESOURCE_GROUP = must_get_env("RESOURCE_GROUP")
STORAGE_ACCOUNT = must_get_env("STORAGE_ACCOUNT")
STORAGE_CONTAINER = "vmtestlogs"

argp = ArgumentParser("vm_do_check_loop.py")
argp.add_argument(
    "--check-for-secs",
    type=int,
    default=60 * 60,
    help="Total time in seconds to loop",
)
argp.add_argument(
    "--check-interval",
    type=int,
    default=30,
    help="Interval in seconds between checks",
)
argp.add_argument(
    "--out-dir",
    type=str,
    help="Directory to store the fetched logs",
)
argp.add_argument(
    "--stress-tests-http-checks",
    action="store_true",
    default=False,
)
argp.add_argument(
    "--expect-to-terminate",
    action="store_true",
    default=False,
)

args = argp.parse_args()
check_for_secs = args.check_for_secs
check_interval = args.check_interval
out_dir = args.out_dir
stress_tests_http_checks = args.stress_tests_http_checks
expect_to_terminate = args.expect_to_terminate

storage_account_url = f"https://{STORAGE_ACCOUNT}.blob.core.windows.net"

blobSvc = BlobServiceClient(
    account_url=storage_account_url,
    credential=DefaultAzureCredential(),
)

containerClient = blobSvc.get_container_client(STORAGE_CONTAINER)


def run_command(command: List[str], output: bool = False, timeout_secs=10):
    print(" ".join(command), flush=True)
    sys.stderr.flush()
    stdout = subprocess.PIPE if output else None
    try:
        result = subprocess.run(
            command, stdout=stdout, text=True, timeout=timeout_secs, check=True
        )
        return result.stdout if output else None
    except subprocess.TimeoutExpired as e:
        raise RuntimeError(f"Command timed out: {' '.join(command)}") from e


run_command(["./scripts/tracing/trace_step.py", "--start", "Start check loop on VM"])


def finish_trace(err: Optional[str] = None):
    maybe_err = []
    if err:
        maybe_err = ["--err", err]
    sys.stdout.flush()
    print(err, flush=True, file=sys.stderr)
    run_command(
        ["./scripts/tracing/trace_step.py", "--complete", "--strict", *maybe_err],
    )


logs_folder_name = re.sub(r"[^a-zA-Z0-9_\-]+", "_", f"{DEPLOYMENT_NAME}_check_loop")

print(f"Using logs folder: {logs_folder_name}")

LAST_UPDATED_FILENAME = "last_updated_timestamp"
TERMINATION_FLAG_FILE = "all_terminated"


def delete_if_not_exists(blob_name: str):
    try:
        blobClient = containerClient.get_blob_client(blob_name)
        blobClient.delete_blob()
        print(f"Deleted {blob_name}")
    except Exception as e:
        if "BlobNotFound" not in str(e):
            print(f"Error deleting {blob_name}: {e}")


file_list = containerClient.list_blob_names(name_starts_with=f"{logs_folder_name}/")
for blob_name in file_list:
    if blob_name.startswith(logs_folder_name + "/"):
        delete_if_not_exists(blob_name)

os.makedirs(out_dir, exist_ok=True)

log_folder_blob_url = f"{storage_account_url}/{STORAGE_CONTAINER}/{logs_folder_name}"
print(f"Logs will be uploaded to: {log_folder_blob_url}")

maybe_additional_scripts = ""
if stress_tests_http_checks:
    maybe_additional_scripts = "-additionalChecksScript check_stress_tests_http.ps1"

vm_cp_into(
    deployment_name=DEPLOYMENT_NAME,
    src="scripts/vm_helpers",
    dst="C:\\vm_helpers",
    run_command=" ".join(
        [
            "C:\\vm_helpers\\start_check_loop.ps1",
            "-checkArgs",
            f'"-checkInterval {check_interval} {maybe_additional_scripts} -uploadLogsTo {log_folder_blob_url}"',
        ]
    ),
    subscription=SUBSCRIPTION,
    resource_group=RESOURCE_GROUP,
    storage_account=STORAGE_ACCOUNT,
)

last_probed_update_time: Optional[datetime] = None
printed_lengths = {}
containers_terminated = False


def print_unprinted(file_name: str, content_bin: bytes):
    global printed_lengths

    printed_length = printed_lengths.get(file_name, 0)
    curr_len = len(content_bin)
    if curr_len <= printed_length:
        return
    printed_lengths[file_name] = curr_len
    print(f"=== {file_name} ===")
    print(
        content_bin[printed_length:].decode("utf-8", errors="ignore"),
        end="",
        flush=True,
    )


def probe_logs():
    global last_probed_update_time, containers_terminated

    file_list = containerClient.list_blob_names(name_starts_with=f"{logs_folder_name}/")
    last_updated = None
    seen_files = False

    for blob_name in file_list:
        if not blob_name.startswith(logs_folder_name + "/"):
            print(f"WARNING: got unexpected blob name: {blob_name}")
            continue
        blob = containerClient.get_blob_client(blob_name)
        content_bin = blob.download_blob().readall()
        f_name = blob_name[len(logs_folder_name) + 1 :]
        if f_name == LAST_UPDATED_FILENAME:
            try:
                content = content_bin.decode("utf-8", errors="ignore")
                last_updated = datetime.fromisoformat(content.strip()).astimezone(
                    timezone.utc
                )
            except ValueError as e:
                print(f"Error parsing last updated timestamp: {e}")
        elif f_name == TERMINATION_FLAG_FILE:
            print(f"{f_name} found.")
            containers_terminated = True
        else:
            seen_files = True
            dir_name = os.path.dirname(f_name)
            if dir_name:
                os.makedirs(os.path.join(out_dir, dir_name), exist_ok=True)
            with open(os.path.join(out_dir, f_name), "wb") as f:
                f.write(content_bin)
            print_unprinted(f_name, content_bin)

    missings = []
    if not last_updated:
        missings.append("Missing last updated timestamp")
    if not seen_files:
        missings.append("No log files found")

    if missings:
        print(f"WARNING: {', '.join(missings)}\nSkipping this one.")
        return

    if not last_probed_update_time or last_updated > last_probed_update_time:
        print(f"Logs updated - latest was from {last_updated}")
        last_probed_update_time = last_updated
        delta = (datetime.now(timezone.utc) - last_updated).total_seconds()
        if delta > check_for_secs * 2:
            print(f"WARNING: Log was last uploaded {delta} seconds ago.")

    elif last_updated < last_probed_update_time:
        print(
            f"WARNING: Newly fetched logs are older than the ones fetched before: {last_updated} < {last_probed_update_time}"
        )
        return


consecutive_failures = 0

start_time = time.time()

while time.time() - start_time < check_for_secs:
    try:
        probe_logs()
        if not expect_to_terminate and containers_terminated:
            finish_trace("Containers stopped unexpectedly.")
            sys.exit(1)
        elif containers_terminated:
            break
        consecutive_failures = 0
        time.sleep(check_interval)
    except Exception as e:
        consecutive_failures += 1
        print(f"Error probing for logs: {e}")
        if consecutive_failures >= 3:
            finish_trace("Too many consecutive failures during log probing.")
            raise e

if last_probed_update_time:
    delta = (datetime.now(timezone.utc) - last_probed_update_time).total_seconds()
    if delta > check_for_secs * 5:
        finish_trace(f"VM did not upload new logs in the last {delta} seconds.")
        sys.exit(1)
