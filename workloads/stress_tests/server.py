"""
A persistant python3 server to respond to our liveness probes,
and extract dmesg without needing policy alterations.
"""

from http.server import BaseHTTPRequestHandler, HTTPServer
from subprocess import check_output, STDOUT, CalledProcessError
from os import getenv


class Handler(BaseHTTPRequestHandler):
  def status(self, code):
    self.send_response(code)
    self.send_header("Content-type", "text/plain")
    self.end_headers()

  def do_GET(self):
    print(f"GET {self.path}", flush=True)
    if self.path == "/index.txt":
      self.status(200)
      self.wfile.write(b"Hello\n")
    elif self.path == "/dmesg.log":
      try:
        out = check_output(["dmesg"], shell=True, stderr=STDOUT)
        self.status(200)
        self.wfile.write(out)
      except CalledProcessError as e:
        self.status(500)
        self.wfile.write(e.output)
        raise
    else:
      self.status(404)
      self.wfile.write(b"Not Found\n")

PORT = int(getenv("PORT", "8000"))
with HTTPServer(("0.0.0.0", PORT), Handler) as server:
  print(f"Listening on port {PORT}", flush=True)
  server.serve_forever()
