"""Machine blocks for /api/status: pc status, envs, agents, units, timers, events, sparks, the verdict."""
import hashlib, json, os, re, urllib.request
from datetime import datetime, timedelta, timezone
from dash.cache import cache_meta, swr
from dash.env import BIN, BRAND, HOME, HOST, PUBLIC_HOST, run
from dash.routes import route
from dash.services import files, projects, runners, sites, todo

NETDATA = "http://127.0.0.1:19999"


def pc_status():
    return json.loads(run([os.path.join(BIN, "pc-status"), "--json"]))


def envs():
    return json.loads(run([os.path.join(BIN, "moodle-envs"), "--json"]) or "[]")


def unit_props(props, units):
    """{Id: {prop: value}} from one batched `systemctl --user show` with unix timestamps."""
    if not units:
        return {}
    out = {}
    for block in run(["systemctl", "--user", "show", "-p", "Id," + ",".join(props), "--timestamp=unix"] + units, 10).split("\n\n"):
        kv = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        if kv.get("Id"):
            out[kv["Id"]] = kv
    return out


def agents():
    out = []
    root = os.path.join(HOME, "agents")
    names = [n for n in sorted(os.listdir(root)) if os.path.isfile(os.path.join(root, n, "BRIEF.md"))]
    props = unit_props(["UnitFileState", "NextElapseUSecRealtime"], ["agent@%s.timer" % n for n in names])
    for name in names:
        d = os.path.join(root, name)
        unit = "agent@%s" % name
        p = props.get(unit + ".timer", {})
        enabled = p.get("UnitFileState") or "no"
        nxt = runners.iso(p.get("NextElapseUSecRealtime", ""))
        sched = human_cal(runners.calendar(unit + ".timer"))
        last = {}
        idx = os.path.join(d, "logs", "index.tsv")
        if os.path.exists(idx):
            rows = [r for r in open(idx).read().splitlines() if r and not r.startswith("start\t")]
            if rows:
                f = rows[-1].split("\t")
                last = {"end": f[1], "exit": f[2], "seconds": f[3], "cost": f[4] if len(f) > 4 else ""}
        out.append({"name": name, "enabled": enabled, "schedule": sched, "next": nxt, "last": last})
    specs = [runners.spec(r["name"], runners.env_keys(os.path.join(root, r["name"], "agent.env"))) for r in out]
    F = runners.facts(specs, unit_props)
    return [runners.view(s, F, r, human_cal) for s, r in zip(specs, out)]


def since_24h():
    """Recent pushes, sentinel failures, runaway actions and stuck-wait kills (one row per loop), newest first."""
    cut = datetime.now(timezone.utc) - timedelta(hours=24)
    ev = []

    def when(s):
        try:
            t = datetime.fromisoformat(s.strip())
        except ValueError:
            return None
        return t if t.tzinfo else None

    log = os.path.join(HOME, "agents/log/notify.log")
    if os.path.exists(log):
        last = None
        for line in open(log).read().splitlines()[-200:]:
            f = line.split("\t")
            t = when(f[0]) if f else None
            if t is None:
                if last:
                    last["text"] += "\n" + line
                continue
            last = None
            if t >= cut:
                last = {"t": f[0], "kind": "push", "prio": f[2] if len(f) > 2 else "",
                        "text": f[3] if len(f) > 3 else ""}
                ev.append(last)
    sl = os.path.join(HOME, "agents/sentinel/state/sentinel.log")
    if os.path.exists(sl):
        loops = {}
        for line in open(sl).read().splitlines()[-200:]:
            r = re.match(r"^(\S+) (runaway|stuck-wait) ((?:killed|took down|removed|restarted) .*)$", line)
            if r:
                t = when(r.group(1))
                if t and t >= cut:
                    text = r.group(3) if r.group(2) == "runaway" else r.group(2) + " " + r.group(3)
                    key = re.sub(r"\d+", "N", text.split(")", 1)[0])
                    e = loops.setdefault(key, {"kind": "runaway", "prio": "default", "n": 0})
                    e.update(t=r.group(1), text=text, n=e["n"] + 1)
                continue
            m = re.match(r"^(\S+) (FAIL|unresolved.*?): ?(.*)$", line)
            if not m:
                continue
            t = when(m.group(1))
            if t and t >= cut:
                ev.append({"t": m.group(1), "kind": "incident", "prio": "high",
                           "text": (m.group(2) + " " + m.group(3)).strip()})
        for e in loops.values():
            n = e.pop("n")
            ev.append(dict(e, text=e["text"] + (" x%d" % n if n > 1 else "")))
    ev.sort(key=lambda e: e["t"], reverse=True)
    return ev


FLEET = re.compile(r"^(dark-eye|docker|sentinel|agent@|agents-dashboard|moodle-keep|%s$)"
                   % re.escape(os.environ.get("ORCHESTRATOR_UNIT") or "claude-orchestrator.service"))
