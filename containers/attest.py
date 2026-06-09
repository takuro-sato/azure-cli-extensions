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

import json
import os
import platform
import re
import socket
import subprocess
import sys

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

    if rc is None:
        # psputilgo missing or timed out — hard failure.
        print("ERROR: %s" % out)
        print("OUTPUT: %s" % json.dumps(result))
        sys.exit(1)

    if NOT_SNP_MARKER in out:
        result["snp_mode"] = False
        print("ERROR: guest is not running in an SEV-SNP environment")
        print("OUTPUT: %s" % json.dumps(result))
        sys.exit(1)

    if rc != 0:
        # psputilgo ran but exited non-zero without the not-SNP marker (e.g. a
        # DLL-load panic or an API error). We have NO positive evidence of SNP
        # mode, so leave snp_mode False rather than inferring it from the mere
        # absence of the marker.
        print("ERROR: psputilgo failed to fetch attestation report (exit %d)" % rc)
        print("OUTPUT: %s" % json.dumps(result))
        sys.exit(1)

    # rc == 0 and the not-SNP marker is absent: the tool successfully fetched a
    # report, which only succeeds inside a genuine SEV-SNP guest.
    result["snp_mode"] = True
    result["report_fetched"] = True
    result["report"] = parse_report(out)
    for line in out.splitlines():
        line = line.strip()
        if line.startswith(CERT_URL_PREFIX):
            result["cert_url"] = line
            break

    print("OUTPUT: %s" % json.dumps(result))
    sys.exit(0)


if __name__ == "__main__":
    main()