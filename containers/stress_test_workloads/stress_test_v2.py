#!/usr/bin/env python3
"""stress_test_v2.py — unified CPU / memory / local-IO / Azure Files-IO
micro-benchmark suite.

Suite:
  0. Dump environment info (uname, /proc/cpuinfo, lscpu, kernel cmdline,
     Hyper-V host build) so the tracing pipeline can extract them.
  1. sysbench cpu  --threads=1  (3 × 30 s, max)  → sysbench_1t_events_per_sec
  2. sysbench cpu  --threads=4  (3 × 30 s, max)  → sysbench_4t_events_per_sec
    3. fio on local CWD:
       3a. randrw 64k iodepth=64 size=256M (8 jobs)
             → fio_rand_read_mib_per_sec, fio_rand_write_mib_per_sec
       3b. seqwrite 1M size=256M 8 threads 60 s
             → fio_local_seq_write_mib_per_sec,
               fio_local_seq_write_iops,
               fio_local_seq_write_lat_avg_msec
  4. (optional) same pair against an Azure Files Premium SMB share mounted
     at /mnt/azurefile if storage_account / share_name / storage_key env
     vars are set
       → fio_azurefile_rand_read_mib_per_sec,
         fio_azurefile_rand_write_mib_per_sec,
         fio_azurefile_seq_write_mib_per_sec,
         fio_azurefile_seq_write_iops,
         fio_azurefile_seq_write_lat_avg_msec
  5. sysbench memory --threads=4 (3 × 30 s, max) → sysbench_memory_mib_per_sec

Optional env vars (logged only):
  LOCATION, PLATFORM, VM_SKU, CPLAT_BLOB, CONFIDENTIAL, VM_IMAGE
"""

import glob
import json
import os
import re
import subprocess
import sys
import time


SYSBENCH_RUNTIME = 30
SYSBENCH_RUNS = 3
SYSBENCH_GAP_S = 5
# fio params for randrw 64k, 8 threads aggregated (local + azurefile)
FIO_RAND_PARAMS = (
    "--randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 "
    "--name=test --bs=64k --iodepth=64 --readwrite=randrw --size=256M "
    "--numjobs=8 --group_reporting "
)
# fio params for sequential write, 1 MiB block, 8 threads, 60 s (local + azurefile)
FIO_SEQ_PARAMS = (
    "--name=seqwrite --ioengine=libaio --rw=write --bs=1M --size=256M "
    "--direct=1 --numjobs=8 --runtime=60 --time_based --group_reporting "
)

storage_key = os.environ.get("storage_key", "")

def sh(cmd, check=True, capture=False):
    global storage_key

    cmd_redacted = cmd.replace(storage_key, "***") if storage_key else cmd
    print(f"+ {cmd_redacted}", flush=True)
    return subprocess.run(
        cmd, shell=True, check=check,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        text=True,
    )


def emit(obj):
    print(f"OUTPUT: {json.dumps(obj)}", flush=True)


def dump_environment():
    """Mirror containers/info_check.sh lines 5-9 (best effort)."""
    sh("uname -a", check=False, capture=False)
    sh("dmesg 2>/dev/null | grep 'Kernel command line' || true", check=False)
    sh("dmesg 2>/dev/null | grep 'Hyper-V: Host Build' || true", check=False)
    sh(
        "if compgen -G '/security-context-*/reference-info-base64' > /dev/null; "
        "then echo Reference info SHA256SUM: $(base64 -d < /security-context-*/reference-info-base64 | sha256sum); "
        "fi",
        check=False,
    )
    sh("cat /proc/cpuinfo", check=False, capture=False)
    sh("lscpu", check=False, capture=False)
    sh("df -h .", check=False, capture=False)


def dump_cifs_diagnostics():
    """Dump CIFS and block-layer diagnostics after Azure Files fio runs."""
    sh("cat /proc/fs/cifs/DebugData", check=False, capture=False)
    sh("cat /proc/fs/cifs/Stats", check=False, capture=False)
    sh("mount | grep cifs", check=False, capture=False)
    sh(r"cat /proc/crypto | grep -A1 'aesni\|gcm(aes)' | head", check=False, capture=False)


def run_sysbench_max(cmd, parser_re, label):
    """Run a sysbench command SYSBENCH_RUNS times and return the max parsed value."""
    best = None
    for i in range(SYSBENCH_RUNS):
        if i > 0:
            time.sleep(SYSBENCH_GAP_S)
        r = sh(cmd, check=True, capture=True)
        print(r.stdout, flush=True)
        m = re.search(parser_re, r.stdout)
        if not m:
            print(f"ERROR: could not parse {label} run {i+1}", flush=True)
            continue
        val = float(m.group(1))
        print(f"# {label} run {i+1}/{SYSBENCH_RUNS}: {val}", flush=True)
        if best is None or val > best:
            best = val
    return best