DESKTOP = re.compile(r"^(gvfs-|org\.gnome\.|org\.freedesktop\.|evolution-|xdg-|pipewire|wireplumber|dbus|at-spi|gnome-|gcr-|dconf|localsearch|filter-chain|snap\.)")


def user_units():
    """Running or failed user services, grouped fleet / yours / desktop, with resident memory."""
    out = []
    units = [u for u in json.loads(run(["systemctl", "--user", "list-units", "--type=service", "--all", "-o", "json"], 10) or "[]")
             if u["sub"] == "running" or u["active"] == "failed"]
    props = unit_props(["ActiveEnterTimestamp", "MemoryCurrent"], [u["unit"] for u in units])
    for u in units:
        p = props.get(u["unit"], {})
        since = p.get("ActiveEnterTimestamp", "") if u["active"] == "active" else ""
        rss = p.get("MemoryCurrent", "")
        out.append({"unit": u["unit"], "what": u["description"][:1].lower() + u["description"][1:], "active": u["active"], "sub": u["sub"],
                    "since": runners.iso(since),
                    "group": "fleet" if FLEET.match(u["unit"]) else "desktop" if DESKTOP.match(u["unit"]) else "his",
                    "rss": int(rss) if rss.isdigit() else None})
    order = {"fleet": 0, "his": 1, "desktop": 2}
    out.sort(key=lambda u: (order[u["group"]], u["active"] != "failed", u["unit"]))
    return out


def user_timers():
    out = []
    for t in json.loads(run(["systemctl", "--user", "list-timers", "--all", "-o", "json"], 10) or "[]"):
        out.append({"unit": t["unit"], "activates": t["activates"], "next": runners.iso(t.get("next") or 0),
                    "last": runners.iso(t.get("last") or 0), "every": human_cal(runners.calendar(t["unit"]))})
    out.sort(key=lambda t: t["next"] or "9")
    return out


def human_cal(cal):
    """systemd OnCalendar / OnUnitActiveSec -> words: daily 04:30, hourly at :07, once 2027-01-01 03:00, parked."""
    if not cal:
        return ""
    m = re.match(r"^(\d+)(min|h|s|d)$", cal)
    if m:
        n, u = int(m.group(1)), {"min": "min", "h": "h", "s": "s", "d": "d"}[m.group(2)]
        if n == 1:
            return "every " + {"min": "minute", "h": "hour", "s": "second", "d": "day"}[u]
        return "every %d %s" % (n, u)
    m = re.match(r"^(?:([A-Za-z,]+) )?\*-\*-\* (\d\d:\d\d)(?::\d\d)?$", cal)
    if m:
        days = m.group(1)
        if not days:
            return "daily " + m.group(2)
        return " + ".join(d[:3] for d in days.split(",")) + " " + m.group(2)
    m = re.match(r"^\*-\*-\* \*:(\d\d)(?::\d\d)?$", cal)
    if m:
        return "hourly at :" + m.group(1)
    m = re.match(r"^(\d{4}-\d\d-\d\d) (\d\d:\d\d)(?::\d\d)?$", cal)
    if m:
        when = datetime.strptime(m.group(1) + " " + m.group(2), "%Y-%m-%d %H:%M")
        return "parked" if when - datetime.now() > timedelta(days=365) else "once %s %s" % m.groups()
    return cal


def sentinel_last_ok():
    p = os.path.join(HOME, "agents/sentinel/state/last-ok")
    return open(p).read().strip() if os.path.exists(p) else ""


CHARTS = {
    "cpu": ("system.cpu", "sum", "%"),
    "ram": ("system.ram", "rampct", "%"),
    "io": ("system.io", "absum", "KB/s"),
    "net": ("system.net", "absum", "kbit/s"),
}


def spark(chart, mode):
    url = ("%s/api/v1/data?chart=%s&after=-1800&points=48&group=average&format=json"
           % (NETDATA, chart))
    with urllib.request.urlopen(url, timeout=5) as r:
        d = json.load(r)
    labels, rows = d["labels"][1:], list(reversed(d["data"]))
    vals = []
    for row in rows:
        v = row[1:]
        if mode == "rampct":
            used = sum(v[i] or 0 for i, l in enumerate(labels) if l in ("used", "buffers"))
            total = sum(x or 0 for x in v)
            vals.append(100.0 * used / total if total else 0.0)
        elif mode == "absum":
            vals.append(sum(abs(x or 0) for x in v))
        else:
            vals.append(sum(x or 0 for x in v))
    return {"values": [round(x, 2) for x in vals]}


def sparks():
    out = {}
    for key, (chart, mode, unit) in CHARTS.items():
        try:
            s = spark(chart, mode)
        except Exception as e:
            s = {"values": [], "error": str(e)}
        s["unit"] = unit
        out[key] = s
    return out


