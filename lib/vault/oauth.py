"""proxy mode for an OAuth sign-in: the broker keeps the refresh token sealed, refreshes the access token itself and
exchanges a sign-in code itself; the agent gets API answers, never a token or the client secret."""
import base64
import json
import threading
import time
import urllib.parse

from .mode import Response
from .proxy import Proxy, host_for
from .seal import SealError

MARGIN = 60


def _answer(status, **body):
    return Response(status, {"Content-Type": "application/json"}, json.dumps(body).encode())


class OAuthProxy(Proxy):
    """A Proxy that also serves entries with an `oauth` table (client secret name, token path, authorize path)."""

    def __init__(self, sealer, audit, upstream="", timeout=300, clock=time.time):
        super().__init__(upstream, timeout)
        self.sealer, self.audit, self.clock = sealer, audit, clock
        self._access, self._lock = {}, threading.Lock()

    def handle(self, request, entry, value, lease):
        if not entry.oauth:
            return super().handle(request, entry, value, lease)
        self.check(request, entry)
        try:
            return self._oauth(request, entry, lease)
        except SealError:
            return _answer(503, error="the vault could not seal the new sign-in token")

    def _oauth(self, request, entry, lease):
        o = entry.oauth
        if request.path == o["authorize"]:
            return self._authorize(request, entry)
        if request.path == o["token"]:
            return self._sign_in(request, entry, lease)
        for retry in (False, True):
            got = self._token(entry, lease, retry)
            if isinstance(got, Response):
                return got
            resp = self.forward(request, entry, "Bearer " + got.decode(), [got, self.sealer.get(entry.name) or got])
            if resp.status != 401 or retry:
                return resp

    def _client(self, entry):
        """(client id, Basic header) from the client secret `<id>:<secret>`, or None when it is not sealed."""
        raw = self.sealer.get(entry.oauth["client"])
        if not raw or b":" not in raw:
            return None
        return raw.split(b":", 1)[0].decode(), "Basic " + base64.b64encode(raw.strip()).decode()

    def _missing_client(self, entry):
        return _answer(503, error=f"{entry.oauth['client']} is not in the vault: the owner adds it as <client id>:<client "
                                  f"secret> (secret add {entry.oauth['client']}, or the Vault page)")

    def _post_token(self, entry, form, lease, why):
        """POST form to the token path with the client's Basic header; (status, json) and one log line for the client."""
        client = self._client(entry)
        if client is None:
            return None, None
        host = self._host(entry)
        headers = {"Authorization": client[1], "Content-Type": "application/x-www-form-urlencoded"}
        try:
            status, _h, body = self.send("POST", host, entry.oauth["token"], urllib.parse.urlencode(form).encode(), headers)
        finally:
            del headers, client
        self.audit.log({"event": "use", "secret": entry.oauth["client"], "ticket": lease.ticket, "agent": lease.agent,
                        "lease": lease.ref, "result": "ok" if status == 200 else "error", "why": why,
                        "target": f"POST {host}{entry.oauth['token']}", "status": status})
        try:
            return status, json.loads(body)
        except ValueError:
            return status, {}

    def _host(self, entry):
        return host_for(entry, entry.oauth["token"])

    def _keep(self, entry, tok):
        """Cache the access token; seal a refresh token the provider rotated."""
        self._access[entry.name] = (tok["access_token"].encode(), self.clock() + int(tok.get("expires_in", 3600)) - MARGIN)
        new = (tok.get("refresh_token") or "").encode()
        if new and new != self.sealer.get(entry.name):
            self.sealer.put(entry.name, new)

    def _token(self, entry, lease, renew):
        """The cached access token, refreshed when old or when renew; a Response when there is none to get."""
        with self._lock:
            cached = self._access.get(entry.name)
            if cached and not renew and cached[1] > self.clock():
                return cached[0]
            refresh = self.sealer.get(entry.name)
            if refresh is None:
                return _answer(503, error="not signed in: run the sign-in once (pc spotify auth)")
            status, tok = self._post_token(entry, {"grant_type": "refresh_token", "refresh_token": refresh.decode()},
                                           lease, "refresh")
            if status is None:
                return self._missing_client(entry)
            if status != 200 or not tok.get("access_token"):
                self._access.pop(entry.name, None)
                return _answer(503, error=f"the provider refused the token refresh ({status}): sign in again "
                                          "(pc spotify auth)")
            self._keep(entry, tok)
            return self._access[entry.name][0]

    def _authorize(self, request, entry):
        """302 to the provider's sign-in page with the client id; the agent chooses redirect, scope and state."""
        client = self._client(entry)
        if client is None:
            return self._missing_client(entry)
        q = dict(urllib.parse.parse_qsl(request.query))
        form = {"client_id": client[0], "response_type": "code",
                **{k: q[k] for k in ("redirect_uri", "scope", "state") if k in q}}
        url = f"https://{self._host(entry)}{entry.oauth['authorize']}?{urllib.parse.urlencode(form)}"
        return Response(302, {"Location": url}, b"", f"GET {self._host(entry)}{entry.oauth['authorize']}")

    def _sign_in(self, request, entry, lease):
        """Exchange a sign-in code for tokens, seal the refresh token, answer without any token."""
        q = dict(urllib.parse.parse_qsl(request.body.decode(errors="replace")))
        if request.method != "POST" or q.get("grant_type") != "authorization_code" or not q.get("code"):
            return _answer(400, error="only grant_type=authorization_code with a code is accepted here")
        form = {k: q[k] for k in ("grant_type", "code", "redirect_uri") if k in q}
        with self._lock:
            status, tok = self._post_token(entry, form, lease, "sign-in")
            if status is None:
                return self._missing_client(entry)
            if status != 200 or not tok.get("refresh_token"):
                return _answer(502, error=f"the provider refused the sign-in ({status})")
            self._keep(entry, tok)
        return Response(200, {"Content-Type": "application/json"},
                        json.dumps({"ok": True, "sealed": entry.name, "scope": tok.get("scope", "")}).encode(),
                        f"POST {self._host(entry)}{entry.oauth['token']}")
