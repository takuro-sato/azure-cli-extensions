#!/usr/bin/env python3

from typing import Any, Callable, Dict, List, Optional, Tuple

import logging
logging.basicConfig(level=logging.INFO, format="[%(asctime)s] [%(module)s] [%(levelname)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S")

import sys
import base64
import json
import os
import sys
import time
import csv
import traceback
import random
from uuid import uuid4
from datetime import datetime
from dataclasses import dataclass
import requests
from azure.kusto.data import KustoClient, KustoConnectionStringBuilder

@dataclass
class MAAEndpoint:
    env: str
    region: str
    dns_name: str
    tee: str

def read_maa_endpoints_csv(file_path: str) -> List[MAAEndpoint]:
    endpoints = []
    try:
        with open(file_path, "rt", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    endpoint = MAAEndpoint(
                        env=row["Env"].strip(),
                        region=row["Region"].strip(),
                        dns_name=row["DNS Name"].strip(),
                        tee=row["TEE"].strip()
                    )
                    endpoints.append(endpoint)
                except KeyError as e:
                    logging.fatal("Missing expected column in CSV: %s", e)
    except OSError as e:
        logging.fatal("Failed to read MAA endpoints from file: %s", e)
        sys.exit(1)
    logging.info("Loaded %d MAA endpoints from %s", len(endpoints), file_path)
    return endpoints

sidecar_maa_url = "http://127.0.0.1:8080/attest/maa"

def request_maa_token(dns_name: str, runtime_data: str) -> str:
    res = requests.post(
        sidecar_maa_url,
        json={
            "maa_endpoint": dns_name,
            "runtime_data": base64.urlsafe_b64encode(runtime_data.encode("utf-8")).decode("utf-8"),
        },
        headers={"Content-Type": "application/json"},
        timeout=30,
    )
    if not res.ok:
        raise Exception(f"MAA attestation request failed with status {res.status_code}: {res.text}")
    res_json = res.json()
    token = res_json.get("token")
    if not isinstance(token, str):
        raise Exception(f"MAA attestation response missing 'token' field or it is not a string: {res_json}")
    return token

class MAATestResult:
    endpoint: MAAEndpoint
    error: Optional[str]
    logs: Optional[str]

    def __init__(self, endpoint: MAAEndpoint, error: Optional[str], logs: Optional[str]) -> None:
        self.endpoint = endpoint
        self.error = error
        self.logs = logs
        if self.error and not self.logs.strip().endswith(self.error.strip()):
            self.logs = (self.logs or "") + "\n" + self.error

def test_maa(
    endpoint: MAAEndpoint,
) -> MAATestResult:
    global runtime_data, skr_log_path

    logs = ""

    def log(msg: str) -> None:
        nonlocal logs
        logs += msg + "\n"
        logging.info("%s", msg)

    log(f"Testing MAA endpoint: {endpoint.dns_name}")

    has_skr_logs = os.path.isfile(skr_log_path)
    if not has_skr_logs:
        log(f"SKR log file does not exist: {skr_log_path}")
    else:
        skr_log_bytes_at_start = os.stat(skr_log_path).st_size

    exc = None

    try:
        token = request_maa_token(endpoint.dns_name, runtime_data)
    except Exception as e:
        exc = e
    finally:
        if has_skr_logs:
            with open(skr_log_path, "rt", encoding="utf-8", errors="replace") as f:
                f.seek(skr_log_bytes_at_start, os.SEEK_SET)
                skr_logs = f.read()
                logs += skr_logs
                if exc:
                    logging.info("SKR log:\n%s", skr_logs)

    if exc:
        return MAATestResult(endpoint, f"Failed to request MAA token: {''.join(traceback.format_exception_only(exc)).strip()}", logs)

    if not token:
        return MAATestResult(endpoint, "MAA Attestation returned an empty token", logs)
    parts = token.split(".")
    if len(parts) < 3:
        return MAATestResult(endpoint, "MAA Attestation returned an invalid token", logs)
    try:
        payload_bytes = base64.urlsafe_b64decode(parts[1] + "==")
    except Exception as e:
        return MAATestResult(endpoint, f"Failed to base64 decode token body: {e}", logs)
    try:
        parsed = json.loads(payload_bytes)
    except Exception as e:
        return MAATestResult(endpoint, f"Failed to parse token body: {e}", logs)
    iss = parsed.get("iss")
    log(f"iss = {iss}")
    if not isinstance(iss, str):
        return MAATestResult(endpoint, f"Expected 'iss' field to be a string, got: {iss}", logs)
    expected_iss = f"https://{endpoint.dns_name}"
    if iss.rstrip("/") != expected_iss:
        return MAATestResult(endpoint, f"Invalid token issuer: {iss}, expected: {expected_iss}", logs)
    log(f"MAA test ({endpoint.dns_name}) succeeded")
    return MAATestResult(endpoint, None, logs)

runtime_data = None
skr_log_path = "/var/log/skr/skr.log"
client_region = os.getenv("CLIENT_REGION")
kusto_database = os.getenv("KUSTO_DATABASE")
kusto_table = os.getenv("KUSTO_TABLE")
kusto_connection_string = os.getenv("KUSTO_CONNECTION_STRING")
if kusto_database and kusto_table and kusto_connection_string:
    kusto_conn = KustoConnectionStringBuilder.with_aad_managed_service_identity_authentication(
        kusto_connection_string,
        client_id=os.getenv("KUSTO_MANAGED_IDENTITY_CLIENT_ID"), # allow None
    )
    kusto_client = KustoClient(kusto_conn)
else:
    kusto_conn = None
    logging.warning("KUSTO_DATABASE, KUSTO_TABLE or KUSTO_CONNECTION_STRING environment variable not provided - will not trace result to Kusto.")

if kusto_conn and not client_region:
    logging.fatal("CLIENT_REGION must be specified for tracing (the region of the container that's running this script)")
    sys.exit(1)


def report_test_result(endpoint: MAAEndpoint, error: Optional[str], logs: str) -> None:
    if error:
        logging.error("MAA test failed for %s (on TEE %s): %s", endpoint.dns_name, endpoint.tee, error)
    else:
        logging.info("MAA test succeeded for %s (on TEE %s)", endpoint.dns_name, endpoint.tee)
    if kusto_conn:
        trace_obj = {
            "Time": datetime.now().isoformat(),
            "RandomId": str(uuid4()),
            "Environment": endpoint.env,
            "Region": endpoint.region,
            "ClientRegion": client_region,
            "MAAEndpoint": endpoint.dns_name,
            "TEE": endpoint.tee,
            "Error": error,
            "Logs": logs,
        }

        query_str = f".ingest inline into table {kusto_table} with (format='json') <|\n  "
        query_str += json.dumps(trace_obj)
        query_str += "\n"
        attempt = 0
        success = False
        while attempt < 7:
            try:
                kusto_client.execute(kusto_database, query_str)
                success = True
                break
            except Exception as e:
                attempt += 1
                logging.error("Failed to ingest trace to Kusto (attempt %d): %s", attempt, "".join(traceback.format_exception_only(e)).strip())
                sleep_secs = 5 * (2**(attempt-1)) # 5, 10, 20, 40, 80, 160, 320 seconds
                logging.info("Retrying in %d seconds...", sleep_secs)
                time.sleep(sleep_secs)
        if not success:
            logging.fatal("Unable to log test result to Kusto after %d attempts.", attempt)
            raise Exception("Unable to log test result to Kusto.")


def do_tests(
    endpoints: List[MAAEndpoint],
    test_fn: Callable[[MAAEndpoint], MAATestResult],
) -> None:
    failed: List[MAATestResult] = []
    succeed: List[MAATestResult] = []

    def test(endpoint: MAAEndpoint) -> MAATestResult:
        result = None
        try:
            result = test_fn(endpoint)
        except Exception as e:
            tb = "".join(traceback.format_exception(e)).strip()
            logging.error("Recovered from exception while testing %s: %s", endpoint.dns_name, tb)
            result = MAATestResult(endpoint, str(e), tb)
        report_test_result(endpoint, result.error, result.logs)
        return result

    shuffled_endpoints = endpoints[:]
    random.shuffle(shuffled_endpoints)
    for endpoint in shuffled_endpoints:
        result = test(endpoint)
        if result.error:
            failed.append(result)
        else:
            succeed.append(result)

    logging.info("SUCCESS: %d, FAIL: %d", len(succeed), len(failed))

    if failed:
        logging.info("Re-testing failed endpoints after 10 seconds...")
        time.sleep(10)
        second_time_failed = []
        random.shuffle(failed)
        for r in failed:
            logging.info(f"Re-testing {r.endpoint.dns_name}")
            result = test(r.endpoint)
            if result.error:
                second_time_failed.append(result)
        if second_time_failed:
            second_time_failed.sort(key=lambda r: r.endpoint.dns_name)
            logging.error("The following endpoints still failed twice:")
            for r in second_time_failed:
                logging.error(f"    {r.endpoint.dns_name} (on TEE {r.endpoint.tee}): {r.error}")



def main() -> int:
    global runtime_data

    start_time_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    try:
        cwd = os.getcwd()
        logging.info("Cwd = %s", cwd)
    except OSError as e:
        logging.fatal("Failed to get current working directory: %s", e)
        sys.exit(1)

    runtime_data = json.dumps({"sample_runtime_data": f"Hi from MAA tester (started on {start_time_str})"})
    time_between_tests = 600  # seconds
    maa_endpoint_csv = "/MAA-endpoints.csv"
    maa_endpoints = read_maa_endpoints_csv(maa_endpoint_csv)

    try:
        while True:
            do_tests(maa_endpoints, test_maa)
            time.sleep(time_between_tests)
    except KeyboardInterrupt:
        logging.info("Interrupted, exiting.")
        sys.exit(0)


try:
    main()
except Exception as e:
    logging.fatal("Unhandled exception in main: %s", "".join(traceback.format_exception(e)).strip())
    logging.fatal("Restarting in 60 seconds...")
    time.sleep(60)
    argv = sys.argv
    # argv is the python script name plus arguments
    logging.shutdown()
    os.execlp(sys.executable, sys.executable, *argv)
