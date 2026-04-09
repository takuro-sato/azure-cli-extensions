#!/usr/bin/env python3

"""
Write all peer IPs (except self) to /peer_ips.txt atomically.

Usage: populate_peer_ips.py a.a.a.a b.b.b.b c.c.c.c --self-ip b.b.b.b
"""

import argparse
import os
import sys

PEER_FILE = "/peer_ips.txt"
SWAP_FILE = PEER_FILE + ".swp"


def main():
    parser = argparse.ArgumentParser(description="Populate peer IPs file")
    parser.add_argument("ips", nargs="+", help="All peer IP addresses")
    parser.add_argument("--self-ip", required=True, help="This container's IP")
    args = parser.parse_args()

    peers = [ip for ip in args.ips if ip != args.self_ip]
    if not peers:
        print("ERROR: no peers after excluding self-ip", file=sys.stderr)
        sys.exit(1)

    print(f"Self IP: {args.self_ip}")
    print(f"Peer IPs: {peers}")

    with open(SWAP_FILE, "w") as f:
        for ip in peers:
            f.write(ip + "\n")
        f.flush()
        os.fsync(f.fileno())

    os.rename(SWAP_FILE, PEER_FILE)
    print(f"Wrote {len(peers)} peer(s) to {PEER_FILE}")


if __name__ == "__main__":
    main()
