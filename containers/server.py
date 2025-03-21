#!/usr/bin/env python3

"""
A persistant python3 server to respond to our curl checks, report uptime, and
extract dmesg without needing policy alterations.
"""

from http.server import BaseHTTPRequestHandler, HTTPServer
from subprocess import check_output, STDOUT, CalledProcessError
from os import getenv
from datetime import datetime, timezone


def checked_exec_get_output(cmd: str) -> bytes:
    return check_output(cmd, shell=True, stderr=STDOUT)


startup_time = datetime.now(timezone.utc)
startup_str = (
    f"Server started at {startup_time.isoformat()}\n\n"
    + f"uptime:\n{checked_exec_get_output('uptime').decode('utf-8')}\n"
    + f"uname -a:\n{checked_exec_get_output('uname -a').decode('utf-8')}\n"
)
req_count = 0


class Handler(BaseHTTPRequestHandler):
    def status(self, code):
        self.send_response(code)
        self.send_header("Content-type", "text/plain")
        self.end_headers()

    def do_GET(self):
        global req_count
        print(f"GET {self.path}", flush=True)
        if self.path in ["/", "/index.txt"]:
            req_received_at = datetime.now(timezone.utc)
            req_count += 1
            self.status(200)
            self.wfile.write(b"Hello from container!\n")
            self.wfile.write(startup_str.encode("utf-8"))
            self.wfile.write(
                f"Request received at {req_received_at.isoformat()} ".encode("utf-8")
            )
            delta = req_received_at - startup_time
            self.wfile.write(
                f"which is {delta.total_seconds()}s after startup.\n".encode("utf-8")
            )
            self.wfile.write(
                f"Request to / received including this one: {req_count}.\n".encode(
                    "utf-8"
                )
            )
        elif self.path == "/dmesg.log":
            try:
                self.status(200)
                self.wfile.write(checked_exec_get_output("dmesg"))
            except CalledProcessError as e:
                self.status(500)
                self.wfile.write(e.output)
                raise
        else:
            self.status(404)
            self.wfile.write(b"Not Found\n")


PORT = int(getenv("PORT", getenv("PORT", 80)))
with HTTPServer(("0.0.0.0", PORT), Handler) as server:
    print(f"Listening on port {PORT}", flush=True)
    print(startup_str, flush=True)
    server.serve_forever()
