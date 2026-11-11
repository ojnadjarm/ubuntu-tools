"""proxy mode: forward an HTTP call to the secret's pinned host with the credential attached; no redirects followed."""
import http.client
import json
import ssl
import urllib.parse

from .mode import Mode, Response

METHODS = ("GET", "POST")
PASS_IN = ("content-type", "accept", "user-agent")
PASS_OUT = ("content-type",)
REDACTED = b"[redacted]"


class PathError(ValueError):
    """A path outside the entry's allowed list."""


class MethodError(ValueError):
    """A method outside the entry's allowed list."""


def allowed_path(path, prefixes):
    """True when path is clean (no dot segments, backslash or empty segment) and under one of prefixes."""
    plain = urllib.parse.unquote(path)
    if "\\" in plain or "//" in plain or any(s in (".", "..") for s in plain.split("/")):
        return False
    return any(plain.startswith(p) for p in prefixes)


def host_for(entry, path):
    """The pinned host for path: the longest matching route, else the entry's first host."""
    best = max((p for p, _ in entry.routes if path.startswith(p)), key=len, default=None)
    return dict(entry.routes)[best] if best else entry.hosts[0]


def cost_of(body, dotted):
    """The number at a dotted JSON path of body, 0 when absent."""
    if not dotted:
        return 0.0
    try:
        v = json.loads(body)
        for k in dotted.split("."):
            v = v[k]
        return max(0.0, float(v))
    except (ValueError, KeyError, TypeError, IndexError):
        return 0.0


class Proxy(Mode):
    """HTTPS to the path's pinned host; `upstream` (tests only) sends every call to one plain-HTTP base."""

    def __init__(self, upstream="", timeout=300):
        self.upstream, self.timeout = upstream, timeout

    def _conn(self, host):
        if self.upstream:
            u = urllib.parse.urlsplit(self.upstream)
            return http.client.HTTPConnection(u.hostname, u.port, timeout=self.timeout)
        return http.client.HTTPSConnection(host, 443, context=ssl.create_default_context(), timeout=self.timeout)

    def check(self, request, entry):
        """Raise MethodError or PathError when request is outside the entry's lists."""
        if request.method not in (entry.methods or METHODS):
            raise MethodError(request.method)
        if not allowed_path(request.path, entry.paths):
            raise PathError(request.path)

    def send(self, method, host, url, body, headers):
        """One upstream call: (status, headers, body)."""
        conn = self._conn(host)
        try:
            conn.request(method, url, body=body or None, headers=headers)
            r = conn.getresponse()
            return r.status, r.getheaders(), r.read()
        finally:
            conn.close()

    def forward(self, request, entry, auth, hide):
        """Send request to its host with the Authorization header auth; every value in hide is redacted from the answer."""
        host = host_for(entry, request.path)
        url = request.path + (f"?{request.query}" if request.query else "")
        headers = {k: v for k, v in request.headers.items() if k.lower() in PASS_IN}
        headers["Authorization"] = auth
        try:
            status, got, body = self.send(request.method, host, url, request.body, headers)
        finally:
            del headers
        for v in hide:
            body = body.replace(v, REDACTED)
        out = {k: v for k, v in got if k.lower() in PASS_OUT}
        return Response(status, out, body, f"{request.method} {host}{request.path}", cost_of(body, entry.cost))

    def handle(self, request, entry, value, lease):
        self.check(request, entry)
        return self.forward(request, entry, f"{entry.scheme} {value.decode()}", [value])
