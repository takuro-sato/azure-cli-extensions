#!/usr/bin/env python3

"""
Aggregate net-liveness stats from multiple get_stats.py outputs and trace
the result to Kusto via trace_step.py.

Each input file should contain a line like:
  OUTPUT: {"send_avg": ..., "send_min": ..., ...}

This script computes the overall avg/min/max across all instances and
calls trace_step.py --complete with the result.

Usage: aggregate_stats.py <stats_output_file_0> [<stats_output_file_1> ...]
"""

import json
import os
import subprocess
import sys

TRACE_SCRIPT = os.path.join(
    os.path.dirname(__file__), "..", "..", "scripts", "tracing", "trace_step.py"
)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <stats_file> [<stats_file> ...]", file=sys.stderr)
        sys.exit(1)

    all_send_avg = []
    all_send_min = []
    all_send_max = []
    all_recv_avg = []
    all_recv_min = []
    all_recv_max = []

    for path in sys.argv[1:]:
        try:
            with open(path, "r") as f:
                for line in f:
                    idx = line.find("OUTPUT:")
                    if idx < 0:
                        continue
                    payload = line[idx + len("OUTPUT:") :].strip()
                    data = json.loads(payload)
                    all_send_avg.append(data["send_avg"])
                    all_send_min.append(data["send_min"])
                    all_send_max.append(data["send_max"])
                    all_recv_avg.append(data["recv_avg"])
                    all_recv_min.append(data["recv_min"])
                    all_recv_max.append(data["recv_max"])
        except (FileNotFoundError, json.JSONDecodeError, KeyError) as e:
            print(f"WARNING: Failed to parse {path}: {e}", file=sys.stderr)

    if not all_send_avg:
        print("No stats found in any input file", file=sys.stderr)
        output = json.dumps({"error": "no stats collected"})
        subprocess.run(
            [TRACE_SCRIPT, "--complete", "--strict", "--err", "No stats collected",
             "--output-from-stdin"],
            input=output.encode(),
        )
        sys.exit(1)

    n = len(all_send_avg)
    result = {
        "instances": n,
        "send_avg": round(sum(all_send_avg) / n, 1),
        "send_min": round(min(all_send_min), 1),
        "send_max": round(max(all_send_max), 1),
        "recv_avg": round(sum(all_recv_avg) / n, 1),
        "recv_min": round(min(all_recv_min), 1),
        "recv_max": round(max(all_recv_max), 1),
    }

    result_json = json.dumps(result, indent=2)
    print(f"Aggregate stats across {n} instances:")
    print(result_json)

    subprocess.run(
        [TRACE_SCRIPT, "--complete", "--strict", "--output-from-stdin"],
        input=result_json.encode(),
        check=True,
    )


if __name__ == "__main__":
    main()
