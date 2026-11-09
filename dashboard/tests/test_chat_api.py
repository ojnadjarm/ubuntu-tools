"""GET /api/chat, POST /api/chat/post and /seen on a temp store: tailnet gate, owner gate, held 422, ETag 304, cursors."""
import email.message, json, os, sys, tempfile, threading, unittest, urllib.error, urllib.request
from http.server import ThreadingHTTPServer
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server  # noqa: F401
from dash import routes
from dash.http import Handler
from dash.services import chat as svc

LOGIN = "owner@example.com"
ENV = ("HARNESS_HOME", "HARNESS_CONFIG", "CHAT_OWNER_LOGIN", "CHAT_DENY_WORDS", "PROTECTED_PROJECTS", "WORK_REPO_ROOTS", "HARNESS_ENV_LOADED")
LAN, TAILNET = "192.0.2.10", "100.101.102.103"


def dispatch(method, path, ip, headers=None):
    """Status code of a request from ip through Handler.dispatch, with the route's real handler."""
    h = Handler.__new__(Handler)
    h.path, h.client_address, h.command = path, (ip, 0), method
    h.headers = email.message.Message()
    for k, v in (headers or {}).items():
        h.headers[k] = v
    sent = []
    h.json = lambda obj, code=200: sent.append(code)
    h.body_json = lambda limit, empty: {"ch": "harness", "text": "hello", "id": 1}
    h.dispatch(method)
    return sent[-1]


