#!/usr/bin/env python3
"""Phone-first status page for this machine: serves index.html plus a cached JSON view of it."""
import json, os, re, socket, subprocess, threading, time, urllib.request
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import ThreadingMixIn

HOME = os.path.expanduser("~")
BIN = os.path.join(HOME, "agents", "bin")
HERE = os.path.dirname(os.path.abspath(__file__))
NETDATA = "http://127.0.0.1:19999"
HOST = os.environ.get("HARNESS_HOST") or socket.gethostname()
PUBLIC_HOST = os.environ.get("HARNESS_TAILNET_FQDN") or HOST
PORT = 19998
BINDS = ["0.0.0.0", "::"]
TTL = 30

_cache = {}
_lock = threading.Lock()


def cached(key, ttl, fn):
    """Return fn() memoised for ttl seconds, keeping the last good value on error."""
    with _lock:
        hit = _cache.get(key)
        if hit and time.time() - hit[0] < ttl:
            return hit[1]
    try:
        val = fn()
    except Exception as e:
        if hit:
            return hit[1]
        val = {"error": str(e)}
    with _lock:
        _cache[key] = (time.time(), val)
    return val


def run(cmd, timeout=25):
    env = dict(os.environ, PATH=BIN + ":" + os.environ.get("PATH", "/usr/bin:/bin"))
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env).stdout


def pc_status():
    return json.loads(run([os.path.join(BIN, "pc-status"), "--json"]))


def envs():
    return json.loads(run([os.path.join(BIN, "moodle-envs"), "--json"]) or "[]")


def sysctl_user(prop, unit):
    return run(["systemctl", "--user", "show", "-p", prop, "--value", unit], 10).strip()


def agents():
    out = []
    root = os.path.join(HOME, "agents")
    for name in sorted(os.listdir(root)):
        d = os.path.join(root, name)
        if not os.path.isfile(os.path.join(d, "BRIEF.md")):
            continue
        unit = "agent@%s" % name
        enabled = run(["systemctl", "--user", "is-enabled", unit + ".timer"], 10).strip() or "no"
        nxt = sysctl_user("NextElapseUSecRealtime", unit + ".timer")
        if nxt and nxt not in ("0", "n/a"):
            nxt = run(["date", "-d", nxt, "-Is"], 10).strip() or nxt
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


def sentinel_last_ok():
    p = os.path.join(HOME, "agents/sentinel/state/last-ok")
    return open(p).read().strip() if os.path.exists(p) else ""


CHARTS = {
    "cpu": ("system.cpu", "sum", "%"),
    "ram": ("system.ram", "rampct", "%"),
    "io": ("system.io", "absum", "KiB/s"),
    "net": ("system.net", "absum", "kbps"),
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


def verdict(st, ag):
    """OK unless pc status reports failures or an agent's last run failed."""
    bad = []
    for sec, items in st.get("sections", {}).items():
        for k, v in items.items():
            if v.get("state") == "FAIL":
                bad.append("%s.%s" % (sec, k))
    for a in ag:
        if a["last"].get("exit") not in (None, "", "0"):
            bad.append("agent %s exit %s" % (a["name"], a["last"]["exit"]))
    return {"ok": not bad, "problems": bad}


def payload():
    st = cached("status", TTL, pc_status)
    ag = cached("agents", TTL, agents)
    return {
        "now": datetime.now().astimezone().isoformat(timespec="seconds"),
        "status": st,
        "envs": cached("envs", TTL, envs),
        "agents": ag,
        "events": cached("events", TTL, since_24h),
        "sentinel_last_ok": cached("sok", TTL, sentinel_last_ok),
        "sparks": cached("sparks", TTL, sparks),
        "verdict": verdict(st, ag),
        "host": HOST,
        "netdata": f"http://{PUBLIC_HOST}:19999",
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            body = open(os.path.join(HERE, "index.html"), "rb").read()
            return self.send(200, body, "text/html; charset=utf-8")
        if path == "/api/status":
            body = json.dumps(payload()).encode()
            return self.send(200, body, "application/json")
        self.send(404, b"not found\n", "text/plain")


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class Server6(Server):
    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        Server.server_bind(self)


def main():
    servers = []
    for addr in BINDS:
        try:
            cls = Server6 if ":" in addr else Server
            servers.append(cls((addr, PORT), Handler))
        except OSError as e:
            print("bind %s:%s failed: %s" % (addr, PORT, e), flush=True)
    if not servers:
        raise SystemExit(1)
    for s in servers[1:]:
        threading.Thread(target=s.serve_forever, daemon=True).start()
    print("dashboard on %s:%d" % (",".join(BINDS), PORT), flush=True)
    servers[0].serve_forever()


if __name__ == "__main__":
    main()
