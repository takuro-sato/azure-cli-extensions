#!/usr/bin/env python3
"""Non-confidential Windows container info and managed identity checks."""

import json
import os
import platform
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def dump_info():
    print("===HOSTNAME===")
    print(socket.gethostname())
    print("===VERSION===")
    print(platform.platform())
    print("===ARCH===")
    print(os.environ.get("PROCESSOR_ARCHITECTURE", platform.machine()))
    print("===EOF===")


def read_cpu_brand():
    try:
        import winreg

        with winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"HARDWARE\DESCRIPTION\System\CentralProcessor\0",
        ) as key:
            value, _ = winreg.QueryValueEx(key, "ProcessorNameString")
        return value.strip()
    except OSError:
        return ""


def test_managed_identity():
    endpoint = os.environ.get("IDENTITY_ENDPOINT", "")
    secret = os.environ.get("IDENTITY_HEADER", "")
    principal_id = os.environ.get("MANAGED_IDENTITY_PRINCIPAL_ID", "")
    if not endpoint or not secret or not principal_id:
        return False, 0, "managed identity endpoint variables were not injected"

    query = urllib.parse.urlencode(
        {
            "resource": "https://storage.azure.com/",
            "principalId": principal_id,
        }
    )
    separator = "&" if "?" in endpoint else "?"
    request_url = endpoint + separator + query
    last_error = ""
    for attempt in range(1, 6):
        try:
            request = urllib.request.Request(
                request_url,
                headers={"secret": secret},
                method="GET",
            )
            with urllib.request.urlopen(request, timeout=10) as response:
                response.read(1)
            return True, attempt, ""
        except urllib.error.HTTPError as error:
            response_body = error.read().decode("utf-8", errors="replace")
            last_error = "HTTP status: %d; Response: %s" % (
                error.code,
                response_body,
            )
        except Exception as error:
            last_error = str(error)
        if attempt < 5:
            time.sleep(5)
    return False, 5, last_error


def main():
    dump_info()
    result = {
        "workload": "info_wcow",
        "os_version": platform.platform(),
        "cpu_model": read_cpu_brand()
        or os.environ.get("PROCESSOR_IDENTIFIER", ""),
        "cpu_arch": os.environ.get("PROCESSOR_ARCHITECTURE", platform.machine()),
        "snp_mode": False,
        "report_fetched": False,
        "security_context_schema_skipped": True,
    }
    errors = []

    test_identity = bool(os.environ.get("TEST_MANAGED_IDENTITY"))
    result["managed_identity_tested"] = test_identity
    if test_identity:
        identity_success, attempts, identity_error = test_managed_identity()
        result["managed_identity_success"] = identity_success
        result["managed_identity_attempts"] = attempts
        if identity_success:
            print("MANAGED_IDENTITY_TEST_SUCCESS=true")
        else:
            errors.append(
                "failed to retrieve a managed identity token after %d attempts: %s"
                % (attempts, identity_error)
            )

    for error in errors:
        print("ERROR: %s" % error)
    if not errors:
        print("info: success")
    print("OUTPUT: %s" % json.dumps(result))
    sys.stdout.flush()

    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
