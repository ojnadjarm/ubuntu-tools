"""Every route answers only loopback and tailnet callers; a LAN address gets 403 before the handler runs."""
import email.message, os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server
from dash import routes
from dash.http import Handler

POSTS = ["/api/voice/clip", "/api/voice/delete", "/api/voice/clear", "/api/seen", "/api/voice/progress",
         "/api/projects/tickets/close", "/api/projects/tickets/delete", "/api/files/delete", "/api/files/delete-many",
         "/api/files/restore", "/api/docs/delete", "/api/owner-todo/done"]


def post(path, ip, fwd=None, method="POST"):
    """(status sent or None, True when the route handler ran) for a same-origin request from ip, X-Forwarded-For fwd."""
    h = Handler.__new__(Handler)
    h.path, h.client_address, h.headers = path, (ip, 0), email.message.Message()
    if fwd:
        h.headers["X-Forwarded-For"] = fwd
    sent, ran = [], []
    h.send = lambda code, *a, **k: sent.append(code)
    h.json = lambda obj, code=200: sent.append(code)
    real = routes.EXACT.get((method, path))
    routes.EXACT[(method, path)] = lambda hh, p: ran.append(p)
    try:
        h.dispatch(method)
    finally:
        if real:
            routes.EXACT[(method, path)] = real
        else:
            del routes.EXACT[(method, path)]
    return (sent[-1] if sent else None), bool(ran)


class TrustedPosts(unittest.TestCase):
    def test_the_twelve_routes_exist(self):
        self.assertLessEqual(set(POSTS), {p for m, p in routes.EXACT if m == "POST"})

    def test_lan_gets_403_on_every_post_route(self):
        for path in [p for m, p in routes.EXACT if m == "POST"]:
            for ip in ("192.0.2.10", "::ffff:198.51.100.4", "fe80::1%eth9"):
                self.assertEqual(post(path, ip), (403, False), (path, ip))

    def test_loopback_and_tailnet_reach_the_route(self):
        for path in POSTS:
            for ip in ("127.0.0.1", "::1", "100.101.102.103", "fd7a:115c:a1e0::5"):
                self.assertEqual(post(path, ip), (None, True), (path, ip))

    def test_lan_gets_403_on_every_get_route(self):
        paths = [p for m, p in routes.EXACT if m == "GET"] + ["/static/eye.css", "/files/x", "/no/such/page"]
        self.assertLessEqual({"/", "/api/status", "/api/agents"}, set(paths))
        for path in paths:
            for ip in ("192.0.2.10", "::ffff:198.51.100.4", "fe80::1%eth9"):
                self.assertEqual(post(path, ip, method="GET"), (403, False), (path, ip))

    def test_loopback_and_tailnet_reach_get_routes(self):
        for path in ("/", "/api/status", "/api/agents"):
            for ip in ("127.0.0.1", "::1", "100.101.102.103", "fd7a:115c:a1e0::5"):
                self.assertEqual(post(path, ip, method="GET"), (None, True), (path, ip))
        self.assertEqual(post("/api/agents", "127.0.0.1", "192.0.2.10", method="GET"), (403, False))

    def test_tailnet_front_judges_the_forwarded_hop(self):
        path = POSTS[0]
        for fwd in ("100.101.102.103", "192.0.2.10, 100.101.102.103", "fd7a:115c:a1e0::5"):
            self.assertEqual(post(path, "127.0.0.1", fwd), (None, True), fwd)
        for fwd in ("192.0.2.10", "100.101.102.103, 192.0.2.10", "junk"):
            self.assertEqual(post(path, "127.0.0.1", fwd), (403, False), fwd)

    def test_forwarded_header_from_the_lan_is_ignored(self):
        self.assertEqual(post(POSTS[0], "192.0.2.10", "100.101.102.103"), (403, False))


if __name__ == "__main__":
    unittest.main()
