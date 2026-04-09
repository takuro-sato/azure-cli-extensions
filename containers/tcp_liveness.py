#!/usr/bin/env python3

"""
TCP liveness test: starts a TCP server, waits for /peer_ips.txt, then
connects to all peers and continuously exchanges heartbeat messages,
measuring latency.
"""

import csv
import os
import socket
import sys
import threading
import time
from datetime import datetime, timezone

MESSAGE_SIZE = 4096  # 4 KB
TIMEOUT_MS = 2000  # ms before an operation is considered too slow
CSV_WRITE_WARN_MS = 10  # ms threshold for CSV write warning
PEER_FILE = "/peer_ips.txt"
CSV_FILE = "/tcp_send_recv_stats.csv"
PORT = 8000

csv_lock = threading.Lock()
csv_file_handle = None
csv_writer = None

HEARTBEAT_PAYLOAD = b"\x00" * MESSAGE_SIZE


def utcnow_str():
    return datetime.now(timezone.utc).strftime("%Y/%m/%d %H:%M:%S.%f")[:-3] + "Z"


def init_csv():
    global csv_file_handle, csv_writer
    csv_file_handle = open(CSV_FILE, "a", newline="")
    csv_writer = csv.writer(csv_file_handle)
    csv_writer.writerow(["timestamp", "peer_ip", "send_ms", "recv_ms"])
    csv_file_handle.flush()


def write_csv_row(peer_ip, send_ms, recv_ms):
    ts = utcnow_str()
    with csv_lock:
        t0 = time.monotonic()
        csv_writer.writerow([ts, peer_ip, f"{send_ms:.1f}", f"{recv_ms:.1f}"])
        csv_file_handle.flush()
        write_ms = (time.monotonic() - t0) * 1000
        if write_ms > CSV_WRITE_WARN_MS:
            print(
                f"ERROR: {utcnow_str()}: time taken to write to csv exceeded {write_ms:.0f}ms",
                flush=True,
            )


def recv_exact(sock, n):
    """Receive exactly n bytes from sock."""
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("connection closed")
        buf.extend(chunk)
    return bytes(buf)


def handle_server_connection(conn, addr):
    """Server side: receive a message, reply with MESSAGE_SIZE bytes."""
    peer_ip = addr[0]
    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    try:
        while True:
            data = recv_exact(conn, MESSAGE_SIZE)
            if not data:
                break
            conn.sendall(HEARTBEAT_PAYLOAD)
    except (ConnectionError, OSError) as e:
        print(f"Server connection from {peer_ip} closed: {e}", flush=True)
    finally:
        conn.close()


def run_server():
    """Listen on PORT and accept connections, spawning a handler thread each."""
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    srv.bind(("0.0.0.0", PORT))
    srv.listen(64)
    print(f"TCP server listening on port {PORT}", flush=True)
    while True:
        conn, addr = srv.accept()
        print(f"Server accepted connection from {addr[0]}", flush=True)
        t = threading.Thread(target=handle_server_connection, args=(conn, addr), daemon=True)
        t.start()


def client_loop(peer_ip):
    """Connect to peer_ip:PORT and continuously send/receive heartbeats."""
    timeout_s = TIMEOUT_MS / 1000.0

    while True:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.settimeout(timeout_s)
            sock.connect((peer_ip, PORT))
            print(f"Connected to {peer_ip}:{PORT}", flush=True)
        except (OSError, ConnectionError) as e:
            print(f"Failed to connect to {peer_ip}: {e}, retrying in 2s", flush=True)
            time.sleep(2)
            continue

        try:
            while True:
                overall_start = time.monotonic()

                # Send
                send_start = time.monotonic()
                try:
                    sock.sendall(HEARTBEAT_PAYLOAD)
                except socket.timeout:
                    elapsed = (time.monotonic() - send_start) * 1000
                    print(
                        f"ERROR: {utcnow_str()}: send/receive from {peer_ip} timed out after {elapsed:.0f}ms",
                        flush=True,
                    )
                    break
                send_ms = (time.monotonic() - send_start) * 1000

                if send_ms > TIMEOUT_MS:
                    print(
                        f"ERROR: {utcnow_str()}: took {send_ms:.0f}ms to send a message to {peer_ip}",
                        flush=True,
                    )

                # Receive
                recv_start = time.monotonic()
                try:
                    recv_exact(sock, MESSAGE_SIZE)
                except socket.timeout:
                    elapsed = (time.monotonic() - overall_start) * 1000
                    print(
                        f"ERROR: {utcnow_str()}: send/receive from {peer_ip} timed out after {elapsed:.0f}ms",
                        flush=True,
                    )
                    break
                except ConnectionError:
                    print(f"Connection to {peer_ip} lost, reconnecting...", flush=True)
                    break
                recv_ms = (time.monotonic() - recv_start) * 1000

                if recv_ms > TIMEOUT_MS:
                    print(
                        f"ERROR: {utcnow_str()}: took {recv_ms:.0f}ms to receive a message from {peer_ip} after sending to it",
                        flush=True,
                    )

                total_ms = (time.monotonic() - overall_start) * 1000
                print(
                    f"Sent and received heartbeat from {peer_ip} within {total_ms:.0f}ms.",
                    flush=True,
                )

                write_csv_row(peer_ip, send_ms, recv_ms)

                # Small sleep to avoid busy-loop
                time.sleep(0.5)
        except (ConnectionError, OSError) as e:
            print(f"Connection to {peer_ip} error: {e}, reconnecting...", flush=True)
        finally:
            sock.close()
        time.sleep(2)


def wait_for_peers_and_connect():
    """Poll for PEER_FILE, then start a client thread per peer."""
    print(f"Waiting for {PEER_FILE}...", flush=True)
    while not os.path.exists(PEER_FILE):
        time.sleep(1)
    with open(PEER_FILE) as f:
        peers = [line.strip() for line in f if line.strip()]
    print(f"Found peers: {peers}", flush=True)
    for peer_ip in peers:
        t = threading.Thread(target=client_loop, args=(peer_ip,), daemon=True)
        t.start()


def main():
    init_csv()

    # Start TCP server in a thread
    server_thread = threading.Thread(target=run_server, daemon=True)
    server_thread.start()

    # Start peer connector thread
    connector_thread = threading.Thread(target=wait_for_peers_and_connect, daemon=True)
    connector_thread.start()

    # Keep main thread alive
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
