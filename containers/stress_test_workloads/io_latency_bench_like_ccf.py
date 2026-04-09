#!/usr/bin/env python3

import argparse
import json
import os
import random
import time


def ns_since_boot():
    return time.clock_gettime_ns(time.CLOCK_BOOTTIME)


def print_with_time(msg):
    ns = ns_since_boot()
    s = ns // 1_000_000_000
    us = (ns % 1_000_000_000) // 1000
    print(f"[{s:5d}.{us:06d}] {msg}", flush=True)


def run_iteration(iter_num, args, run_id):
    files = []
    write_count = 0
    write_sum_us = 0.0
    write_min_us = float('inf')
    write_max_us = 0.0
    high_latency_write_count = 0
    threshold_us = args.latency_thres * 1000

    fsync_count = 0
    fsync_sum_us = 0.0
    fsync_min_us = float('inf')
    fsync_max_us = 0.0
    high_latency_fsync_count = 0
    fsync_threshold_us = args.latency_thres_fsync * 1000

    iter_start = time.monotonic()

    for file_idx in range(args.num_files_per_iter):
        filename = os.path.join(args.work_dir, f"io_bench_{run_id}_{file_idx}.dat")
        files.append(filename)

        buf = random.randbytes(args.block_size)
        written = 0

        fd = os.open(filename, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
        try:
            while written < args.file_size:
                chunk = min(args.block_size, args.file_size - written)
                if chunk < len(buf):
                    buf = buf[:chunk]

                start = time.monotonic()
                os.write(fd, buf)
                elapsed_us = (time.monotonic() - start) * 1_000_000

                write_count += 1
                write_sum_us += elapsed_us
                if elapsed_us < write_min_us:
                    write_min_us = elapsed_us
                if elapsed_us > write_max_us:
                    write_max_us = elapsed_us
                written += chunk

                if elapsed_us > threshold_us:
                    high_latency_write_count += 1
                    print_with_time(
                        f"ERROR: High latency doing write: {elapsed_us / 1000:.3f} ms "
                        f"(file {file_idx}, offset {written - chunk})"
                    )
        finally:
            if args.fsync:
                start = time.monotonic()
                os.fsync(fd)
                fsync_us = (time.monotonic() - start) * 1_000_000
                fsync_count += 1
                fsync_sum_us += fsync_us
                if fsync_us < fsync_min_us:
                    fsync_min_us = fsync_us
                if fsync_us > fsync_max_us:
                    fsync_max_us = fsync_us
                if fsync_us > fsync_threshold_us:
                    high_latency_fsync_count += 1
                    print_with_time(
                        f"ERROR: High latency doing fsync: {fsync_us / 1000:.3f} ms "
                        f"(file {file_idx})"
                    )
            os.close(fd)

    iter_elapsed = time.monotonic() - iter_start
    # Report iteration stats
    if write_count > 0:
        avg_us = write_sum_us / write_count
        total_bytes = args.num_files_per_iter * args.file_size
        mib_per_sec = (total_bytes / (1024 * 1024)) / iter_elapsed
        msg = (
            f"Iteration {iter_num}: {write_count} writes, "
            f"avg={avg_us / 1000:.3f} ms, min={write_min_us / 1000:.3f} ms, "
            f"max={write_max_us / 1000:.3f} ms, {mib_per_sec:.1f} MiB/s, "
            f"high_latency_writes={high_latency_write_count}"
        )
        if fsync_count > 0:
            fsync_avg_us = fsync_sum_us / fsync_count
            msg += (
                f", {fsync_count} fsyncs, "
                f"avg={fsync_avg_us / 1000:.3f} ms, min={fsync_min_us / 1000:.3f} ms, "
                f"max={fsync_max_us / 1000:.3f} ms, "
                f"high_latency_fsyncs={high_latency_fsync_count}"
            )
        print_with_time(msg)

    # Sleep then delete
    if args.delay_per_iter > 0:
        time.sleep(args.delay_per_iter)

    for f in files:
        try:
            os.unlink(f)
        except OSError as e:
            print_with_time(f"WARNING: failed to unlink {f}: {e}")

    return {
        "write_count": write_count,
        "write_sum_us": write_sum_us,
        "write_min_us": write_min_us,
        "write_max_us": write_max_us,
        "high_latency_writes": high_latency_write_count,
        "fsync_count": fsync_count,
        "fsync_sum_us": fsync_sum_us,
        "fsync_min_us": fsync_min_us,
        "fsync_max_us": fsync_max_us,
        "high_latency_fsyncs": high_latency_fsync_count,
        "elapsed_s": iter_elapsed,
        "total_bytes": args.num_files_per_iter * args.file_size,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Sequential-write IO latency benchmark"
    )
    parser.add_argument(
        "--file-size",
        type=int,
        default=30 * 1024 * 1024,
        help="Size of each file in bytes (default: 30 MiB)",
    )
    parser.add_argument(
        "--block-size",
        type=int,
        default=300 * 1024,
        help="Size of each write in bytes (default: 300 KiB)",
    )
    parser.add_argument(
        "--num-files-per-iter",
        type=int,
        default=50,
        help="Number of files to write per iteration (default: 50)",
    )
    parser.add_argument(
        "--delay-per-iter",
        type=float,
        default=0.5,
        help="Seconds to sleep after each iteration (default: 0.5)",
    )
    parser.add_argument(
        "-w",
        "--work-dir",
        default=".",
        help="Directory to create files in (default: .)",
    )
    parser.add_argument(
        "--no-fsync",
        action="store_true",
        default=False,
        help="Disable fsync before closing each file (default: fsync is enabled)",
    )
    parser.add_argument(
        "--latency-thres",
        type=float,
        default=11,
        help="Threshold for high write latency in milliseconds (default: 11)",
    )
    parser.add_argument(
        "--latency-thres-fsync",
        type=float,
        default=1000,
        help="Threshold for high fsync latency in milliseconds (default: 1000)",
    )

    args = parser.parse_args()
    args.fsync = not args.no_fsync
    run_id = f"{random.getrandbits(32):08x}"

    print_with_time(
        f"Starting benchmark (run_id={run_id}): file_size={args.file_size}, block_size={args.block_size}, "
        f"num_files_per_iter={args.num_files_per_iter}, delay_per_iter={args.delay_per_iter}s, "
        f"latency_thres={args.latency_thres}ms, latency_thres_fsync={args.latency_thres_fsync}ms"
    )

    # Aggregated stats across all iterations
    total_write_count = 0
    total_write_sum_us = 0.0
    total_write_min_us = float('inf')
    total_write_max_us = 0.0
    total_high_latency_writes = 0
    total_fsync_count = 0
    total_fsync_sum_us = 0.0
    total_fsync_min_us = float('inf')
    total_fsync_max_us = 0.0
    total_high_latency_fsyncs = 0
    total_elapsed_s = 0.0
    total_bytes = 0

    iter_num = 0
    while True:
        stats = run_iteration(iter_num, args, run_id)
        iter_num += 1

        total_write_count += stats["write_count"]
        total_write_sum_us += stats["write_sum_us"]
        if stats["write_min_us"] < total_write_min_us:
            total_write_min_us = stats["write_min_us"]
        if stats["write_max_us"] > total_write_max_us:
            total_write_max_us = stats["write_max_us"]
        total_high_latency_writes += stats["high_latency_writes"]
        total_fsync_count += stats["fsync_count"]
        total_fsync_sum_us += stats["fsync_sum_us"]
        if stats["fsync_min_us"] < total_fsync_min_us:
            total_fsync_min_us = stats["fsync_min_us"]
        if stats["fsync_max_us"] > total_fsync_max_us:
            total_fsync_max_us = stats["fsync_max_us"]
        total_high_latency_fsyncs += stats["high_latency_fsyncs"]
        total_elapsed_s += stats["elapsed_s"]
        total_bytes += stats["total_bytes"]

        output = {
            "iterations": iter_num,
            "total_writes": total_write_count,
            "write_avg_ms": round(total_write_sum_us / total_write_count / 1000, 3) if total_write_count else 0,
            "write_min_ms": round(total_write_min_us / 1000, 3) if total_write_count else 0,
            "write_max_ms": round(total_write_max_us / 1000, 3) if total_write_count else 0,
            "high_latency_writes": total_high_latency_writes,
            "mib_per_sec": round((total_bytes / (1024 * 1024)) / total_elapsed_s, 1) if total_elapsed_s else 0,
        }
        if total_fsync_count > 0:
            output.update({
                "total_fsyncs": total_fsync_count,
                "fsync_avg_ms": round(total_fsync_sum_us / total_fsync_count / 1000, 3),
                "fsync_min_ms": round(total_fsync_min_us / 1000, 3),
                "fsync_max_ms": round(total_fsync_max_us / 1000, 3),
                "high_latency_fsyncs": total_high_latency_fsyncs,
            })
        print(f"OUTPUT: {json.dumps(output)}", flush=True)


if __name__ == "__main__":
    main()
