"""GET /api/chat, POST /api/chat/post, /seen and /upload, GET /api/chat/file/<id> on a temp store under a fake $HOME:
tailnet gate, owner gate, held 422, ETag 304, cursors, attachments, recent and older pages."""
import email.message, http.client, io, json, os, sys, tempfile, threading, time, unittest, urllib.error, urllib.parse, urllib.request
from http.server import ThreadingHTTPServer
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server  # noqa: F401
from dash import routes
from dash.http import Handler
from dash.services import chat as svc

LOGIN = "owner@example.com"
ENV = ("HOME", "HARNESS_HOME", "HARNESS_CONFIG", "ORG_FILE", "CHAT_OWNER_LOGIN", "CHAT_DENY_WORDS", "PROTECTED_PROJECTS", "WORK_REPO_ROOTS", "HARNESS_ENV_LOADED")
LAN, TAILNET = "192.0.2.10", "100.101.102.103"
ORG = {"seats": [{"id": "owner", "name": "You", "role": "owner", "parent": None, "wake": None, "match": None},
                 {"id": "fx", "name": "Fixture", "role": "po", "parent": "owner", "wake": "pull", "match": "~/fx"}]}


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
        org = os.path.join(self.tmp.name, "org.json")
        with open(org, "w") as f:
            json.dump(ORG, f)
        os.environ.update(HOME=self.tmp.name, HARNESS_HOME=self.tmp.name, HARNESS_CONFIG=conf, ORG_FILE=org, CHAT_OWNER_LOGIN=LOGIN, CHAT_DENY_WORDS="acme")
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

    def upload(self, data, name, login=LOGIN):
        """(status, json) of POST /api/chat/upload with the raw bytes and the name in X-File-Name."""
        h = {"Content-Type": "application/octet-stream", "X-File-Name": urllib.parse.quote(name)}
        if login:
            h["Tailscale-User-Login"] = login
        r = urllib.request.Request(self.base + "/api/chat/upload", data=data, headers=h)
        try:
            with urllib.request.urlopen(r) as resp:
                return resp.status, json.loads(resp.read())
        except urllib.error.HTTPError as e:
            raw = e.read()
            return e.code, json.loads(raw) if raw else None

    def fetch(self, path, login=LOGIN):
        """(status, bytes, headers) of a GET."""
        r = urllib.request.Request(self.base + path, headers={"Tailscale-User-Login": login} if login else {})
        try:
            with urllib.request.urlopen(r) as resp:
                return resp.status, resp.read(), resp.headers
        except urllib.error.HTTPError as e:
            return e.code, e.read(), e.headers

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
        self.assertEqual(self.req("/api/chat")[1], {"messages": [], "more": False, "channels": [{"ch": "harness", "unread": 0}],
                                                    "wakes": {"today": {}}, "thinking": []})

    def test_recent(self):
        """recent=1: the newest 50 of every channel, newest last, with more: true while older ones exist."""
        a = svc.chat_store.post({"ch": "org", "from": "fx", "text": "first"})
        ids = [svc.chat_store.post({"ch": "harness", "from": "fx", "text": "h%d" % i}) for i in range(55)]
        b = svc.chat_store.post({"ch": "dm-fx--owner", "from": "fx", "text": "last"})
        body = self.req("/api/chat?recent=1")[1]
        self.assertEqual([m["id"] for m in body["messages"]], ids[-49:] + [b])
        self.assertEqual((body["more"], body["messages"][-1]["ch"]), (True, "dm-fx--owner"))
        older = self.req("/api/chat?recent=1&before=%d" % body["messages"][0]["id"])[1]
        self.assertEqual(([m["id"] for m in older["messages"]], older["more"]), ([a] + ids[:6], False))
        self.assertEqual([m["id"] for m in self.req("/api/chat?recent=1&after=%d" % ids[-1])[1]["messages"]], [b])

    def test_channel_opens_on_newest_50_then_older(self):
        ids = [svc.chat_store.post({"ch": "harness", "from": "fx", "text": "h%d" % i}) for i in range(60)]
        body = self.req("/api/chat?ch=harness")[1]
        self.assertEqual(([m["id"] for m in body["messages"]], body["more"]), (ids[10:], True))
        body = self.req("/api/chat?ch=harness&before=%d" % ids[10])[1]
        self.assertEqual(([m["id"] for m in body["messages"]], body["more"]), (ids[:10], False))
        self.assertEqual(self.req("/api/chat?ch=harness&before=x")[0], 400)

    def png(self):
        from PIL import Image
        b = io.BytesIO()
        Image.new("RGB", (900, 300), (10, 120, 200)).save(b, "PNG")
        return b.getvalue()

    def test_upload_then_post_with_files(self):
        """Type from the bytes, not the name; the post carries the stored metadata, text may be empty."""
        code, img = self.upload(self.png(), "shot.txt")
        self.assertEqual((code, img["name"], img["mime"]), (200, "shot.txt", "image/png"))
        code, txt = self.upload(b"token=abcdefghijklmnop1234 inside is not scanned\n", "../notes.png")
        self.assertEqual((code, txt["name"], txt["mime"], txt["size"]), (200, "notes.png", "text/plain", 49))
        code, body, _ = self.req("/api/chat/post", {"ch": "harness", "text": "", "files": [img["id"], txt["id"]]})
        self.assertEqual(code, 200)
        msg = self.req("/api/chat?ch=harness")[1]["messages"][-1]
        self.assertEqual((msg["from"], msg["text"], msg["files"]), ("owner", "", [img, txt]))
        stored = os.path.join(self.tmp.name, "state", "chat", "files", txt["id"])
        self.assertTrue(os.path.isfile(stored), "kept under the chat store")
        for bad in ({"ch": "harness", "text": "x", "files": ["0" * 16]}, {"ch": "harness", "text": "x", "files": "nope"},
                    {"ch": "harness", "text": "x", "files": [img["id"]] * 6}, {"ch": "harness", "text": "", "files": []}):
            self.assertEqual(self.req("/api/chat/post", bad)[0], 400, bad)

    def test_upload_gates_cap_and_names(self):
        self.assertEqual(self.upload(b"x", "a.txt", login=None)[0], 403)
        self.assertEqual(self.upload(b"x", "a.txt", login="someone@example.com")[0], 403)
        c = http.client.HTTPConnection("127.0.0.1", self.srv.server_address[1])
        c.putrequest("POST", "/api/chat/upload")
        for k, v in (("Tailscale-User-Login", LOGIN), ("X-File-Name", "big.bin"),
                     ("Content-Length", str(svc.chat_files.MAX_BYTES + 1))):
            c.putheader(k, v)
        c.endheaders()
        r = c.getresponse()
        self.assertEqual((r.status, "10 MiB" in json.loads(r.read())["error"]), (413, True), "refused on the header")
        c.close()
        self.assertEqual(self.upload(b"", "empty.txt")[0], 400)
        self.assertEqual(self.upload(b"plain", "the acme plan.txt"), (422, {"held": "deny word"}))
        self.assertEqual(self.upload(b"plain", "ghp_abcdefghijklmnopqrstuvwxyz0123.txt"), (422, {"held": "secret"}))
        self.assertFalse(os.path.exists(os.path.join(self.tmp.name, "state", "chat", "files")), "nothing stored")

    def test_pull_seat_gets_no_attachment(self):
        code, f = self.upload(b"plain", "a.txt")
        self.assertEqual(self.req("/api/chat/post", {"ch": "dm-fx--owner", "text": "see", "files": [f["id"]]})[:2],
                         (422, {"held": "attachment"}))
        self.assertEqual(self.store_files(), [])

    def test_served_image_and_thumb_carry_no_exif(self):
        from PIL import Image
        im = Image.new("RGB", (1200, 800), (200, 30, 30))
        ex = im.getexif()
        ex[0x0112], ex[0x010F] = 6, "CamMaker"
        gps = ex.get_ifd(0x8825)
        gps[1], gps[2] = "N", (48.0, 51.0, 30.0)
        raw = io.BytesIO()
        im.save(raw, "JPEG", exif=ex.tobytes())
        self.assertIn(b"Exif", raw.getvalue())
        code, f = self.upload(raw.getvalue(), "IMG_0001.JPG")
        self.assertEqual((code, f["mime"]), (200, "image/jpeg"))
        for q, ctype, size in (("", "image/jpeg", (800, 1200)), ("?thumb=1", "image/webp", (427, 640))):
            code, data, hdr = self.fetch("/api/chat/file/%s%s" % (f["id"], q))
            self.assertEqual((code, hdr["Content-Type"], hdr["X-Content-Type-Options"]), (200, ctype, "nosniff"), q)
            self.assertNotIn(b"Exif", data, q)
            self.assertNotIn(b"CamMaker", data, q)
            with Image.open(io.BytesIO(data)) as got:
                self.assertEqual((got.size, dict(got.getexif())), (size, {}), "upright, no EXIF " + q)

    def test_file_route_gate_and_download(self):
        code, f = self.upload(b"%PDF-1.4 fixture", "report <1>.pdf")
        self.assertEqual(f["mime"], "application/pdf")
        code, data, hdr = self.fetch("/api/chat/file/" + f["id"])
        self.assertEqual((code, data, hdr["Content-Type"]), (200, b"%PDF-1.4 fixture", "application/pdf"))
        self.assertTrue(hdr["Content-Disposition"].startswith("attachment;"), hdr["Content-Disposition"])
        self.assertEqual(self.fetch("/api/chat/file/%s?thumb=1" % f["id"])[0], 404, "no thumbnail for a non-image")
        for login in (None, "someone@example.com"):
            self.assertEqual(self.fetch("/api/chat/file/" + f["id"], login=login)[0], 403)
        for bad in ("0" * 16, "../../org.json", f["id"] + ".json"):
            self.assertEqual(self.fetch("/api/chat/file/" + bad)[0], 404, bad)

    def test_post_wakes_through_dispatch(self):
        """The panel's post goes through chat_dispatch: @fx is routed to its pull seat, which waits in the store (queued, not parked)."""
        code, body, _ = self.req("/api/chat/post", {"ch": "harness", "text": "@fx are you there"})
        self.assertEqual((code, body["wakes"]), (200, [{"seat": "fx", "outcome": "queued"}]))
        st = os.path.join(self.tmp.name, "state", "chat")
        self.assertFalse(os.path.exists(os.path.join(st, "queue", "fx.jsonl")))
        with open(os.path.join(st, "audit.jsonl")) as f:
            self.assertIn({"wake": "fx", "reason": "mention", "outcome": "queued"},
                          [{k: r[k] for k in ("wake", "reason", "outcome")} for r in map(json.loads, f) if "wake" in r])

    def test_post_to_pull_seat_strict(self):
        """The owner's direct message to a pull seat meets the strict guard: a ticket key is held (422), nothing stored."""
        code, body, _ = self.req("/api/chat/post", {"ch": "dm-fx--owner", "text": "about AB-7"})
        self.assertEqual((code, body), (422, {"held": "ticket key"}))
        self.assertEqual(self.req("/api/chat/post", {"ch": "harness", "text": "about AB-7"})[0], 200)
        self.assertEqual(self.req("/api/chat/post", {"ch": "harness", "text": "nobody named"})[1]["wakes"], [])

    def test_wakes_today_per_seat(self):
        day = os.path.join(self.tmp.name, "state", "chat", "counters")
        os.makedirs(day)
        with open(os.path.join(day, time.strftime("%Y-%m-%d") + ".json"), "w") as f:
            json.dump({"fx": 3}, f)
        self.assertEqual(self.req("/api/chat")[1]["wakes"], {"today": {"fx": 3}})

    def test_thinking(self):
        """A woken PO whose request waits in its inbox is starting in that channel; filed to done/, nobody is thinking."""
        with open(os.environ["ORG_FILE"], "w") as f:
            json.dump({"seats": ORG["seats"] + [{"id": "px", "name": "PX", "role": "po", "parent": "owner", "wake": "po-inbox", "match": "~/px"}]}, f)
        po = os.path.join(self.tmp.name, "po-px")
        for d in ("inbox", "done"):
            os.makedirs(os.path.join(po, d))
        open(os.path.join(po, "inbox", "r1.md"), "w").close()
        svc.chat_thinking.chat_wake.woke("px", [{"ch": "dm-owner--px", "id": 7}], "r1.md")
        got = self.req("/api/chat")[1]["thinking"]
        self.assertEqual([(t["seat"], t["ch"], t["state"]) for t in got], [("px", "dm-owner--px", "starting")])
        os.rename(os.path.join(po, "inbox", "r1.md"), os.path.join(po, "done", "r1.md"))
        self.assertEqual(self.req("/api/chat")[1]["thinking"], [])

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
        for path in ("/api/chat/upload",):
            self.assertEqual(dispatch("POST", path, LAN, own), 403, path)
            self.assertEqual(dispatch("POST", path, TAILNET, own), 403, path)
        for path in ("/api/chat/post", "/api/chat/seen"):
            self.assertEqual(dispatch("POST", path, LAN, own), 403, path)
            self.assertEqual(dispatch("POST", path, TAILNET, own), 403, "a tailnet peer straight on the port is not the owner")
            self.assertEqual(dispatch("POST", path, "127.0.0.1", {**own, "X-Forwarded-For": LAN}), 403)
            self.assertEqual(dispatch("POST", path, "127.0.0.1", {**own, "X-Forwarded-For": TAILNET}), 200, path)

    def test_routes_registered(self):
        self.assertIn(svc, server.MODULES, "server.py imports the chat service")
        self.assertTrue(routes.find("GET", "/api/chat") and routes.find("POST", "/api/chat/post") and routes.find("POST", "/api/chat/seen"))
        self.assertTrue(routes.find("POST", "/api/chat/upload") and routes.find("GET", "/api/chat/file/0123456789abcdef"))


if __name__ == "__main__":
    unittest.main()
