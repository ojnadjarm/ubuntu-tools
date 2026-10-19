"""Owner status: running agents, done since the last ask, waiting on the owner, queued briefs (stdlib only)."""
import glob, json, os, re, subprocess, time
from datetime import datetime

import owner_todo
from agent_work import agent_work

TICKET = re.compile(r"\bT\d+[a-z]?\b")
DATED = re.compile(r"- \d{4}-\d{2}-\d{2} ")
QUEUE_AGE_S = 48 * 3600


def _home(home):
    return home or os.path.expanduser("~")


def stamp_path(home=None):
    """Last-ask stamp: $OWNER_STATUS_STAMP, else <home>/agents/state/owner-status.json."""
    return os.environ.get("OWNER_STATUS_STAMP") or os.path.join(_home(home), "agents/state/owner-status.json")


def _label(tx):
    try:
        with open(tx[:-len(".jsonl")] + ".meta.json") as f:
            return json.load(f).get("description") or "agent"
    except (OSError, ValueError):
        return "agent"


def running(now):
    """Live subagents from the orbit-hook claims plus active headless agent@ units."""
    out = []
    claims = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "dark-eye", "orbit-claims.json")
    try:
        with open(claims) as f:
            for c in json.load(f).values():
                out.append({"label": _label(c.get("tx", "")), "min": int((now - c.get("at", now)) // 60)})
    except (OSError, ValueError, AttributeError):
        pass
    try:
        units = subprocess.run(["systemctl", "--user", "list-units", "agent@*.service", "--state=active", "--no-legend",
                                "--plain", "-o", "json"], capture_output=True, text=True, timeout=5).stdout
        for u in json.loads(units or "[]"):
            name = u["unit"][len("agent@"):-len(".service")]
            ts = subprocess.run(["systemctl", "--user", "show", "-p", "ActiveEnterTimestampMonotonic", "--value", u["unit"]],
                                capture_output=True, text=True, timeout=5).stdout.strip()
            mins = int((time.monotonic() - int(ts) / 1e6) // 60) if ts.isdigit() and int(ts) else 0
            out.append({"label": name + " (headless)", "min": mins})
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    return sorted(out, key=lambda r: -r["min"])


def _history(home):
    try:
        with open(os.path.join(agent_work(), "history.md")) as f:
            return [l.rstrip("\n") for l in f if DATED.match(l)]
    except OSError:
        return []


def _stamp(home):
    try:
        with open(stamp_path(home)) as f:
            s = json.load(f)
        return s.get("at", ""), int(s.get("lines", 0))
    except (OSError, ValueError):
        return "", None


def done(lines, since_date, stamp):
    """History lines after the last-ask stamp, or dated since_date onwards; returns (since text, lines)."""
    at, count = stamp
    if since_date is None and count is not None and count <= len(lines):
        return at[11:16] or at, lines[count:]
    day = since_date or datetime.now().strftime("%Y-%m-%d")
    return day, [l for l in lines if l[2:12] >= day]


def queued(history, live, now):
    """Briefs edited in the last 48 h whose ticket has no history line and is not running."""
    seen = set(TICKET.findall(" ".join(history))) | set(TICKET.findall(" ".join(r["label"] for r in live)))
    out = []
    for p in sorted(glob.glob(os.path.join(agent_work(), "briefs", "T*.md"))):
        t = TICKET.match(os.path.basename(p).split("-")[0])
        if t and t.group(0) not in seen and now - os.path.getmtime(p) < QUEUE_AGE_S:
            out.append(t.group(0))
    return sorted(set(out), key=lambda t: int(re.sub(r"\D", "", t)))


def collect(home=None, since_date=None, now=None):
    """The four sections as one dict."""
    now = now or time.time()
    history = _history(home)
    live = running(now)
    since, new = done(history, since_date, _stamp(home))
    todo = owner_todo.items(_home(home))
    return {"running": live, "since": since, "done": new, "history_lines": len(history),
            "waiting": [{"id": i["id"], "text": i["text"]} for i in todo], "queued": queued(history, live, now)}


def mark(data, home=None):
    """Record this ask so the next one shows only newer history lines."""
    p = stamp_path(home)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"at": datetime.now().isoformat(timespec="seconds"), "lines": data["history_lines"]}, f)
    os.replace(tmp, p)


def _short(s, n=72):
    return s if len(s) <= n else s[:n - 1] + "…"


def _entry(line):
    return _short(line[13:])


def render(d):
    """At most 15 lines: four headed sections, newest and longest-running first."""
    out = ["Running now: %d" % len(d["running"])]
    for r in d["running"][:3]:
        out.append("  %s · %d min" % (_short(r["label"], 40), r["min"]))
    if len(d["running"]) > 3:
        out[-1] += "  (+%d more)" % (len(d["running"]) - 3)
    out.append("Done since %s: %d" % (d["since"], len(d["done"])))
    out += ["  " + _entry(l) for l in d["done"][-3:][::-1]]
    out.append("Waiting on you: %d" % len(d["waiting"]))
    out += ["  %s. %s" % (w["id"], _short(w["text"], 68)) for w in d["waiting"][:3]]
    out.append("Queued: %d%s" % (len(d["queued"]), "  " + ", ".join(d["queued"][:10]) if d["queued"] else ""))
    return "\n".join(out)


def main(argv):
    import argparse
    p = argparse.ArgumentParser(prog="agents-status --owner", description="Running, done since the last ask, waiting on you, queued.")
    p.add_argument("--since", metavar="YYYY-MM-DD", help="done since this date (does not move the last-ask stamp)")
    p.add_argument("--json", action="store_true", help="the four sections as JSON (does not move the stamp)")
    a = p.parse_args(argv)
    d = collect(since_date=a.since)
    if a.json:
        print(json.dumps(d, indent=1))
        return 0
    print(render(d))
    if not a.since:
        mark(d)
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main(sys.argv[1:]))
