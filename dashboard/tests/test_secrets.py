"""Agents › Vault on fixtures: /api/secrets shows names and numbers only; the broker's page adds and replaces through a masked field, owner only."""
import http.client, json, os, socket, socketserver, sys, tempfile, threading, unittest
from unittest import mock
from urllib.parse import urlencode

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "lib"))
from dash.services import secrets  # noqa: E402
from vault import page, wire  # noqa: E402
from vault.admin import Admin  # noqa: E402
from vault.audit import Audit  # noqa: E402
from vault.seal import MemorySealer  # noqa: E402

OWNER = "owner@fixture.invalid"
REMOTE = "192.0.2.7"
HOST = "vault.fixture.invalid:8498"
FAKE = "fixture-value-" + os.urandom(6).hex()
REGISTRY = """
[secret.selftest-key]
class = "ruled"
rules = "fixture rule"
used_in = "fixture: a proxied key"
modes = ["proxy"]
hosts = ["example.invalid"]
reissue = "https://example.invalid/keys"

[secret.selftest-file]
class = "free"
used_in = "fixture: a file not moved yet"
legacy = "selftest.env"

[secret.selftest-empty]
class = "critical"
used_in = "fixture: nothing sealed"
"""


class UnixHTTP(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__("localhost", timeout=10)
        self.path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(self.path)


class Fixture(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="vault-v4-")
        reg = os.path.join(self.dir, "registry.toml")
        with open(reg, "w") as f:
            f.write(REGISTRY)
        os.makedirs(os.path.join(self.dir, "home", "secrets"))
        with open(os.path.join(self.dir, "home", "secrets", "selftest.env"), "w") as f:
            f.write("X=fixture\n")
        self.sealer = MemorySealer()
        self.audit = Audit(os.path.join(self.dir, "uses.jsonl"))
        self.admin = Admin(reg, os.path.join(self.dir, "added.json"), self.sealer, self.audit)
        self.sock = os.path.join(self.dir, "admin.sock")
        admin = self.admin

        class H(socketserver.StreamRequestHandler):
            def handle(self):
                wire.write_msg(self.wfile, admin.handle(wire.read_msg(self.rfile), 1))

        self.srv = socketserver.ThreadingUnixStreamServer(self.sock, H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.page_sock = os.path.join(self.dir, "page.sock")
        self.page = page.serve(self.admin, self.page_sock, OWNER, peers={os.getuid()})
        self.env = mock.patch.dict(os.environ, {"FLEET_VAULT_SOCKET": self.sock, "HARNESS_HOME": os.path.join(self.dir, "home")})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        for s in (self.srv, self.page):
            s.shutdown()
            s.server_close()

    def req(self, method, path, form=None, sock=None, **hdr):
        h = {"Host": HOST, "Tailscale-User-Login": OWNER, "X-Forwarded-For": REMOTE}
        h.update({k.replace("_", "-"): v for k, v in hdr.items()})
        h = {k: v for k, v in h.items() if v is not None}
        body = None
        if form is not None:
            body = urlencode(form).encode()
            h.setdefault("Content-Type", "application/x-www-form-urlencoded")
            h.setdefault("Origin", "https://" + HOST)
            h.setdefault("Sec-Fetch-Site", "same-origin")
        c = UnixHTTP(sock or self.page_sock)
        c.request(method, path, body=body, headers=h)
        r = c.getresponse()
        out = (r.status, dict(r.getheaders()), r.read().decode())
        c.close()
        return out

    def stored(self):
        """Every byte the broker wrote to disk in this fixture."""
        out = ""
        for n in ("uses.jsonl", "added.json"):
            p = os.path.join(self.dir, n)
            if os.path.exists(p):
                out += open(p).read()
        return out


class Selftest(Fixture):
    def test_fixture_is_not_the_real_store(self):
        self.assertTrue(self.sock.startswith(tempfile.gettempdir()) and self.page_sock.startswith(self.dir))
        self.assertNotIn("/run/fleet-vault", self.sock + self.page_sock)
        self.assertIsInstance(self.admin.sealer, MemorySealer)
        self.assertEqual(secrets.sock(), self.sock)


class Api(Fixture):
    def test_rows_names_numbers_never_a_value(self):
        self.sealer.put("selftest-key", FAKE.encode())
        for ev in ({"event": "use", "secret": "selftest-key", "ticket": "T1", "agent": "a", "result": "ok"},
                   {"event": "use", "secret": "selftest-key", "ticket": "T2", "result": "ok"},
                   {"event": "use", "secret": "selftest-key", "ticket": "T1", "agent": "a", "result": "ok"},
                   {"event": "use", "secret": "selftest-key", "result": "refused", "why": "no such lease"}):
            self.audit.log(ev)
        s = secrets.summary()
        self.assertEqual(s["error"], "")
        rows = {r["name"]: r for r in s["secrets"]}
        self.assertEqual(sorted(rows), ["selftest-empty", "selftest-file", "selftest-key"])
        k = rows["selftest-key"]
        self.assertEqual((k["class"], k["state"], k["uses_7d"], k["refusals_7d"]), ("ruled", "sealed", 3, 1))
        self.assertEqual([(w["ticket"], w["result"]) for w in k["who"]], [("", "refused"), ("T1", "ok"), ("T2", "ok")])
        self.assertEqual(k["replace"], "/vault/replace?name=selftest-key")
        self.assertEqual(k["reissue"], "https://example.invalid/keys")
        self.assertEqual((rows["selftest-file"]["state"], rows["selftest-empty"]["state"]), ("file", "empty"))
        self.assertIsNotNone(rows["selftest-file"]["since"])
        self.assertEqual(s["add"], "/vault/add")
        self.assertNotIn(FAKE, json.dumps(s))

    def test_broker_down_is_503_with_a_reason(self):
        class H:
            def json(self, obj, code=200):
                self.out = (code, obj)
        with mock.patch.dict(os.environ, {"FLEET_VAULT_SOCKET": os.path.join(self.dir, "none.sock")}):
            h = H()
            secrets.list_route(h, "/api/secrets")
        self.assertEqual(h.out[0], 503)
        self.assertIn("broker unreachable", h.out[1]["error"])


class Page(Fixture):
    def test_add_form_is_masked_and_scriptless(self):
        for path in ("/vault/add", "/add"):
            st, hd, body = self.req("GET", path)
            self.assertEqual(st, 200, path)
            self.assertIn('type="password" name="value"', body)
            self.assertIn('autocomplete="off"', body)
            self.assertNotIn("<script", body.lower())
            self.assertEqual(hd["Cache-Control"], "no-store")
            self.assertIn("default-src 'none'", hd["Content-Security-Policy"])
            self.assertIn("frame-ancestors 'none'", hd["Content-Security-Policy"])
            self.assertEqual(hd["Referrer-Policy"], "same-origin")
            self.assertIn('content="same-origin"', body)
        st, hd, _ = self.req("GET", "/vault/")
        self.assertEqual((st, hd["Location"]), (303, "/vault/add"))
        st, hd, css = self.req("GET", "/vault/page.css")
        self.assertEqual((st, hd["Content-Type"].split(";")[0]), (200, "text/css"))

    def test_add_seals_a_new_name_and_never_echoes(self):
        st, hd, body = self.req("POST", "/vault/put", {"mode": "add", "name": "selftest-card", "class": "critical",
                                                       "used_in": "fixture card", "value": "  " + FAKE + " "})
        self.assertEqual(st, 303)
        self.assertEqual(hd["Location"], "/vault/done?name=selftest-card&event=add")
        self.assertEqual(self.sealer.get("selftest-card"), FAKE.encode())
        e = self.admin.entries["selftest-card"]
        self.assertEqual((e.cls, e.used_in, e.added), ("critical", "fixture card", True))
        last = self.audit.tail(1)[0]
        self.assertEqual((last["event"], last["secret"], last["agent"], last["result"]), ("add", "selftest-card", "vault page", "ok"))
        st, _, done = self.req("GET", hd["Location"])
        self.assertEqual(st, 200)
        self.assertIn("selftest-card is sealed", done)
        for text in (body, done, self.stored()):
            self.assertNotIn(FAKE, text)

    def test_ruled_needs_rules(self):
        st, _, body = self.req("POST", "/vault/put", {"mode": "add", "name": "selftest-r", "class": "ruled",
                                                      "used_in": "fixture", "value": FAKE})
        self.assertEqual(st, 400)
        self.assertIn("needs its rules", body)
        self.assertIn('value="selftest-r"', body)
        self.assertNotIn(FAKE, body)
        self.assertIsNone(self.sealer.get("selftest-r"))
        st, _, _ = self.req("POST", "/vault/put", {"mode": "add", "name": "selftest-r", "class": "ruled",
                                                   "used_in": "fixture", "rules": "only on T9", "value": FAKE})
        self.assertEqual(st, 303)
        self.assertEqual(self.admin.entries["selftest-r"].rules, "only on T9")

    def test_replace_a_known_name(self):
        self.sealer.put("selftest-key", b"old-fixture")
        st, _, form = self.req("GET", "/vault/replace?name=selftest-key")
        self.assertEqual(st, 200)
        self.assertIn('name="mode" value="replace"', form)
        self.assertIn("https://example.invalid/keys", form)
        self.assertNotIn("old-fixture", form)
        st, hd, _ = self.req("POST", "/vault/put", {"mode": "replace", "name": "selftest-key", "value": FAKE})
        self.assertEqual((st, hd["Location"]), (303, "/vault/done?name=selftest-key&event=replace"))
        self.assertEqual(self.sealer.get("selftest-key"), FAKE.encode())
        self.assertEqual(self.admin.entries["selftest-key"].cls, "ruled")
        self.assertEqual(self.req("GET", "/vault/replace?name=nope")[0], 404)
        self.assertEqual(self.req("GET", "/vault/replace?name=../x")[0], 404)

    def test_refused_adds_keep_nothing(self):
        self.sealer.put("selftest-key", b"old-fixture")
        cases = {"re-add of a sealed name": {"mode": "add", "name": "selftest-key", "value": FAKE},
                 "empty value": {"mode": "add", "name": "selftest-x", "class": "free", "used_in": "x", "value": " "},
                 "bad name": {"mode": "add", "name": "Bad/Name", "class": "free", "used_in": "x", "value": FAKE},
                 "replace of an unknown name": {"mode": "replace", "name": "selftest-x", "value": FAKE}}
        for why, form in cases.items():
            st, _, body = self.req("POST", "/vault/put", form)
            self.assertEqual(st, 400, why)
            self.assertNotIn(FAKE, body, why)
        self.assertEqual(self.sealer.get("selftest-key"), b"old-fixture")
        self.assertIsNone(self.sealer.get("selftest-x"))
        self.assertNotIn(FAKE, self.stored())

    def test_only_the_owner_from_another_device(self):
        form = {"mode": "add", "name": "selftest-y", "class": "free", "used_in": "x", "value": FAKE}
        refused = {"another login": {"Tailscale_User_Login": "other@fixture.invalid"},
                   "no login": {"Tailscale_User_Login": None},
                   "from this laptop": {"X_Forwarded_For": "127.0.0.1"},
                   "no source": {"X_Forwarded_For": None},
                   "other origin": {"Origin": "https://evil.invalid"},
                   "cross-site fetch": {"Sec_Fetch_Site": "cross-site"}}
        for why, hdr in refused.items():
            st, _, body = self.req("POST", "/vault/put", form, **hdr)
            self.assertEqual(st, 403, why)
            self.assertNotIn(FAKE, body, why)
        self.assertIsNone(self.sealer.get("selftest-y"))
        st, _, body = self.req("GET", "/vault/add", X_Forwarded_For="127.0.0.1")
        self.assertEqual(st, 200)
        self.assertIn("opened from the laptop itself", body)
        self.assertNotIn('name="value"', body)
        self.assertEqual(self.req("GET", "/vault/add", Tailscale_User_Login="other@fixture.invalid")[0], 403)

    def test_no_owner_login_or_wrong_peer_is_off(self):
        off = os.path.join(self.dir, "off.sock")
        root_only = os.path.join(self.dir, "root.sock")
        servers = [page.serve(self.admin, off, ""), page.serve(self.admin, root_only, OWNER, peers={0} - {os.getuid()})]
        try:
            self.assertEqual(self.req("GET", "/vault/add", sock=off)[0], 403)
            self.assertEqual(self.req("GET", "/vault/add", sock=root_only)[0], 403)
            st, _, _ = self.req("POST", "/vault/put", {"mode": "add", "name": "selftest-z", "class": "free",
                                                       "used_in": "x", "value": FAKE}, sock=root_only)
            self.assertEqual(st, 403)
            self.assertEqual(oct(os.stat(off).st_mode & 0o777), "0o600")
        finally:
            for s in servers:
                s.shutdown()
                s.server_close()
        self.assertIsNone(self.sealer.get("selftest-z"))

    def test_local_addresses(self):
        self.assertTrue(page.is_local("127.0.0.1") and page.is_local("::1") and page.is_local("not-an-ip"))
        self.assertFalse(page.is_local(REMOTE))


if __name__ == "__main__":
    unittest.main()