def _parse_fio_json(label, raw):
    """Extract and log fio JSON from a mixed JSON+text fio output file.

    Returns the parsed JSON object, printing surrounding non-JSON text to
    stdout so it appears in the log without drowning it in JSON.
    """
    first_brace = raw.find("{")
    if first_brace < 0:
        raise ValueError(f"fio {label} output did not contain JSON")
    try:
        result, json_end = json.JSONDecoder().raw_decode(raw[first_brace:])
    except json.JSONDecodeError as e:
        raise ValueError(f"fio {label} output contained invalid JSON: {e}") from e
    pre = raw[:first_brace]
    post = raw[first_brace + json_end:]
    if pre.strip():
        print(pre, flush=True)
    print(f"[fio {label} JSON omitted from log; parsed below]", flush=True)
    if post.strip():
        print(post, flush=True)
    return result


def run_fio(workdir, label, params=None):
    """Run fio randrw in workdir, return (read_mib, write_mib) or None."""
    if params is None:
        params = FIO_RAND_PARAMS
    json_path = f"/tmp/fio-{label}.json"
    cmd = (
        f"fio {params} "
        f"--directory={workdir} "
        f"--output-format=json,normal --output={json_path}"
    )
    try:
        sh(cmd, check=True)
        with open(json_path) as f:
            raw = f.read()
        job = _parse_fio_json(label, raw)["jobs"][0]
        return (
            round(job["read"]["bw"] / 1024.0, 2),    # KiB/s -> MiB/s
            round(job["write"]["bw"] / 1024.0, 2),
        )
    except (subprocess.CalledProcessError, ValueError, KeyError, IndexError, TypeError) as e:
        print(f"ERROR: fio {label} failed: {e}", flush=True)
        return None
    finally:
        for f in glob.glob(os.path.join(workdir, "test.*.0")):
            try:
                os.unlink(f)
            except FileNotFoundError:
                pass


def run_fio_seqwrite(workdir, label, prefix):
    """Run fio sequential write in workdir.

    Returns a dict of metrics keyed as ``{prefix}_seq_write_*``, or None.
    """
    json_path = f"/tmp/fio-{label}.json"
    cmd = (
        f"fio {FIO_SEQ_PARAMS} "
        f"--directory={workdir} "
        f"--output-format=json,normal --output={json_path}"
    )
    try:
        sh(cmd, check=True)
        with open(json_path) as f:
            raw = f.read()
        write = _parse_fio_json(label, raw)["jobs"][0]["write"]
        return {
            f"{prefix}_seq_write_mib_per_sec": round(write["bw"] / 1024.0, 2),
            f"{prefix}_seq_write_iops": round(write["iops"], 2),
            f"{prefix}_seq_write_lat_avg_msec": round(
                write.get("lat_ns", {}).get("mean", 0) / 1_000_000, 3
            ),
        }
    except (subprocess.CalledProcessError, ValueError, KeyError, IndexError, TypeError) as e:
        print(f"ERROR: fio {label} failed: {e}", flush=True)
        return None
    finally:
        for f in glob.glob(os.path.join(workdir, "seqwrite.*.0")):
            try:
                os.unlink(f)
            except FileNotFoundError:
                pass


def maybe_mount_azurefile():
    """If env vars are set, mount Azure Files SMB share at /mnt/azurefile.

    Returns the mount point if mounted, else None.
    """
    global storage_key

    storage_account = os.environ.get("storage_account")
    share_name = os.environ.get("share_name")
    if not (storage_account and share_name and storage_key):
        print("# Azure Files credentials not set, skipping azurefile fio", flush=True)
        return None
    storage_fqdn = os.environ.get(
        "storage_fqdn", f"{storage_account}.file.core.windows.net"
    )
    mount_dir = os.environ.get("AZUREFILE_MOUNT_DIR", "/mnt/azurefile")
    os.makedirs(mount_dir, exist_ok=True)

    # `closetimeo` was only added to cifs.ko in Linux 5.11. Older kernels
    # (e.g. the 5.10.x ContainerPlat LCOW UVM) reject it with EINVAL.
    kernel_release = os.uname().release
    kernel_match = re.match(r"(\d+)\.(\d+)", kernel_release)
    if kernel_match:
        major_minor = tuple(int(x) for x in kernel_match.groups())
        has_closetimeo = major_minor > (5, 10)
    else:
        has_closetimeo = False
        print(f"# Warning: could not parse kernel version '{kernel_release}', assuming no closetimeo support", flush=True)
    print(f"# kernel: {kernel_release} (closetimeo supported: {has_closetimeo})", flush=True)

    mount_opts = (
        f"vers=3.1.1,cache=strict,username={storage_account},"
        f"password={storage_key},uid=0,noforceuid,gid=0,noforcegid,"
        "file_mode=0777,dir_mode=0777,soft,persistenthandles,nounix,"
        "serverino,mapposix,rsize=1048576,wsize=1048576,"
        "bsize=1048576,echo_interval=60,actimeo=30"
    )
    if has_closetimeo:
        mount_opts += ",closetimeo=1"

    try:
        sh(
            f"mount -t cifs '//{storage_fqdn}/{share_name}' '{mount_dir}' -o '{mount_opts}'",
            check=True,
        )
        return mount_dir
    except subprocess.CalledProcessError as e:
        print(f"ERROR: Azure Files mount failed: {e}", flush=True)
        return None


