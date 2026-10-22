"""Sites registry: one listener can hold several sites, each its own row, probed on its own path; no live ports or services are touched."""
import json, os, tempfile, unittest
from unittest import mock

from dash.services import sites as S

HOST = S.PUBLIC_HOST


def run(live, answers, containers=(), units=None, fronts=None, methods=None, loopback=()):
    """sites() over fake listeners; answers maps (port, path) -> HTTP code, anything else does not answer; methods narrows the answering verbs; loopback ports bind 127.0.0.1 only."""
    def code(url, method):
        if methods and method not in methods:
            return 501
        return answers.get((int(url.split(":")[-1].split("/")[0]), "/" + url.split("/", 3)[3]))
    units = units or {}
    with mock.patch.object(S, "listeners", return_value={p: {"port": p, "pid": p if p in units else None, "proc": "caddy", "loopback": p in loopback} for p in live}), \
            mock.patch.object(S, "docker_ps", return_value=list(containers)), \
            mock.patch.object(S, "proc_unit", side_effect=lambda pid: units.get(pid, "")), \
            mock.patch.object(S, "proc_started", return_value=60), \
            mock.patch.object(S, "serve_fronts", return_value=fronts or {}), \
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


class OwnedListeners(unittest.TestCase):
    def test_a_listener_with_a_unit_or_container_is_up_under_other_not_stray(self):
        rows = run([3000, 6379], {(3000, "/"): 200}, containers=[{"name": "vass-services-redis-1", "state": "running", "status": "1 h", "ports": [6379]}],
                   units={3000: "vass-frontend.service"})
        other = {r["port"]: r for r in rows if r["port"] in (3000, 6379)}
        self.assertEqual({p: (r["group"], r["state"], r["name"]) for p, r in other.items()},
                         {3000: ("other", "up", "vass-frontend"), 6379: ("other", "up", "vass-services-redis-1")})
        self.assertEqual(other[3000]["url"], "http://%s:3000/" % HOST)
        self.assertEqual(other[6379]["url"], "")

    def test_selenium_novnc_port_without_novnc_is_unlisted_and_up_unlinked(self):
        rows = run([4444, 5900, 7900], {(4444, "/"): 200}, containers=[{"name": "moodle-selenium", "state": "running", "status": "1 h", "ports": [4444, 5900, 7900]}])
        self.assertNotIn(7900, S.SITES)
        self.assertIn(5900, S.SITES)
        r = [r for r in rows if r["port"] == 7900][0]
        self.assertEqual((r["group"], r["state"], r["url"]), ("other", "up", ""))

    def test_a_tailscale_front_maps_to_the_site_it_fronts(self):
        rows = run([3001, 8446], {(3001, "/"): 200}, units={3001: "vass-frontend-proxy.service", 8446: "tailscaled.service"}, fronts={8446: 3001})
        self.assertEqual([r["port"] for r in rows if r["port"] == 8446], [])
        r = [r for r in rows if r["port"] == 3001][0]
        self.assertEqual((r["url"], r["tls"], r["state"]), ("https://%s:8446/" % HOST, True, "up"))

    def test_a_secret_page_backend_hides_with_its_front_and_a_self_front_stays(self):
        with mock.patch.object(S, "run", return_value=LINK + "\n"):
            rows = run([8475, 8644], {(8474, "/FAKESECRETTOKEN/"): 200, (8644, "/"): 200}, units={8475: "finance-web.service"}, fronts={8474: 8475, 8644: 8644})
        self.assertEqual(sorted(r["port"] for r in rows if r["port"] in (8474, 8475, 8644)), [8474, 8644])

    def test_a_loopback_only_listener_gets_no_tailnet_http_link(self):
        rows = run([3000, 3001], {(3000, "/"): 200, (3001, "/"): 200}, units={3000: "vass-frontend.service", 3001: "vass-frontend-proxy.service"},
                   fronts={8446: 3001}, loopback={3000, 3001})
        url = {r["port"]: (r["url"], r["state"]) for r in rows if r["port"] in (3000, 3001)}
        self.assertEqual(url, {3000: ("", "up"), 3001: ("https://%s:8446/" % HOST, "up")})

    def test_a_unit_listener_that_does_not_speak_http_is_up_and_unlinked(self):
        rows = run([9229], {(9229, "/"): 400}, units={9229: "dark-eye.service"})
        self.assertEqual([(r["group"], r["state"], r["why"], r["url"], r["tls"]) for r in rows if r["port"] == 9229],
                         [("other", "up", None, "", False)])

    def test_stray_only_without_unit_or_container(self):
        rows = run([3002], {(3002, "/"): 200})
        self.assertEqual([r["state"] for r in rows if r["port"] == 3002], ["stray"])

    def test_every_warn_or_down_row_says_why(self):
        rows = run([7900, 8072], {(8072, "/ailearning/"): 404}, units={7900: "x.service"})
        bad = [r for r in rows if r["state"] in ("warn", "down")]
        self.assertTrue(bad)
        self.assertEqual([r["name"] for r in bad if not r["why"]], [])
        self.assertIn("HTTP 404", [r["why"] for r in rows if r["name"] == "ailearning"][0])


