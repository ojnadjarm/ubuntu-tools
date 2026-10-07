"""Sites registry: one listener can hold several sites, each its own row, probed on its own path; no live ports or services are touched."""
import json, unittest
from unittest import mock

from dash.services import sites as S

HOST = S.PUBLIC_HOST


def run(live, answers):
    """sites() over fake listeners; answers maps (port, path) -> HTTP code, anything else does not answer."""
    code = lambda url, method: answers.get((int(url.split(":")[-1].split("/")[0]), "/" + url.split("/", 3)[3]))
    with mock.patch.object(S, "listeners", return_value={p: {"port": p, "pid": None, "proc": "caddy"} for p in live}), \
            mock.patch.object(S, "docker_ps", return_value=[]), \
            mock.patch.object(S, "http_code", side_effect=code):
        return S.sites()


class SitesRows(unittest.TestCase):
    def test_local_sites_are_one_row_each_with_https_links(self):
        rows = run([8072], {(8072, "/ailearning/"): 200, (8072, "/portfolio/"): 200})
        mine = {r["name"]: r for r in rows if r["port"] == 8072}
        self.assertEqual(set(mine), {"ailearning", "Portfolio"})
        self.assertEqual(mine["ailearning"]["url"], "https://%s:8472/ailearning/" % HOST)
        self.assertEqual(mine["Portfolio"]["url"], "https://%s:8472/portfolio/" % HOST)
        for r in mine.values():
            self.assertEqual((r["group"], r["state"], r["tls"]), ("mine", "up", True))
            self.assertTrue(r["what"])

    def test_each_site_is_probed_on_its_own_path(self):
        rows = run([8072], {(8072, "/ailearning/"): 200, (8072, "/portfolio/"): 404})
        state = {r["name"]: r["state"] for r in rows if r["port"] == 8072}
        self.assertEqual(state, {"ailearning": "up", "Portfolio": "warn"})

    def test_sites_service_down_shows_both_sites_down(self):
        rows = run([], {})
        down = {r["name"] for r in rows if r["state"] == "down"}
        self.assertTrue({"ailearning", "Portfolio"} <= down, down)

    def test_retired_preview_and_tailscale_fronts_are_gone(self):
        rows = run([8071, 8470, 8472], {})
        self.assertNotIn(8071, S.SITES)
        self.assertEqual([r["port"] for r in rows if r["port"] in (8470, 8472)], [])
        self.assertEqual([r["state"] for r in rows if r["port"] == 8071], ["stray"])


LINK = "https://%s:8474/FAKESECRETTOKEN/" % HOST


class Fake:
    """Handler stand-in: records the response of a route."""

    def __init__(self, ip):
        self.client_address, self.code, self.headers_out = (ip, 0), None, {}

    def send(self, code, body, ctype):
        self.code = code

    def send_response(self, code):
        self.code = code

    def send_header(self, k, v):
        self.headers_out[k] = v

    def end_headers(self):
        pass


class FinanceTile(unittest.TestCase):
    def rows(self, answers):
        with mock.patch.object(S, "run", return_value=LINK + "\n"):
            return run([8474], answers)

    def test_tile_points_at_the_resolver_and_never_carries_the_token(self):
        rows = self.rows({(8474, "/FAKESECRETTOKEN/"): 200})
        fin = [r for r in rows if r["port"] == 8474]
        self.assertEqual([(r["name"], r["url"], r["group"], r["state"]) for r in fin], [("Finances", "/finance", "mine", "up")])
        self.assertEqual(fin[0]["host"], "%s:8474" % HOST)
        self.assertNotIn("FAKESECRETTOKEN", json.dumps(rows))

    def test_tile_is_down_when_the_page_does_not_answer(self):
        self.assertEqual([r["state"] for r in self.rows({}) if r["port"] == 8474], ["down"])

    def test_tailnet_and_loopback_are_trusted_lan_is_not(self):
        for ip in ("127.0.0.1", "::1", "::ffff:127.0.0.1", "100.100.1.2", "fd7a:115c:a1e0::1"):
            self.assertTrue(S.trusted(ip), ip)
        for ip in ("192.168.50.20", "::ffff:192.168.50.20", "10.0.0.5", "172.17.0.2", "fe80::1"):
            self.assertFalse(S.trusted(ip), ip)

    def test_resolver_redirects_trusted_and_refuses_lan(self):
        with mock.patch.object(S, "run", return_value=LINK + "\n") as cli:
            ok, lan = Fake("100.100.1.2"), Fake("192.168.50.20")
            S.secret_route(ok, "/finance")
            S.secret_route(lan, "/finance")
        self.assertEqual((ok.code, ok.headers_out["Location"], ok.headers_out["Cache-Control"]), (302, LINK, "no-store"))
        self.assertEqual((lan.code, lan.headers_out), (403, {}))
        self.assertEqual(cli.call_count, 1)

    def test_resolver_follows_the_cli_each_time(self):
        h = Fake("127.0.0.1")
        with mock.patch.object(S, "run", return_value="https://%s:9999/NEWTOKEN/\n" % HOST):
            S.secret_route(h, "/finance")
        self.assertEqual(h.headers_out["Location"], "https://%s:9999/NEWTOKEN/" % HOST)

    def test_resolver_503_when_the_cli_prints_nothing(self):
        h = Fake("127.0.0.1")
        with mock.patch.object(S, "run", return_value=""):
            S.secret_route(h, "/finance")
        self.assertEqual(h.code, 503)


if __name__ == "__main__":
    unittest.main()
