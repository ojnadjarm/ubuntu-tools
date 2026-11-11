"""exchange mode: the broker logs in with the sealed password and returns only a short-lived session token."""
import http.client
import json
import ssl
import urllib.parse
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

from .mode import Mode, Response
from .proxy import PathError

SESSION = "/session"
NS = {"s": "urn:partner.soap.sforce.com"}
ENVELOPE = ('<?xml version="1.0" encoding="utf-8"?>'
            '<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/" xmlns:p="urn:partner.soap.sforce.com">'
            '<env:Body><p:login><p:username>{user}</p:username><p:password>{password}</p:password></p:login>'
            '</env:Body></env:Envelope>')


class ValueFormatError(ValueError):
    """The sealed value lacks a key the login needs (names only in the message)."""


def fields(value):
    """KEY=value lines of the sealed value as a dict (quotes stripped)."""
    out = {}
    for line in value.decode("utf-8", "replace").splitlines():
        k, sep, v = line.strip().partition("=")
        if sep and k and not k.startswith("#"):
            out[k.strip()] = v.strip().strip("'\"")
    return out


def _json(status, obj, target=""):
    return Response(status, {"Content-Type": "application/json"}, json.dumps(obj).encode(), target)


class Exchange(Mode):
    """Salesforce SOAP login at the entry's first pinned host and path; `upstream` (tests only) is a plain-HTTP base."""

    def __init__(self, upstream="", timeout=60):
        self.upstream, self.timeout = upstream, timeout

    def _conn(self, host):
        if self.upstream:
            u = urllib.parse.urlsplit(self.upstream)
            return http.client.HTTPConnection(u.hostname, u.port, timeout=self.timeout)
        return http.client.HTTPSConnection(host, 443, context=ssl.create_default_context(), timeout=self.timeout)

    def handle(self, request, entry, value, lease):
        if request.path != SESSION:
            raise PathError(request.path)
        if request.method != "POST":
            return _json(405, {"error": "method not allowed: POST /session"})
        f = fields(value)
        user, password = f.get("SF_USERNAME", ""), f.get("SF_PASSWORD", "") + f.get("SF_SECURITY_TOKEN", "")
        if not user or not password:
            return _json(503, {"error": "the sealed value needs SF_USERNAME and SF_PASSWORD"})
        host, path = entry.hosts[0], entry.paths[0]
        target = f"POST {host}{path}"
        body = ENVELOPE.format(user=escape(user), password=escape(password)).encode()
        conn = self._conn(host)
        try:
            conn.request("POST", path, body=body, headers={"Content-Type": "text/xml; charset=utf-8", "SOAPAction": "login"})
            r = conn.getresponse()
            raw = r.read()
        finally:
            conn.close()
            del body
        hidden = sorted({password, f.get("SF_PASSWORD", ""), escape(password), escape(f.get("SF_PASSWORD", ""))} - {""},
                        key=len, reverse=True)
        for h in hidden:
            raw = raw.replace(h.encode(), b"[redacted]")
        try:
            root = ET.fromstring(raw)
        except ET.ParseError:
            return _json(502, {"error": f"login failed (HTTP {r.status}, not a SOAP answer)"}, target)
        fault = root.find(".//faultstring")
        if r.status != 200 or fault is not None:
            why = (fault.text or "").strip() if fault is not None else f"HTTP {r.status}"
            for h in hidden:
                why = why.replace(h, "[redacted]")
            why = why[:200]
            return _json(401 if fault is not None else 502, {"error": f"login refused: {why}"}, target)
        sid, url = root.find(".//s:result/s:sessionId", NS), root.find(".//s:result/s:serverUrl", NS)
        valid = root.find(".//s:userInfo/s:sessionSecondsValid", NS)
        if sid is None or url is None or not sid.text or not url.text:
            return _json(502, {"error": "login answer without a session"}, target)
        u = urllib.parse.urlsplit(url.text.strip())
        out = {"access_token": sid.text.strip(), "instance_url": f"{u.scheme}://{u.netloc}",
               "expires_in": int(valid.text) if valid is not None and (valid.text or "").isdigit() else None}
        return _json(200, out, target)
