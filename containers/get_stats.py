#!/usr/bin/env python3

"""
Read /tcp_send_recv_stats.csv and print per-peer send/recv latency stats.
Outputs a final OUTPUT: line with aggregate avg/min/max across all peers.
"""

import csv
import json
import sys
from collections import defaultdict

CSV_FILE = "/tcp_send_recv_stats.csv"


def main():
    stats = defaultdict(lambda: {"send": [], "recv": []})

    try:
        with open(CSV_FILE, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                peer = row["peer_ip"]
                stats[peer]["send"].append(float(row["send_ms"]))
                stats[peer]["recv"].append(float(row["recv_ms"]))
    except FileNotFoundError:
        print(f"No stats file found at {CSV_FILE}", file=sys.stderr)
        sys.exit(1)

    if not stats:
        print("No data in stats file")
        return

    all_send = []
    all_recv = []
    for peer in sorted(stats.keys()):
        s = stats[peer]["send"]
        r = stats[peer]["recv"]
        all_send.extend(s)
        all_recv.extend(r)
        print(f"-> {peer}:")
        print(
            f"  send: avg={sum(s)/len(s):.1f}ms,min={min(s):.1f}ms,max={max(s):.1f}ms"
        )
        print(
            f"  recv: avg={sum(r)/len(r):.1f}ms,min={min(r):.1f}ms,max={max(r):.1f}ms"
        )

    if all_send and all_recv:
        output = {
            "send_avg": round(sum(all_send) / len(all_send), 1),
            "send_min": round(min(all_send), 1),
            "send_max": round(max(all_send), 1),
            "recv_avg": round(sum(all_recv) / len(all_recv), 1),
            "recv_min": round(min(all_recv), 1),
            "recv_max": round(max(all_recv), 1),
        }
        print(f"OUTPUT: {json.dumps(output)}")


if __name__ == "__main__":
    main()