SS_OUT = ('tcp LISTEN 0 4096 127.0.0.1:8070 0.0.0.0:* users:(("python3",pid=42,fd=3))\n'
          'tcp LISTEN 0 4096 [::1]:8070 [::]:* users:(("python3",pid=42,fd=4))\n'
          'tcp LISTEN 0 4096 0.0.0.0:3000 0.0.0.0:*\n'
          'tcp LISTEN 0 4096 127.0.0.53%lo:53 0.0.0.0:*\n'
          'udp UNCONN 0 0 127.0.0.1:323 0.0.0.0:*\n')


class ListenerCache(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        cache = mock.patch.object(S, "LISTENERS_CACHE", os.path.join(self.dir.name, "pc-cache", "listeners"))
        cache.start()
        self.addCleanup(cache.stop)

    def test_two_refreshes_within_ttl_ask_sudo_once(self):
        with mock.patch.object(S, "run", return_value=SS_OUT) as ss:
            a, b = S.listeners(), S.listeners()
        self.assertEqual([c.args[0][:2] for c in ss.call_args_list], [["sudo", "-n"]])
        self.assertEqual(a, b)
        self.assertEqual((a[3000]["loopback"], a[53]["loopback"]), (False, True))
        a = {8070: a[8070]}
        self.assertEqual(a, {8070: {"port": 8070, "pid": 42, "proc": "python3", "loopback": True}})

    def test_stale_cache_reads_again(self):
        with mock.patch.object(S, "run", return_value=SS_OUT) as ss:
            S.listeners()
            with mock.patch.object(S.time, "time", return_value=S.time.time() + S.LISTENERS_TTL + 1):
                S.listeners()
        self.assertEqual(ss.call_count, 2)

    def test_refused_sudo_falls_back_unprivileged_and_caches_nothing(self):
        with mock.patch.object(S, "run", side_effect=lambda cmd, t: "" if cmd[0] == "sudo" else SS_OUT) as ss:
            S.listeners()
            S.listeners()
        self.assertEqual([c.args[0][0] for c in ss.call_args_list], ["sudo", "ss", "sudo", "ss"])
        self.assertFalse(os.path.exists(S.LISTENERS_CACHE))


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
        self.assertEqual([(r["state"], r["why"]) for r in self.rows({}) if r["port"] == 8474], [("down", "no HTTP answer")])

    def test_tile_is_up_when_head_is_refused_but_get_answers(self):
        with mock.patch.object(S, "run", return_value=LINK + "\n"):
            rows = run([8474], {(8474, "/FAKESECRETTOKEN/"): 200}, methods={"GET"})
        self.assertEqual([(r["state"], r["why"]) for r in rows if r["port"] == 8474], [("up", None)])

    def test_tile_warn_says_the_http_code(self):
        fin = [r for r in self.rows({(8474, "/FAKESECRETTOKEN/"): 500}) if r["port"] == 8474]
        self.assertEqual([(r["state"], r["why"]) for r in fin], [("warn", "HTTP 500")])

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
