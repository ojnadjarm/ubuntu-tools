"""Machine blocks for /api/status: pc status, envs, agents, units, timers, events, sparks, the verdict."""
import json, os, re, urllib.request
from datetime import datetime, timedelta, timezone
from dash.cache import cache_meta, swr
from dash.env import BIN, BRAND, HOME, HOST, PUBLIC_HOST, run
from dash.routes import route
from dash.services import files, sites

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


def unix_iso(v):
    return datetime.fromtimestamp(int(v[1:])).astimezone().isoformat(timespec="seconds") if v.startswith("@") else v


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
        nxt = unix_iso(p.get("NextElapseUSecRealtime", ""))
        sched = ""
        conf = os.path.join(HOME, ".config/systemd/user", unit + ".timer.d", "schedule.conf")
        if os.path.exists(conf):
            m = re.findall(r"^OnCalendar=(.+)$", open(conf).read(), re.M)
            sched = m[-1] if m else ""
        last = {}
        idx = os.path.join(d, "logs", "index.tsv")
        if os.path.exists(idx):
            rows = [r for r in open(idx).read().splitlines() if r and not r.startswith("start\t")]
            if rows:
                f = rows[-1].split("\t")
                last = {"end": f[1], "exit": f[2], "seconds": f[3], "cost": f[4] if len(f) > 4 else ""}
        out.append({"name": name, "enabled": enabled, "schedule": sched, "next": nxt, "last": last})
    return out


def since_24h():
    """Recent pushes and sentinel failures, newest first."""
    cut = datetime.now(timezone.utc) - timedelta(hours=24)
    ev = []

    def when(s):
        try:
            return datetime.fromisoformat(s.strip())
        except ValueError:
            return None

    log = os.path.join(HOME, "agents/log/notify.log")
    if os.path.exists(log):
        for line in open(log).read().splitlines()[-200:]:
            f = line.split("\t")
            t = when(f[0]) if f else None
            if t and t >= cut:
                ev.append({"t": f[0], "kind": "push", "prio": f[2] if len(f) > 2 else "",
                           "text": f[3] if len(f) > 3 else ""})
    sl = os.path.join(HOME, "agents/sentinel/state/sentinel.log")
    if os.path.exists(sl):
        for line in open(sl).read().splitlines()[-200:]:
            m = re.match(r"^(\S+) (FAIL|unresolved.*?): ?(.*)$", line)
            if not m:
                continue
            t = when(m.group(1))
            if t and t >= cut:
                ev.append({"t": m.group(1), "kind": "incident", "prio": "high",
                           "text": (m.group(2) + " " + m.group(3)).strip()})
    ev.sort(key=lambda e: e["t"], reverse=True)
    return ev[:20]


FLEET = re.compile(r"^(dark-eye|docker|sentinel|agent@|notes-brain|agents-dashboard|moodle-keep)")
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
                    "since": unix_iso(since),
                    "group": "fleet" if FLEET.match(u["unit"]) else "desktop" if DESKTOP.match(u["unit"]) else "his",
                    "rss": int(rss) if rss.isdigit() else None})
    order = {"fleet": 0, "his": 1, "desktop": 2}
    out.sort(key=lambda u: (order[u["group"]], u["active"] != "failed", u["unit"]))
    return out


def user_timers():
    def iso(us):
        return datetime.fromtimestamp(us / 1e6).astimezone().isoformat(timespec="seconds") if us else ""
    out = []
    for t in json.loads(run(["systemctl", "--user", "list-timers", "--all", "-o", "json"], 10) or "[]"):
        conf = os.path.join(HOME, ".config/systemd/user", t["unit"] + ".d", "schedule.conf")
        cal = ""
        for p in (os.path.join(HOME, ".config/systemd/user", t["unit"]), conf):
            if os.path.exists(p):
                m = re.findall(r"^On(?:Calendar|UnitActiveSec|BootSec)=(.+)$", open(p).read(), re.M)
                cal = m[-1] if m else cal
        out.append({"unit": t["unit"], "activates": t["activates"], "next": iso(t.get("next")),
                    "last": iso(t.get("last")), "every": human_cal(cal)})
    out.sort(key=lambda t: t["next"] or "9")
    return out


def human_cal(cal):
    """systemd OnCalendar / OnUnitActiveSec -> words: daily 04:30, Mon + Thu 03:00, every minute."""
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


ASK = re.compile(r'decide|say\s+"?go|needs? you', re.I)


def verdict(st, ag, ev):
    """OK unless a push asks the owner to decide, pc status reports failures or an agent's last run failed."""
    asks = [e for e in ev if e["kind"] == "push" and ASK.search(e["text"])]
    bad = ["ask: " + e["text"][:80] for e in asks]
    for sec, items in st.get("sections", {}).items():
        for k, v in items.items():
            if v.get("state") == "FAIL":
                bad.append("%s.%s" % (sec, k))
    for a in ag:
        if a["last"].get("exit") not in (None, "", "0"):
            bad.append("agent %s exit %s" % (a["name"], a["last"]["exit"]))
    return {"ok": not bad, "problems": bad, "asks": asks}


BLOCKS = {"status": (pc_status, {}), "envs": (envs, []), "agents": (agents, []), "events": (since_24h, []),
          "sites": (sites.sites, []), "drop": (files.drop, {}), "units": (user_units, []), "timers": (user_timers, []),
          "docker": (sites.docker_ps, []), "plans": (files.plans, []), "sentinel_last_ok": (sentinel_last_ok, ""),
          "sparks": (sparks, {})}


def payload():
    out = {"now": datetime.now().astimezone().isoformat(timespec="seconds")}
    out.update(swr(BLOCKS))
    out["stale"], out["errors"], out["stale_since"] = cache_meta(BLOCKS)
    out["verdict"] = verdict(out["status"], out["agents"], out["events"])
    out["host"] = HOST
    out["brand"] = BRAND
    out["netdata"] = f"http://{PUBLIC_HOST}:19999"
    out["voice_url"] = "https://%s:%d/voice" % (PUBLIC_HOST, sites.SITES[19998][3])
    return out


@route("GET", "/api/status")
def status_route(h, path):
    h.json(payload())