class ChatApi(unittest.TestCase):
    """A real server on loopback over a temp HARNESS_HOME; the owner login is set, the tailscale front is simulated by headers."""

    def setUp(self):
        self.saved = {k: os.environ.get(k) for k in ENV}
        self.tmp = tempfile.TemporaryDirectory()
        conf = os.path.join(self.tmp.name, "config.env")
        open(conf, "w").close()
        for k in ("PROTECTED_PROJECTS", "WORK_REPO_ROOTS", "HARNESS_ENV_LOADED"):
            os.environ.pop(k, None)
        os.environ.update(HARNESS_HOME=self.tmp.name, HARNESS_CONFIG=conf, CHAT_OWNER_LOGIN=LOGIN, CHAT_DENY_WORDS="acme")
        svc.chat_guard.deny_words.cache_clear()
        svc.chat_guard.protected_paths.cache_clear()
        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = "http://127.0.0.1:%d" % self.srv.server_address[1]

    def tearDown(self):
        self.srv.shutdown()
        self.srv.server_close()
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        svc.chat_guard.deny_words.cache_clear()
        self.tmp.cleanup()

    def req(self, path, body=None, login=LOGIN, headers=None):
        """(status, json or None, headers) of a GET, or a POST when body is given; the owner's login header unless login is None."""
        h = dict(headers or {})
        if login:
            h["Tailscale-User-Login"] = login
        data = None
        if body is not None:
            data, h["Content-Type"] = json.dumps(body).encode(), "application/json"
        r = urllib.request.Request(self.base + path, data=data, headers=h)
        try:
            with urllib.request.urlopen(r) as resp:
                raw = resp.read()
                return resp.status, json.loads(raw) if raw else None, resp.headers
        except urllib.error.HTTPError as e:
            raw = e.read()
            return e.code, json.loads(raw) if raw else None, e.headers

    def store_files(self):
        d = os.path.join(self.tmp.name, "state", "chat")
        return sorted(f for f in os.listdir(d) if f.endswith(".jsonl") and f != "audit.jsonl") if os.path.isdir(d) else []

    def test_post_then_read(self):
        code, body, _ = self.req("/api/chat/post", {"ch": "harness", "text": "first"})
        self.assertEqual(code, 200)
        first = body["id"]
        second = self.req("/api/chat/post", {"ch": "harness", "text": "second"})[1]["id"]
        code, body, _ = self.req("/api/chat?ch=harness")
        self.assertEqual(code, 200)
        self.assertEqual([(m["from"], m["text"]) for m in body["messages"]], [("owner", "first"), ("owner", "second")])
        self.assertEqual(body["channels"], [{"ch": "harness", "unread": 0}])
        self.assertEqual([m["id"] for m in self.req("/api/chat?ch=harness&after=%d" % first)[1]["messages"]], [second])

    def test_etag_304_until_something_new(self):
        self.req("/api/chat/post", {"ch": "harness", "text": "one"})
        code, _, hdr = self.req("/api/chat?ch=harness")
        tag = hdr["ETag"]
        self.assertEqual(self.req("/api/chat?ch=harness", headers={"If-None-Match": tag})[0], 304)
        self.req("/api/chat/post", {"ch": "harness", "text": "two"})
        self.assertEqual(self.req("/api/chat?ch=harness", headers={"If-None-Match": tag})[0], 200)

    def test_no_channel_lists_channels_only(self):
        self.req("/api/chat/post", {"ch": "harness", "text": "x"})
        self.assertEqual(self.req("/api/chat")[1], {"messages": [], "channels": [{"ch": "harness", "unread": 0}]})

    def test_held_is_422_and_not_stored(self):
        for text, rule in (("token=abcdefghijklmnop1234", "secret"), ("the ACME ticket", "deny word")):
            code, body, _ = self.req("/api/chat/post", {"ch": "harness", "text": text})
            self.assertEqual((code, body), (422, {"held": rule}), text)
        self.assertEqual(self.store_files(), [])
        with open(os.path.join(self.tmp.name, "state", "chat", "audit.jsonl")) as f:
            audit = f.read()
        self.assertNotIn("abcdefghijklmnop", audit)
        self.assertNotIn("ACME", audit)
        self.assertEqual([json.loads(l)["held"] for l in audit.splitlines()], ["secret", "deny word"])

    def test_bad_input_is_400(self):
        for body in ({"ch": "Bad Channel", "text": "x"}, {"ch": "harness", "text": "x" * 2001}, {"ch": "harness", "text": " "}):
            self.assertEqual(self.req("/api/chat/post", body)[0], 400, body)
        self.assertEqual(self.req("/api/chat/post", {})[:2], (422, {"held": "not text"}))
        self.assertEqual(self.req("/api/chat?ch=../etc")[0], 400)
        self.assertEqual(self.req("/api/chat?ch=harness&after=x")[0], 400)
        self.assertEqual(self.req("/api/chat/seen", {"ch": "harness", "id": "1"})[0], 400)
        self.assertEqual(self.store_files(), [])

    def test_seen_moves_the_owner_cursor(self):
        mid = svc.chat_store.post({"ch": "harness", "from": "ceo", "text": "from the orchestrator"})
        self.assertEqual(self.req("/api/chat")[1]["channels"], [{"ch": "harness", "unread": 1}])
        self.assertEqual(self.req("/api/chat/seen", {"ch": "harness", "id": mid})[:2], (200, {"ok": True}))
        self.assertEqual(self.req("/api/chat")[1]["channels"], [{"ch": "harness", "unread": 0}])

    def test_owner_gate_over_loopback(self):
        for login in (None, "someone@example.com"):
            for path, body in (("/api/chat/post", {"ch": "harness", "text": "x"}), ("/api/chat/seen", {"ch": "harness", "id": 1})):
                self.assertEqual(self.req(path, body, login=login)[0], 403, (path, login))
        os.environ["CHAT_OWNER_LOGIN"] = ""
        self.assertEqual(self.req("/api/chat/post", {"ch": "harness", "text": "x"}, login="")[0], 403)
        self.assertEqual(self.store_files(), [])

    def test_tailnet_gate(self):
        own = {"Tailscale-User-Login": LOGIN}
        for ip, fwd, code in ((LAN, None, 403), ("::ffff:10.0.0.4", None, 403), ("127.0.0.1", LAN, 403),
                              (TAILNET, None, 200), ("::1", None, 200), ("127.0.0.1", TAILNET, 200)):
            hdr = {"X-Forwarded-For": fwd} if fwd else {}
            self.assertEqual(dispatch("GET", "/api/chat", ip, hdr), code, (ip, fwd))
        for path in ("/api/chat/post", "/api/chat/seen"):
            self.assertEqual(dispatch("POST", path, LAN, own), 403, path)
            self.assertEqual(dispatch("POST", path, TAILNET, own), 403, "a tailnet peer straight on the port is not the owner")
            self.assertEqual(dispatch("POST", path, "127.0.0.1", {**own, "X-Forwarded-For": LAN}), 403)
            self.assertEqual(dispatch("POST", path, "127.0.0.1", {**own, "X-Forwarded-For": TAILNET}), 200, path)

    def test_routes_registered(self):
        self.assertIn(svc, server.MODULES, "server.py imports the chat service")
        self.assertTrue(routes.find("GET", "/api/chat") and routes.find("POST", "/api/chat/post") and routes.find("POST", "/api/chat/seen"))


if __name__ == "__main__":
    unittest.main()
