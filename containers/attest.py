#!/usr/bin/env python3
"""Confidential WCOW info + attestation payload.

Runs inside a confidential Windows (WCOW) ACI container group. Dumps basic
guest info, then invokes the embedded ``psputilgo.exe`` to prove the guest is
running on a genuine AMD SEV-SNP UVM by fetching a raw hardware attestation
report (via ``amdsnppspapi.dll``, which is bundled into the image next to the
exe).

Mirrors the LCOW ``info`` container's role (embed an attestation tool, fetch a
raw SNP report locally, emit machine-readable output) but for Windows. Output
is scraped by scripts/parse_container_output.py:
  * ``OUTPUT: {json}``  -> merged attestation result (always emitted)
  * ``ERROR: <msg>``    -> emitted only on attestation failure

The ===HOSTNAME===/===EOF=== markers are kept so the legacy info_cwcow grep
check still passes.
"""

import base64
import glob
import json
import os
import platform
import re
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

CERT_URL_PREFIX = "https://kdsintf.amd.com"
NOT_SNP_MARKER = "It's not in SNP environment."

# psputilgo --PrintReport emits each report field as ``  <Name>:  <hex>`` with
# long values wrapped onto indented continuation lines (no field label).
_REPORT_FIELD_RE = re.compile(r"^\s+([A-Za-z0-9_]+):\s*([0-9a-fA-F ]*)$")
_REPORT_CONT_RE = re.compile(r"^\s+[0-9a-fA-F ]+$")


def dump_info():
    print("===HOSTNAME===")
    print(socket.gethostname())
    print("===VERSION===")
    print(platform.platform())
    print("===ARCH===")
    print(os.environ.get("PROCESSOR_ARCHITECTURE", platform.machine()))
    print("===EOF===")
    sys.stdout.flush()


def run_psputil():
    """Return (returncode, combined_output)."""
    exe = os.path.join(os.path.dirname(os.path.abspath(__file__)), "psputilgo.exe")
    if not os.path.exists(exe):
        return None, "psputilgo.exe not found next to attest.py at %s" % exe
    try:
        proc = subprocess.run(
            [exe, "--PrintReport", "--PrintCertUrl"],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        return None, "psputilgo.exe timed out after 120s"
    combined = (proc.stdout or "") + (proc.stderr or "")
    return proc.returncode, combined


def read_cpu_brand():
    """CPUID brand string, e.g. "AMD EPYC 7763 64-Core Processor".

    PROCESSOR_IDENTIFIER only exposes family/model/stepping (identical across
    different SKUs), so prefer the brand string the kernel writes to the
    registry on boot. Returns "" if it can't be read.
    """
    try:
        import winreg

        with winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"HARDWARE\DESCRIPTION\System\CentralProcessor\0",
        ) as k:
            value, _ = winreg.QueryValueEx(k, "ProcessorNameString")
        return value.strip()
    except OSError:
        return ""


def collect_host_info():
    """OS + CPU details visible from the Windows guest environment.

    Available regardless of SNP mode, so we always fold these into OUTPUT.
    """
    return {
        "os_version": platform.platform(),
        "cpu_model": read_cpu_brand() or os.environ.get("PROCESSOR_IDENTIFIER", ""),
        "cpu_arch": os.environ.get("PROCESSOR_ARCHITECTURE", platform.machine()),
    }


