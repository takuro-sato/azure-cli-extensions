import sys
from http.server import SimpleHTTPRequestHandler, HTTPServer

class MyHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"Hello from sidecar B\n")

if __name__ == "__main__":
    print("Sidecar started")
    sys.stdout.flush()
    server = HTTPServer(('', 8000), MyHandler)
    print("Starting http server on port 8000")
    server.serve_forever()