ASK = re.compile(r'\b(?:decide|pick|choose)\b|say\s+"?go|needs? you', re.I)
NEG = re.compile(r"\b(nothing|no|not|none|never|nobody)\b", re.I)
CLAUSE = re.compile(r"(?<=[.;:!?,])\s+|\s+(?:[—–-]|but)\s+|\s+(?=\d+[.)]\s)")


def asks_owner(text):
    """True when a push asks the owner something: an ask phrase in a clause with no negation before it ("Nothing needs you" is not an ask)."""
    for part in CLAUSE.split(text):
        m = ASK.search(part)
        if m and not NEG.search(part[:m.start()]):
            return True
    return False


RESOLVED = "agents/log/notify-resolved.jsonl"


def push_key(e):
    """Stable id of one push: the first 10 hex of sha1 over its timestamp and text."""
    return hashlib.sha1((e["t"] + "\t" + e["text"]).encode()).hexdigest()[:10]


def resolved():
    """Push keys whose latest line in the resolved ledger (written by `pc need`) says resolved."""
    state = {}
    try:
        lines = open(os.path.join(HOME, RESOLVED)).read().splitlines()
    except OSError:
        return set()
    for line in lines:
        try:
            r = json.loads(line)
            state[r["key"]] = r["state"]
        except (ValueError, KeyError, TypeError):
            continue
    return {k for k, s in state.items() if s == "resolved"}


def verdict(st, ag, ev, todos=()):
    """What needs the owner: unresolved pushes that ask him or are high-priority, open owner to-dos, pc status failures, agents whose last run failed; `needs` is the one list the headline counts."""
    done = resolved()
    pushes = [e for e in ev if e["kind"] == "push" and push_key(e) not in done]
    asks = [e for e in pushes if asks_owner(e["text"])]
    needs = [{"kind": "ask", "t": e["t"], "text": e["text"], "id": push_key(e)} for e in asks]
    needs += [{"kind": "push", "t": e["t"], "text": e["text"], "id": push_key(e)} for e in pushes
              if e.get("prio") == "high" and e not in asks]
    needs += [{"kind": "todo", "todo": i["id"], "text": i["text"]} for i in todos]
    for sec, items in st.get("sections", {}).items():
        for k, v in items.items():
            if v.get("state") == "FAIL":
                needs.append({"kind": "fail", "text": "%s.%s" % (sec, k)})
    for a in ag:
        if a["last"].get("exit") not in (None, "", "0"):
            if any(n["kind"] == "push" and n["text"] == "agent %s failed (exit %s)" % (a["name"], a["last"]["exit"])
                   and a["last"].get("end") and datetime.fromisoformat(n["t"]) >= datetime.fromisoformat(a["last"]["end"])
                   for n in needs):
                continue
            needs.append({"kind": "agent", "text": "agent %s exit %s" % (a["name"], a["last"]["exit"])})
    bad = [(n["kind"] + ": " + n["text"][:80]) if n["kind"] in ("ask", "todo") else n["text"] for n in needs]
    return {"ok": not needs, "problems": bad, "asks": asks, "needs": needs}


def owner_counts():
    """The four counts of `agents-status --owner`, done counted from today."""
    import owner_status
    d = owner_status.collect(HOME, since_date=datetime.now().strftime("%Y-%m-%d"))
    return {"running": len(d["running"]), "done": len(d["done"]), "waiting": len(d["waiting"]), "queued": len(d["queued"])}


BLOCKS = {"status": (pc_status, {}), "owner": (owner_counts, {}), "envs": (envs, []), "agents": (agents, []), "events": (since_24h, []),
          "sites": (sites.sites, []), "drop": (files.drop, {}), "units": (user_units, []), "timers": (user_timers, []),
          "docker": (sites.docker_ps, []), "plans": (files.plans, []), "sentinel_last_ok": (sentinel_last_ok, ""),
          "sparks": (sparks, {}), "projects": (projects.projects, [])}


def payload():
    out = {"now": datetime.now().astimezone().isoformat(timespec="seconds")}
    out.update(swr(BLOCKS))
    out["stale"], out["errors"], out["stale_since"] = cache_meta(BLOCKS)
    out["todo"], out["todo_error"] = todo.checked()
    out["verdict"] = verdict(out["status"], out["agents"], out["events"], out["todo"])
    out["events"] = out["events"][:20]
    out["host"] = HOST
    out["brand"] = BRAND
    out["netdata"] = f"http://{PUBLIC_HOST}:19999"
    out["voice_url"] = "https://%s:%d/voice" % (PUBLIC_HOST, sites.SITES[19998][3])
    out["test_site"] = sites.test_site()
    return out


@route("GET", "/api/status")
def status_route(h, path):
    h.json(payload())