def check_security_context_schema():
    """Run the shared schema checker against the UVM reference-info payload."""
    security_context_dirs = glob.glob("/security-context-*")
    if len(security_context_dirs) != 1:
        return False, "expected exactly one /security-context-* directory, found %s" % (
            security_context_dirs,
        )

    reference_info_path = os.path.join(
        security_context_dirs[0], "reference-info-base64"
    )
    checker_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "security_context_schema",
        "check.py",
    )
    sign1util_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "sign1util.exe"
    )
    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            cose_path = os.path.join(temp_dir, "reference-info.cose")
            payload_path = os.path.join(temp_dir, "reference-info.json")
            with open(reference_info_path, "rt") as reference_info_file:
                reference_info = base64.b64decode(reference_info_file.read())
            with open(cose_path, "wb") as cose_file:
                cose_file.write(reference_info)

            print_result = subprocess.run(
                [sign1util_path, "print", "-in", cose_path],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if print_result.returncode != 0:
                output = (print_result.stdout or "") + (print_result.stderr or "")
                return False, "sign1util failed to print reference info: %s" % output

            payload_marker = "payload:"
            output_lines = print_result.stdout.splitlines()
            try:
                payload_index = next(
                    index
                    for index, line in enumerate(output_lines)
                    if line.strip() == payload_marker
                )
            except StopIteration:
                return False, "sign1util output did not contain a payload"

            payload = "\n".join(output_lines[payload_index + 1 :]).strip()
            if not payload:
                return False, "sign1util output contained an empty payload"
            json.loads(payload)
            with open(payload_path, "wt") as payload_file:
                payload_file.write(payload)

            command = [sys.executable, checker_path, "--reference-payload", payload_path]
            if os.environ.get("EXPECT_HOST_AMD_CERT"):
                command.append("--require-host-amd-cert")
            return_code = subprocess.run(command).returncode
            if return_code != 0:
                return False, "security context schema check failed"
            return True, ""
    except Exception as error:
        return False, "failed to check security context schema: %s" % error


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


def finish(result, errors):
    for error in errors:
        print("ERROR: %s" % error)
    if not errors:
        print("info: success")
    print("OUTPUT: %s" % json.dumps(result))
    sys.stdout.flush()

    while True:
        time.sleep(3600)


def parse_report(out):
    """Parse psputilgo's --PrintReport hex dump into ``{field: hexstring}``.

    Ignores the cert-url line and any status messages (which are not indented
    with a ``<Name>:`` label). Returns an empty dict if nothing parses.
    """
    report = {}
    current = None
    for line in out.splitlines():
        m = _REPORT_FIELD_RE.match(line)
        if m:
            current = m.group(1)
            report[current] = m.group(2).replace(" ", "")
            continue
        if current is not None and _REPORT_CONT_RE.match(line):
            report[current] += line.strip().replace(" ", "")
            continue
        current = None
    return report


def main():
    dump_info()

    print("===PSPUTIL===")
    rc, out = run_psputil()
    print(out)
    print("===EOPSPUTIL===")
    sys.stdout.flush()

    result = {
        "workload": "attestation_cwcow",
        "snp_mode": False,
        "report_fetched": False,
        "cert_url": "",
        "exit_code": rc if rc is not None else -1,
        "report": {},
    }
    result.update(collect_host_info())
    errors = []

    is_non_confidential = rc is not None and NOT_SNP_MARKER in out

    if rc is None:
        errors.append(out)
    elif is_non_confidential:
        result["snp_mode"] = False
        errors.append("guest is not running in an SEV-SNP environment")
    elif rc != 0:
        # psputilgo ran but exited non-zero without the not-SNP marker (e.g. a
        # DLL-load panic or an API error). We have NO positive evidence of SNP
        # mode, so leave snp_mode False rather than inferring it from the mere
        # absence of the marker.
        errors.append("psputilgo failed to fetch attestation report (exit %d)" % rc)
    else:
        # A successful report fetch only occurs inside a genuine SEV-SNP guest.
        result["snp_mode"] = True
        result["report_fetched"] = True
        result["report"] = parse_report(out)
        for line in out.splitlines():
            line = line.strip()
            if line.startswith(CERT_URL_PREFIX):
                result["cert_url"] = line
                break

    result["security_context_schema_skipped"] = is_non_confidential
    if not is_non_confidential:
        schema_valid, schema_error = check_security_context_schema()
        result["security_context_schema_valid"] = schema_valid
        if schema_error:
            errors.append(schema_error)

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

    finish(result, errors)


if __name__ == "__main__":
    main()
