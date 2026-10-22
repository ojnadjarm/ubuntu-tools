"""human_cal turns the real OnCalendar forms on this machine into words."""
import json, os, sys, tempfile, unittest
from datetime import datetime, timezone
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dash.services import system

NOW = datetime(2026, 10, 10, 3, 0)


class HumanCal(unittest.TestCase):
    def cal(self, c):
        with mock.patch.object(system, "datetime", wraps=datetime) as dt:
            dt.now.return_value = NOW
            return system.human_cal(c)

    def test_daily_and_days(self):
        self.assertEqual(self.cal("*-*-* 04:30:00"), "daily 04:30")
        self.assertEqual(self.cal("Mon,Thu *-*-* 03:00"), "Mon + Thu 03:00")

    def test_hourly(self):
        self.assertEqual(self.cal("*-*-* *:07:00"), "hourly at :07")
        self.assertEqual(self.cal("*-*-* *:30"), "hourly at :30")

    def test_one_shot(self):
        self.assertEqual(self.cal("2027-01-01 03:00:00"), "once 2027-01-01 03:00")

    def test_parked(self):
        self.assertEqual(self.cal("2099-01-01 00:00:00"), "parked")

    def test_unknown_stays_raw(self):
        self.assertEqual(self.cal("weekly"), "weekly")


class OneCopy(unittest.TestCase):
    def test_timers_and_units_use_runners(self):
        rows = json.dumps([{"unit": "chk.timer", "activates": "chk.service", "next": 1, "last": 0}])
        svc = json.dumps([{"unit": "a.service", "description": "A", "active": "active", "sub": "running"}])
        with mock.patch.object(system.runners, "calendar", return_value="*-*-* 04:30:00"), \
             mock.patch.object(system.runners, "iso", side_effect=lambda v: "iso:%s" % v), \
             mock.patch.object(system, "datetime", wraps=datetime) as dt, \
             mock.patch.object(system, "unit_props", return_value={"a.service": {"ActiveEnterTimestamp": "@5"}}), \
             mock.patch.object(system, "run", side_effect=[rows, svc]):
            dt.now.return_value = NOW
            t = system.user_timers()[0]
            u = system.user_units()[0]
        self.assertEqual((t["every"], t["next"], t["last"]), ("daily 04:30", "iso:1", "iso:0"))
        self.assertEqual(u["since"], "iso:@5")

    def test_agents_schedule_uses_runners(self):
        with tempfile.TemporaryDirectory() as h:
            os.makedirs(os.path.join(h, "agents/x"))
            open(os.path.join(h, "agents/x/BRIEF.md"), "w").close()
            os.makedirs(os.path.join(h, "units/agent@x.timer.d"))
            with mock.patch.object(system, "HOME", h), mock.patch.object(system.runners, "UNIT_DIR", os.path.join(h, "units")), \
                 mock.patch.object(system, "unit_props", return_value={}), \
                 mock.patch.object(system.runners, "calendar", return_value="Mon,Thu *-*-* 03:00"), \
                 mock.patch.object(system.runners, "view", side_effect=lambda s, F, r, hc: r):
                rows = system.agents()
        self.assertEqual(rows[0]["schedule"], "Mon + Thu 03:00")


class Groups(unittest.TestCase):
    def test_orchestrator_unit_is_fleet(self):
        svc = json.dumps([{"unit": "claude-orchestrator.service", "description": "Orch", "active": "active", "sub": "running"}])
        with mock.patch.object(system, "unit_props", return_value={}), mock.patch.object(system, "run", return_value=svc):
            self.assertEqual(system.user_units()[0]["group"], "fleet")


class Since24h(unittest.TestCase):
    def test_naive_line_is_continuation_not_crash(self):
        now = datetime.now(timezone.utc).isoformat()
        with tempfile.TemporaryDirectory() as h:
            os.makedirs(os.path.join(h, "agents/log"))
            with open(os.path.join(h, "agents/log/notify.log"), "w") as f:
                f.write("%s\tx\tdefault\thello\n2026-10-15\n" % now)
            with mock.patch.object(system, "HOME", h):
                ev = system.since_24h()
        self.assertEqual([e["text"] for e in ev], ["hello\n2026-10-15"])

    def sentinel(self, lines):
        now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
        with tempfile.TemporaryDirectory() as h:
            os.makedirs(os.path.join(h, "agents/sentinel/state"))
            with open(os.path.join(h, "agents/sentinel/state/sentinel.log"), "w") as f:
                f.write("".join((now + " " + l if l[0] != " " else l) + "\n" for l in lines))
            with mock.patch.object(system, "HOME", h):
                return system.since_24h()

    def test_fail_fixed_in_same_second_is_one_row_with_outcome(self):
        ev = self.sentinel(["FAIL: docker.moodle-shared\t2/3 up, ports 80,1025,8025;", " Container x  Started", "fixed by bash"])
        self.assertEqual([e["text"] for e in ev], ["FAIL docker.moodle-shared · 2/3 up, ports 80,1025,8025 · fixed"])

    def test_escalation_folds_into_its_fail(self):
        ev = self.sentinel(["FAIL: network.internet\tunreachable;", "unresolved, escalating to Claude: network.internet\tunreachable;"])
        self.assertEqual([e["text"] for e in ev], ["FAIL network.internet · unreachable · escalated"])

    def test_escalation_of_another_check_keeps_its_own_row(self):
        ev = self.sentinel(["FAIL: status.probe\tno valid JSON;", "unresolved, escalating to Claude: docker.moodle45r\t2/3 up;"])
        self.assertEqual(sorted(e["text"] for e in ev), ["FAIL status.probe · no valid JSON", "unresolved, escalating to Claude docker.moodle45r · 2/3 up"])

    def test_housekeeping_rows_drop_paths_and_commands(self):
        raw = ["runaway removed /tmp/claude-1000/-home-x/f950f2b2/scratchpad (rule5: dead session's scratchpad, 141h old)",
               "runaway killed pid 3129957 (rule1: shell loop under a scratchpad, reparented to systemd pid 5742, 2704 min old): /bin/bash -c source x",
               "stuck-wait killed pid 620051 (registered wait, owner agent ac2939 ended): bash ~/.local/bin/wait-for --until [ $(wc -l < y)"]
        ev = self.sentinel(raw)
        self.assertEqual(sorted(e["text"] for e in ev), sorted([
            "removed a dead session's scratchpad, 141h old", "killed a shell loop under a scratchpad, 2704 min old",
            "stuck-wait killed a wait (registered wait, owner agent ac2939 ended)"]))
        self.assertEqual(sorted(e["title"] for e in ev), sorted([raw[0][8:], raw[1][8:], raw[2]]))


if __name__ == "__main__":
    unittest.main()
