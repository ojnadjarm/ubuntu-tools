"""The broker's loopback HTTP listener: /<lease>/<secret>/<path> goes to the gate; nothing is logged here."""
import http.server
import threading
import urllib.parse

from .mode import Request

MAX_BODY = 64 * 1024 * 1024


def make_handler(gate):
    """A request handler class bound to gate."""

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *a):
            pass

        def _send(self, resp):
            self.send_response(resp.status)
            for k, v in resp.headers.items():
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(resp.body)))
            self.end_headers()
            self.wfile.write(resp.body)

        def _plain(self, status, text):
            body = (text + "\n").encode()
            self.send_response(status)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _serve(self):
            u = urllib.parse.urlsplit(self.path)
            parts = u.path.split("/", 3)
            if len(parts) < 4 or not parts[1] or not parts[2]:
                return self._plain(404, "use /<lease>/<secret>/<path>")
            n = int(self.headers.get("Content-Length") or 0)
            if n > MAX_BODY:
                return self._plain(413, "body too large")
            body = self.rfile.read(n) if n else b""
            req = Request(self.command, "/" + parts[3], u.query, dict(self.headers.items()), body)
            self._send(gate.forward(parts[1], parts[2], req))

        do_GET = do_POST = do_PUT = do_DELETE = _serve

        def do_PATCH(self):
            self._plain(405, "method not allowed")

    return Handler


def serve(gate, host, port):
    """Start the listener in a daemon thread; returns the server."""
    server = http.server.ThreadingHTTPServer((host, port), make_handler(gate))
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