def main():
    location = os.environ.get("LOCATION", "unknown")
    platform = os.environ.get("PLATFORM", "unknown")
    vm_sku = os.environ.get("VM_SKU", "")
    cplat_blob = os.environ.get("CPLAT_BLOB", "")
    confidential = os.environ.get("CONFIDENTIAL", "")
    vm_image = os.environ.get("VM_IMAGE", "")
    metadata_output = {
        "test": "stress-test-v2",
        "location": location,
        "platform": platform,
        "vm_sku": vm_sku,
        "cplat_blob": cplat_blob,
        "confidential": confidential,
        "vm_image": vm_image,
    }
    print(f"# config: {json.dumps(metadata_output)}", flush=True)

    # --- 0. Environment info -------------------------------------------------
    dump_environment()

    # --- 1. sysbench CPU (1 thread, max of 3 runs) ---------------------------
    cpu_re = r"events per second:\s*([\d.]+)"
    cpu1_max = run_sysbench_max(
        f"sysbench --threads=1 --time={SYSBENCH_RUNTIME} cpu --cpu-max-prime=15000 run",
        cpu_re,
        "sysbench cpu 1t",
    )
    sb_cpu1_out = {"sysbench_1t_events_per_sec": cpu1_max} if cpu1_max is not None else None

    # --- 2. sysbench CPU (4 threads, max of 3 runs) --------------------------
    cpu4_max = run_sysbench_max(
        f"sysbench --threads=4 --time={SYSBENCH_RUNTIME} cpu --cpu-max-prime=15000 run",
        cpu_re,
        "sysbench cpu 4t",
    )
    sb_cpu4_out = {"sysbench_4t_events_per_sec": cpu4_max} if cpu4_max is not None else None

    # --- 3. fio on local CWD -------------------------------------------------
    #   3a. random 64k R/W, 8 threads  → fio_rand_*
    #   3b. sequential 1M write, 8 threads → fio_local_seq_write_*
    local_fio = run_fio(".", "local")
    fio_local_out = None
    if local_fio is not None:
        fio_local_out = {
            "fio_rand_read_mib_per_sec": local_fio[0],
            "fio_rand_write_mib_per_sec": local_fio[1],
        }
    fio_local_seq_out = run_fio_seqwrite(".", "local-seq", "fio_local")

    # --- 4. fio on Azure Files share (optional) -----------------------------
    #   4a. random 64k R/W, 8 threads  → fio_azurefile_rand_*
    #   4b. sequential 1M write, 8 threads → fio_azurefile_seq_write_*
    fio_azf_rand_out = None
    fio_azf_seq_out = None
    az_mount = maybe_mount_azurefile()
    if az_mount is not None:
        try:
            az_fio_rand = run_fio(az_mount, "azurefile-rand")
            if az_fio_rand is not None:
                fio_azf_rand_out = {
                    "fio_azurefile_rand_read_mib_per_sec": az_fio_rand[0],
                    "fio_azurefile_rand_write_mib_per_sec": az_fio_rand[1],
                }
            fio_azf_seq_out = run_fio_seqwrite(az_mount, "azurefile-seq", "fio_azurefile")
            dump_cifs_diagnostics()
        finally:
            sh(f"umount '{az_mount}'", check=False)

    # --- 5. sysbench memory (max of 3 runs) ----------------------------------
    sb_mem_max = run_sysbench_max(
        f"sysbench memory --time={SYSBENCH_RUNTIME} --threads=4 run",
        r"\(([\d.]+)\s*MiB/sec\)",
        "sysbench memory",
    )
    sb_mem_out = {"sysbench_memory_mib_per_sec": sb_mem_max} if sb_mem_max is not None else None

    # Emit OUTPUT lines at the end so they survive upstream log truncation
    # (notably `az vm run-command invoke`).
    emit(metadata_output)
    for out in (sb_cpu1_out, sb_cpu4_out, fio_local_out, fio_local_seq_out, fio_azf_rand_out, fio_azf_seq_out, sb_mem_out):
        if out is not None:
            emit(out)

    print("ALL-DONE", flush=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        print(f"ERROR: command failed: {e}", flush=True)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}", flush=True)
        sys.exit(1)
