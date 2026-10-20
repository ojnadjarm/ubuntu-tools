"""Per-agent runner: what really runs an agent (agent@ timer, a named service + tmux session, or a bash timer) read from agent.env."""
import json, os, re
from datetime import datetime
from dash.env import HOME, run

KINDS = ("timer-agent", "service", "bash-timer")
UNIT_DIR = os.path.join(HOME, ".config/systemd/user")
TIMER_PROPS = ["UnitFileState", "ActiveState", "LastTriggerUSec", "Triggers"]
SERVICE_PROPS = ["UnitFileState", "ActiveState", "SubState", "Result", "ExecMainStatus",
                 "ExecMainStartTimestamp", "ExecMainExitTimestamp", "ActiveEnterTimestamp"]


def env_keys(path):
    """KEY=value pairs of an agent.env, quotes and trailing comments stripped."""
    out = {}
    if not os.path.exists(path):
        return out
    for line in open(path, errors="replace"):
        m = re.match(r"^\s*([A-Z_][A-Z0-9_]*)=(\"[^\"]*\"|'[^']*'|[^\s#]*)", line)
        if m:
            out[m.group(1)] = m.group(2).strip("\"'")
    return out


def spec(name, env):
    """{kind, unit, tmux}; no RUNNER_KIND means the agent@<name>.timer default, on-demand without its timer drop-in."""
    kind = env.get("RUNNER_KIND", "timer-agent")
    if kind not in KINDS or kind == "timer-agent" or not env.get("RUNNER_UNIT"):
        if not os.path.isdir(os.path.join(UNIT_DIR, "agent@%s.timer.d" % name)):
            return {"kind": "on-demand", "unit": "agent@%s.service" % name, "tmux": ""}
        return {"kind": "timer-agent", "unit": "agent@%s.timer" % name, "tmux": ""}
    return {"kind": kind, "unit": env["RUNNER_UNIT"], "tmux": env.get("RUNNER_TMUX", "")}


def iso(v):
    """systemd '@<unix>' or list-timers microseconds -> local ISO, '' when unset."""
    if isinstance(v, (int, float)):
        return datetime.fromtimestamp(v / 1e6).astimezone().isoformat(timespec="seconds") if v else ""
    return datetime.fromtimestamp(int(v[1:])).astimezone().isoformat(timespec="seconds") if v and v.startswith("@") and v[1:].isdigit() else ""


def calendar(unit):
    """Raw OnCalendar / OnUnitActiveSec of a user timer, drop-in schedule.conf last."""
    cal = ""
    for p in (os.path.join(UNIT_DIR, unit), os.path.join(UNIT_DIR, unit + ".d", "schedule.conf")):
        if os.path.exists(p):
            m = re.findall(r"^On(?:Calendar|UnitActiveSec|BootSec)=(.+)$", open(p).read(), re.M)
            cal = m[-1] if m else cal
    return cal


def facts(specs, unit_props):
    """Everything the non-default runners need, in a few batched reads: unit props, timer next/calendar, tmux created."""
    specs = [s for s in specs if s["kind"] != "timer-agent"]
    if not specs:
        return {"units": {}, "next": {}, "cal": {}, "tmux": {}}
    timers = [s["unit"] for s in specs if s["kind"] == "bash-timer"]
    units = unit_props(TIMER_PROPS, timers) if timers else {}
    services = [s["unit"] for s in specs if s["kind"] == "service"]
    services += [units.get(t, {}).get("Triggers", "").split(" ")[0] or t.replace(".timer", ".service") for t in timers]
    units.update(unit_props(SERVICE_PROPS, services))
    nxt = {}
    if timers:
        for t in json.loads(run(["systemctl", "--user", "list-timers", "--all", "-o", "json"] + timers, 10) or "[]"):
            nxt[t["unit"]] = iso(t.get("next") or 0)
    tmux = {}
    if any(s["tmux"] for s in specs):
        for line in run(["tmux", "ls", "-F", "#{session_name} #{session_created}"], 3).splitlines():
            n, _, c = line.partition(" ")
            tmux[n] = iso("@" + c) if c.isdigit() else ""
    return {"units": units, "next": nxt, "cal": {t: calendar(t) for t in timers}, "tmux": tmux}


def secs(a, b):
    """Whole seconds between two '@<unix>' stamps, '' when either is unset."""
    try:
        return str(max(0, int(b[1:]) - int(a[1:])))
    except (TypeError, ValueError):
        return ""


def bash_timer(s, F, row, human):
    """A bash timer schedules the work; the agent is the fallback it escalates to."""
    t = F["units"].get(s["unit"], {})
    svc_name = t.get("Triggers", "").split(" ")[0] or s["unit"].replace(".timer", ".service")
    svc = F["units"].get(svc_name, {})
    down = t.get("ActiveState") != "active"
    failed = svc.get("ActiveState") == "failed" or svc.get("Result", "success") not in ("success", "") or svc.get("ExecMainStatus", "0") not in ("0", "")
    end = iso(svc.get("ExecMainExitTimestamp", "")) or iso(t.get("LastTriggerUSec", ""))
    last = {"end": end, "exit": svc.get("ExecMainStatus", ""), "seconds": secs(svc.get("ExecMainStartTimestamp"), svc.get("ExecMainExitTimestamp"))} if end else {}
    return {"enabled": t.get("UnitFileState") or "no", "on": not down, "schedule": human(F["cal"].get(s["unit"], "")),
            "next": F["next"].get(s["unit"], ""), "last": last, "fallback": row.get("last", {}),
            "health": "bad" if down or failed else "ok",
            "runner": {"kind": s["kind"], "unit": s["unit"], "service": svc_name, "state": t.get("ActiveState", ""),
                       "result": svc.get("Result", "")}}


def service(s, F, row, human):
    """An always-on service, alive only while its unit is active and its tmux session (when named) exists."""
    u = F["units"].get(s["unit"], {})
    active, failed = u.get("ActiveState") == "active", u.get("ActiveState") == "failed"
    tm = s["tmux"] in F["tmux"] if s["tmux"] else None
    alive = active and tm is not False
    health = "bad" if failed else "ok" if alive else "warn" if active or tm else "off"
    since = (F["tmux"].get(s["tmux"]) if s["tmux"] else "") or iso(u.get("ActiveEnterTimestamp", ""))
    return {"enabled": u.get("UnitFileState") or "no", "on": alive, "schedule": "always on", "next": "",
            "health": health,
            "runner": {"kind": s["kind"], "unit": s["unit"], "state": u.get("ActiveState", ""), "sub": u.get("SubState", ""),
                       "tmux": s["tmux"], "tmux_alive": tm, "since": since if alive else ""}}


VIEWS = {"bash-timer": bash_timer, "service": service}


def view(s, F, row, human=lambda c: c):
    """Card fields for one agent row: the default keeps the row and adds kind/on/health; other kinds override from the runner."""
    if s["kind"] in VIEWS:
        return dict(row, kind=s["kind"], **VIEWS[s["kind"]](s, F, row, human))
    ex = (row.get("last") or {}).get("exit")
    on = row.get("enabled") == "enabled"
    return dict(row, kind=s["kind"], on=on, health="bad" if ex not in (None, "", "0") else "ok" if on else "off",
                runner={"kind": s["kind"], "unit": s["unit"]})
