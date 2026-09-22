"""HTTP transport: one-write send() with gzip, ETag/304 and TCP_NODELAY; route dispatch; pages and static files."""
import gzip, hashlib, html, json, os, socket, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from dash import routes
from dash.env import BINDS, BRAND, HERE, PORT
from dash.routes import route
from dash.services.files import MIME

GZ_MIN = 1024
_assets = {}


def compressible(ctype):
    """True for text bodies worth gzipping."""
    return ctype.startswith(("text/", "application/json", "image/svg")) or "javascript" in ctype


def asset(full, ctype, brand=False):
    """(bytes, gzip bytes or None, ETag) of a file, memoised by (path, mtime, size); brand appends HARNESS_BRAND to <title>."""
    st = os.stat(full)
    key = (st.st_mtime_ns, st.st_size)
    hit = _assets.get((full, brand))
    if not hit or hit[0] != key:
        body = open(full, "rb").read()
        tag = '"%x-%x"' % key
        if brand and BRAND:
            body = body.replace(b"</title>", (" · " + html.escape(BRAND)).encode() + b"</title>", 1)
            tag = tag[:-1] + '-%s"' % hashlib.sha1(BRAND.encode()).hexdigest()[:8]
        gz = gzip.compress(body, 6) if len(body) >= GZ_MIN and compressible(ctype) else None
        hit = _assets[(full, brand)] = (key, body, gz, tag)
    return hit[1:]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    wbufsize = 1 << 16

    def setup(self):
        self.request.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        super().setup()

    def log_message(self, *a):
        pass

    def fresh(self, etag):
        """True when the client's If-None-Match already holds etag."""
        return etag in [t.strip() for t in self.headers.get("If-None-Match", "").split(",")]

    def send(self, code, body, ctype, etag=None, gz=None):
        """Buffered into one write; gzip text >= GZ_MIN when accepted; GET 200s get an ETag and answer 304."""
        post = self.command == "POST"
        zipped = len(body) >= GZ_MIN and compressible(ctype) and "gzip" in self.headers.get("Accept-Encoding", "")
        if zipped:
            body = gz or gzip.compress(body, 6)
        if not post and code == 200:
            etag = (etag or '"%s"' % hashlib.sha1(body).hexdigest()[:16])[:-1] + ('-gz"' if zipped else '"')
            if self.fresh(etag):
                self.send_response(304)
                self.send_header("ETag", etag)
                self.send_header("Cache-Control", "no-cache")
                return self.end_headers()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        if zipped:
            self.send_header("Content-Encoding", "gzip")
        if compressible(ctype):
            self.send_header("Vary", "Accept-Encoding")
        if etag and not post and code == 200:
            self.send_header("ETag", etag)
        self.send_header("Cache-Control", "no-store" if post else "no-cache")
        self.end_headers()
        if not getattr(self, "head_only", False):
            self.wfile.write(body)

    def do_HEAD(self):
        """Same headers as GET, no body."""
        self.head_only = True
        try:
            self.do_GET()
        finally:
            self.head_only = False

    def do_GET(self):
        self.dispatch("GET")

    def do_POST(self):
        self.dispatch("POST")

    def dispatch(self, method):
        path = self.path.split("?")[0]
        fn = routes.find(method, path)
        if not fn:
            return self.send(404, b"not found\n", "text/plain")
        fn(self, path)

    def json(self, obj, code=200):
        """Send obj as a JSON body."""
        self.send(code, json.dumps(obj).encode(), "application/json")

    def body_json(self, limit, empty):
        """The request body as JSON, read up to limit bytes; empty when there is none or it does not parse."""
        try:
            raw = self.rfile.read(min(int(self.headers.get("Content-Length") or 0), limit))
            return json.loads(raw) if raw else empty
        except ValueError:
            return empty

    def static(self, path):
        """Serve a published plan page or a shared asset, confined to the dashboard dir."""
        rel = path.lstrip("/")
        if rel.endswith("/"):
            rel += "index.html"
        full = os.path.realpath(os.path.join(HERE, rel))
        if os.path.isdir(full):
            full = os.path.join(full, "index.html")
        base = os.path.join(HERE, rel.split("/")[0])
        if not full.startswith(base + os.sep) or not os.path.isfile(full):
            return self.send(404, b"not found\n", "text/plain")
        ctype = MIME.get(os.path.splitext(full)[1], "text/plain; charset=utf-8")
        body, gz, etag = asset(full, ctype, rel.startswith("static/") and full.endswith(".html"))
        self.send(200, body, ctype, etag, gz)


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class Server6(Server):
    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        Server.server_bind(self)


def main():
    servers = []
    for addr in BINDS:
        try:
            cls = Server6 if ":" in addr else Server
            servers.append(cls((addr, PORT), Handler))
        except OSError as e:
            print("bind %s:%s failed: %s" % (addr, PORT, e), flush=True)
    if not servers:
        raise SystemExit(1)
    for s in servers[1:]:
        threading.Thread(target=s.serve_forever, daemon=True).start()
    print("dashboard on %s:%d" % (",".join(BINDS), PORT), flush=True)
    servers[0].serve_forever()


@route("GET", "/")
@route("GET", "/index.html")
def index_route(h, path):
    body, gz, etag = asset(os.path.join(HERE, "index.html"), "text/html; charset=utf-8", True)
    h.send(200, body, "text/html; charset=utf-8", etag, gz)


@route("GET", "/voice")
def voice_page(h, path):
    h.static("/static/voice.html")


@route("GET", "/pronunciation")
def pronunciation_page(h, path):
    h.static("/static/pronunciation.html")


@route("GET", "/tts/", prefix=True)
def tts_route(h, path):
    h.static("/state/tts/" + os.path.basename(path))


@route("GET", "/plans/", prefix=True)
@route("GET", "/static/", prefix=True)
@route("GET", "/mockups/", prefix=True)
def static_route(h, path):
    h.static(path)
