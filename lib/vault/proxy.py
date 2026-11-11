"""proxy mode: forward an HTTP call to the secret's pinned host with the credential attached; no redirects followed."""
import http.client
import json
import ssl
import urllib.parse

from .mode import Mode, Response

METHODS = ("GET", "POST")
PASS_IN = ("content-type", "accept")
PASS_OUT = ("content-type",)
REDACTED = b"[redacted]"


class PathError(ValueError):
    """A path outside the entry's allowed list."""


def allowed_path(path, prefixes):
    """True when path is clean (no dot segments, backslash or empty segment) and under one of prefixes."""
    plain = urllib.parse.unquote(path)
    if "\\" in plain or "//" in plain or any(s in (".", "..") for s in plain.split("/")):
        return False
    return any(plain.startswith(p) for p in prefixes)


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
    """HTTPS to the entry's first pinned host; `upstream` (tests only) sends every call to one plain-HTTP base."""

    def __init__(self, upstream="", timeout=300):
        self.upstream, self.timeout = upstream, timeout

    def _conn(self, host):
        if self.upstream:
            u = urllib.parse.urlsplit(self.upstream)
            return http.client.HTTPConnection(u.hostname, u.port, timeout=self.timeout)
        return http.client.HTTPSConnection(host, 443, context=ssl.create_default_context(), timeout=self.timeout)

    def handle(self, request, entry, value, lease):
        if request.method not in METHODS:
            return Response(405, body=b'{"error":"method not allowed"}')
        if not allowed_path(request.path, entry.paths):
            raise PathError(request.path)
        host = entry.hosts[0]
        url = request.path + (f"?{request.query}" if request.query else "")
        headers = {k: v for k, v in request.headers.items() if k.lower() in PASS_IN}
        headers["Authorization"] = "Bearer " + value.decode()
        conn = self._conn(host)
        try:
            conn.request(request.method, url, body=request.body or None, headers=headers)
            r = conn.getresponse()
            body = r.read().replace(value, REDACTED)
            out = {k: v for k, v in r.getheaders() if k.lower() in PASS_OUT}
            return Response(r.status, out, body, f"{request.method} {host}{request.path}", cost_of(body, entry.cost))
        finally:
            conn.close()
            del headers
