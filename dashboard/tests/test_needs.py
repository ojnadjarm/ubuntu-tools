"""The verdict: which pushes ask the owner, and one `needs` list behind the headline count and the digest list."""
import os, sys, tempfile, unittest
from datetime import datetime, timedelta
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server

DIGEST = ("1. All green, no FAIL. 2. 1 incident: eye-render hand-run killed 09-21 08:26, quiet since. 3. Agent runs 2/2 exit 0. "
          "4. Disk 9%, SMART PASSED, wear 5%, batt health 72% - all flat. 5. Nothing needs you.")


def push(text, t="2026-09-22T08:00:35+02:00"):
    return {"t": t, "kind": "push", "prio": "default", "text": text}


class Needs(unittest.TestCase):
    def test_multi_line_push_keeps_later_lines(self):
        from dash.services import system
        home = tempfile.mkdtemp()
        os.makedirs(os.path.join(home, "agents/log"))
        t = (datetime.now().astimezone() - timedelta(hours=1)).isoformat(timespec="seconds")
        with open(os.path.join(home, "agents/log/notify.log"), "w") as f:
            f.write(t + "\tok\tdefault\t1. 0 incidents; all ok\n2. Disk flat\n3. T1 needs you to decide\n")
        with mock.patch.object(system, "HOME", home):
            ev = system.since_24h()
        self.assertEqual([e["text"] for e in ev], ["1. 0 incidents; all ok\n2. Disk flat\n3. T1 needs you to decide"])
        self.assertTrue(server.asks_owner(ev[0]["text"]))

    def test_runaway_loop_is_one_event_with_count(self):
        from dash.services import system
        home = tempfile.mkdtemp()
        os.makedirs(os.path.join(home, "agents/sentinel/state"))
        now = datetime.now().astimezone()
        ts = [(now - timedelta(minutes=m)).isoformat(timespec="seconds") for m in (45, 30, 15)]
        with open(os.path.join(home, "agents/sentinel/state/sentinel.log"), "w") as f:
            for i, t in enumerate(ts):
                f.write("%s runaway took down sandbox asr (rule3: stale sandbox, %dh old)\n" % (t, 88 + i))
            f.write("%s runaway killed pid 42 (rule3: hand-run Dark Eye body outside dark-eye.service, 2h old): eye-render\n" % ts[0])
            f.write("%s runaway would take down sandbox asr (rule3: stale sandbox, 37h old)\n" % ts[1])
        with mock.patch.object(system, "HOME", home):
            ev = system.since_24h()
        self.assertEqual([(e["kind"], e["t"], e["text"]) for e in ev], [
            ("runaway", ts[2], "took down sandbox asr (rule3: stale sandbox, 90h old) x3"),
            ("runaway", ts[0], "killed a hand-run Dark Eye body outside dark-eye.service, 2h old")])

    def test_stuck_wait_kill_is_an_event(self):
        from dash.services import system
        home = tempfile.mkdtemp()
        os.makedirs(os.path.join(home, "agents/sentinel/state"))
        t = (datetime.now().astimezone() - timedelta(minutes=10)).isoformat(timespec="seconds")
        with open(os.path.join(home, "agents/sentinel/state/sentinel.log"), "w") as f:
            f.write("%s stuck-wait seen pid 408230 (polls x.output unchanged 27 min, no writer; owner agent a71fd5 still running, left alone)\n" % t)
            f.write("%s stuck-wait killed pid 505171 (owner ended; owner agent a51b09): 'until grep -q facts p2.log; do sleep 3; done'\n" % t)
        with mock.patch.object(system, "HOME", home):
            ev = system.since_24h()
        self.assertEqual([(e["kind"], e["t"], e["text"]) for e in ev], [
            ("runaway", t, "stuck-wait killed a wait (owner ended; owner agent a51b09)")])

    def test_old_high_push_still_needs_with_many_newer_pushes(self):
        from dash.services import system
        home = tempfile.mkdtemp()
        os.makedirs(os.path.join(home, "agents/log"))
        now = datetime.now().astimezone()
        with open(os.path.join(home, "agents/log/notify.log"), "w") as f:
            f.write((now - timedelta(hours=23)).isoformat(timespec="seconds") + "\tfail\thigh\tdark-eye body failed to start\n")
            for m in range(25):
                f.write((now - timedelta(minutes=m + 1)).isoformat(timespec="seconds") + "\tok\tdefault\troutine %d\n" % m)
        with mock.patch.object(system, "HOME", home):
            ev = system.since_24h()
            needs = system.verdict({}, [], ev)["needs"]
            with mock.patch.object(system, "swr", return_value={"status": {}, "agents": [], "events": ev}), \
                 mock.patch.object(system, "cache_meta", return_value=(False, {}, None)):
                out = system.payload()
        self.assertEqual([n["text"] for n in needs], ["dark-eye body failed to start"])
        self.assertEqual([n["text"] for n in out["verdict"]["needs"]], ["dark-eye body failed to start"])
        self.assertEqual(len(out["events"]), 20)

    def test_all_clear_digests_are_not_asks(self):
        for text in (DIGEST, "All green. 0 incidents, 0 runaways. Nothing to decide.", "No FAIL; nobody needs you today."):
            self.assertFalse(server.asks_owner(text), text)

    def test_real_asks_still_count(self):
        for text in ("1. 12 incidents, all one loop: eye-render respawned + killed every 2h since 00:15 — needs your fix. 2. Disk 10%.",
                     'toolsmith: 10 open. Top 3: TSP-019, TSP-016 — say "go TSP-019"',
                     "5. Decide: run Dark Eye body under its unit.",
                     "Nothing broke, but TSP-019 needs you",
                     "Two daylight checks need you: buds round trip, mute-key injection."):
            self.assertTrue(server.asks_owner(text), text)

    def test_picks_are_asks(self):
        for text in ("T88 Tuning mockups, pick A/B/C: https://x/t88/ A rack+tubes+gauge column · B rack replaces tubes, 2x2 bank",
                     "T91 buttons: pick A, B or C. https://x/t91/buttons/buttons-1920.png (phone: buttons-400.png)",
                     "T95 readouts: 3 directions (A plates, B dimensioned, C schedule). Pick A/B/C: https://x/t95/readouts/",
                     "Choose A or B for the plate."):
            self.assertTrue(server.asks_owner(text), text)
        self.assertFalse(server.asks_owner("Tuning plate as picked (A, no big tubes): https://x/t88/. Building it now."))

    def test_the_0922_digest_leaves_nothing_to_count(self):
        v = server.verdict({"sections": {}}, [{"name": "digest", "last": {"exit": "0"}}], [push(DIGEST)])
        self.assertEqual((v["ok"], v["needs"], v["problems"], v["asks"]), (True, [], [], []))

    def test_high_failure_push_counts(self):
        e = dict(push("ailearning daily ci failed at ci (rc 1): ✖ the repo itself is clean (1047.97593ms) · ~/agents/log/ailearning-ci.log",
                      "2026-10-03T01:00:42+02:00"), prio="high")
        v = server.verdict({"sections": {}}, [], [e])
        self.assertEqual([(n["kind"], n["text"]) for n in v["needs"]], [("push", e["text"])])
        self.assertFalse(v["ok"])

    def test_failed_agent_run_counts_once(self):
        from dash.services import system
        e = dict(push("agent code-review failed (exit 1)", "2026-10-15T14:41:07+02:00"), prio="high")
        ag = [{"name": "code-review", "last": {"end": "2026-10-15T14:41:06+02:00", "exit": "1"}}]
        with mock.patch.object(system, "resolved", return_value=set()):
            v = server.verdict({"sections": {}}, ag, [e])
        self.assertEqual([n["kind"] for n in v["needs"]], ["push"])
        with mock.patch.object(system, "resolved", return_value={system.push_key(e)}):
            v = server.verdict({"sections": {}}, ag, [e])
        self.assertEqual([n["text"] for n in v["needs"]], ["agent code-review exit 1"])

    def test_headline_and_list_share_one_source(self):
        st = {"sections": {"disk": {"smart": {"state": "FAIL"}}, "net": {"ts": {"state": "OK"}}}}
        ag = [{"name": "toolsmith", "last": {"exit": "143"}}, {"name": "digest", "last": {"exit": "0"}}]
        ev = [push(DIGEST), push('toolsmith: say "go TSP-019"', "2026-09-22T09:00:00+02:00")]
        v = server.verdict(st, ag, ev)
        self.assertEqual([n["kind"] for n in v["needs"]], ["ask", "fail", "agent"])
        self.assertEqual(len(v["problems"]), len(v["needs"]))
        self.assertEqual([a["text"] for a in v["asks"]], [n["text"] for n in v["needs"] if n["kind"] == "ask"])
        self.assertFalse(v["ok"])


if __name__ == "__main__":
    unittest.main()
