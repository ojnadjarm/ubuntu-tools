"""Agent runner kinds on fixture unit states: timer-agent, bash-timer, service; never the real units."""
import json, os, sys, tempfile, unittest
from unittest import mock
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dash.services import runners

T0 = 1791385945  # a fixed unix second
ROW = {"name": "x", "enabled": "disabled", "schedule": "2099-01-01 00:00:00", "next": "",
       "last": {"end": "2026-09-22T12:50:48+02:00", "exit": "0", "seconds": "64"}}


def facts(units, tmux=None, nxt=None, cal=None):
    return {"units": units, "tmux": tmux or {}, "next": nxt or {}, "cal": cal or {}}


class Env(unittest.TestCase):
    def test_env_keys_and_spec(self):
        with tempfile.NamedTemporaryFile("w", suffix=".env", delete=False) as f:
            f.write('MODEL=opus\nSCHEDULE="2099-01-01 00:00:00"\nRUNNER_KIND=bash-timer   # comment\nRUNNER_UNIT=chk.timer\n')
        try:
            env = runners.env_keys(f.name)
        finally:
            os.unlink(f.name)
        self.assertEqual(env["SCHEDULE"], "2099-01-01 00:00:00")
        self.assertEqual(runners.spec("s", env), {"kind": "bash-timer", "unit": "chk.timer", "tmux": ""})
        self.assertEqual(runners.spec("s", {})["unit"], "agent@s.timer")
        self.assertEqual(runners.spec("s", {"RUNNER_KIND": "bogus", "RUNNER_UNIT": "a"})["kind"], "timer-agent")


class Kinds(unittest.TestCase):
    def test_timer_agent_keeps_row(self):
        s = runners.spec("x", {})
        ok = runners.view(s, facts({}), dict(ROW, enabled="enabled"))
        self.assertEqual((ok["kind"], ok["on"], ok["health"], ok["schedule"]), ("timer-agent", True, "ok", ROW["schedule"]))
        bad = runners.view(s, facts({}), dict(ROW, enabled="enabled", last={"end": "x", "exit": "1"}))
        self.assertEqual(bad["health"], "bad")
        self.assertEqual(runners.view(s, facts({}), ROW)["health"], "off")

    def bash(self, timer_state="active", result="success", status="0"):
        s = {"kind": "bash-timer", "unit": "chk.timer", "tmux": ""}
        units = {"chk.timer": {"UnitFileState": "enabled", "ActiveState": timer_state, "LastTriggerUSec": "@%d" % T0, "Triggers": "chk.service"},
                 "chk.service": {"ActiveState": "inactive", "Result": result, "ExecMainStatus": status,
                                 "ExecMainStartTimestamp": "@%d" % T0, "ExecMainExitTimestamp": "@%d" % (T0 + 2)}}
        return runners.view(s, facts(units, nxt={"chk.timer": "2026-10-07T17:27:25+02:00"}, cal={"chk.timer": "15min"}), ROW,
                            lambda c: "every 15 min" if c == "15min" else c)

    def test_bash_timer_on(self):
        r = self.bash()
        self.assertEqual((r["kind"], r["on"], r["health"], r["enabled"]), ("bash-timer", True, "ok", "enabled"))
        self.assertEqual(r["schedule"], "every 15 min")
        self.assertEqual(r["next"], "2026-10-07T17:27:25+02:00")
        self.assertEqual((r["last"]["exit"], r["last"]["seconds"]), ("0", "2"))
        self.assertTrue(r["last"]["end"])
        self.assertEqual(r["fallback"]["end"], ROW["last"]["end"])

    def test_bash_timer_failed_and_down(self):
        self.assertEqual(self.bash(result="exit-code", status="1")["health"], "bad")
        down = self.bash(timer_state="inactive")
        self.assertEqual((down["on"], down["health"]), (False, "bad"))

    def svc(self, state="active", tmux=True):
        s = {"kind": "service", "unit": "brain.service", "tmux": "notes"}
        units = {"brain.service": {"UnitFileState": "disabled", "ActiveState": state, "SubState": "exited", "ActiveEnterTimestamp": "@%d" % T0}}
        return runners.view(s, facts(units, tmux={"notes": "2026-10-07T17:18:33+02:00"} if tmux else {}), dict(ROW, last={}))

    def test_service_states(self):
        on = self.svc()
        self.assertEqual((on["kind"], on["on"], on["health"], on["schedule"]), ("service", True, "ok", "always on"))
        self.assertEqual(on["runner"]["since"], "2026-10-07T17:18:33+02:00")
        self.assertEqual(self.svc(tmux=False)["health"], "warn")
        self.assertEqual(self.svc(state="inactive", tmux=True)["health"], "warn")
        off = self.svc(state="inactive", tmux=False)
        self.assertEqual((off["on"], off["health"]), (False, "off"))
        self.assertEqual(self.svc(state="failed", tmux=False)["health"], "bad")


class Facts(unittest.TestCase):
    def test_batched_reads(self):
        calls = []

        def props(p, units):
            calls.append(units)
            return {"chk.timer": {"Triggers": "chk.service"}} if "chk.timer" in units else {}

        out = {"tmux": "notes %d\nclaude 1\n" % T0, "list-timers": json.dumps([{"unit": "chk.timer", "next": T0 * 10**6}])}
        fake = lambda cmd, t=0: out["tmux"] if cmd[0] == "tmux" else out["list-timers"]
        specs = [{"kind": "timer-agent", "unit": "agent@a.timer", "tmux": ""}, {"kind": "bash-timer", "unit": "chk.timer", "tmux": ""},
                 {"kind": "service", "unit": "brain.service", "tmux": "notes"}]
        with mock.patch.object(runners, "run", fake), mock.patch.object(runners, "calendar", lambda u: "15min"):
            F = runners.facts(specs, props)
        self.assertEqual(calls, [["chk.timer"], ["brain.service", "chk.service"]])
        self.assertTrue(F["next"]["chk.timer"])
        self.assertIn("notes", F["tmux"])
        self.assertEqual(F["cal"], {"chk.timer": "15min"})
        self.assertEqual(runners.facts(specs[:1], props), {"units": {}, "next": {}, "cal": {}, "tmux": {}})


if __name__ == "__main__":
    unittest.main()
