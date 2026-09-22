"""Every listener worth a link: ss + docker ps + an HTTP probe per port."""
import glob, os, re, time, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor
from dash.env import HOME, PUBLIC_HOST, run

# port -> (name, what it is, scheme, tailnet https port if tailscale serve fronts it, group)
# group: a SITES screen group for things a person opens in a browser, None for plumbing
SITES = {
    19998: ("Dashboard", "this page: the machine's control panel", "http", 8498, "mine"),
    8070: ("Drop folder", "files you asked for, pull them from the phone", "http", None, "mine"),
    8071: ("Portfolio preview", "static build of the portfolio site", "http", None, "mine"),
    8644: ("The Eye", "talk to the eye from the phone", "https", 8644, "mine"),
    8052: ("Moodle 5.2", "the dev site, 17 fixture charts", "http", 8452, "moodle"),
    8025: ("MailHog", "every mail the Moodle sites send, caught here", "http", None, "moodle"),
    19999: ("Netdata", "live machine metrics, per second", "http", 8499, "metrics"),
    8642: ("Eye bridge", "the body's local API", None, None, None),
    8643: ("Eye sandbox", "a hand-run body (body-sandbox)", None, None, None),
    4444: ("Selenium", "behat grid", "http", None, None),
    7900: ("Selenium noVNC", "watch a behat run", "http", None, None),
    1025: ("MailHog SMTP", "mail sink", None, None, None),
    5452: ("Moodle 5.2 DB", "postgres", None, None, None),
    5900: ("Selenium VNC", "raw VNC", None, None, None),
    80: ("Moodle proxy", "shared nginx front", None, None, None),
}
# infrastructure that is never a "site": ssh, dns, cups, statsd, ephemeral tailscale ports
SKIP_PORTS = {22, 53, 631, 8125, 8452, 8498, 8499}


def listeners():
    """port -> {pid, proc} for every IPv4/IPv6 TCP listener in this user's view."""
    out = {}
    lines = run(["sudo", "-n", "ss", "-ltnpH"], 10) or run(["ss", "-ltnpH"], 10)
    for line in lines.splitlines():
        f = line.split()
        if len(f) < 4:
            continue
        m = re.search(r":(\d+)$", f[3])
        if not m:
            continue
        port = int(m.group(1))
        pm = re.search(r'\("([^"]+)",pid=(\d+)', line)
        cur = out.setdefault(port, {"port": port, "pid": None, "proc": ""})
        if pm and not cur["pid"]:
            cur["pid"], cur["proc"] = int(pm.group(2)), pm.group(1)
    return out


def proc_started(pid):
    try:
        return time.time() - (os.path.getmtime("/proc/%d" % pid))
    except OSError:
        return None


def proc_unit(pid):
    try:
        cg = open("/proc/%d/cgroup" % pid).read()
    except OSError:
        return ""
    m = re.findall(r"/([\w@.\-]+\.service)", cg)
    return m[-1] if m and m[-1] != "user@%d.service" % os.getuid() else ""


def human_age(sec):
    """Mirror of the page's ago(): 50 min / 27 h / 8 d."""
    if sec is None:
        return ""
    if sec < 3600:
        return "%d min" % max(0, round(sec / 60))
    if sec < 172800:
        return "%d h" % round(sec / 3600)
    return "%d d" % round(sec / 86400)


DOCKER_UP = re.compile(r"^Up (?:(About an?|Less than an?|\d+) )?(second|minute|hour|day|week|month|year)s?", re.I)
DOCKER_UNIT = {"second": 1, "minute": 60, "hour": 3600, "day": 86400, "week": 604800, "month": 2592000, "year": 31536000}


def docker_age(status):
    """'Up 29 hours' -> '29 h'; anything else stays as docker wrote it, lowercased."""
    m = DOCKER_UP.match(status)
    if not m:
        return status.lower()
    n = m.group(1) or "1"
    n = 1 if not n.isdigit() else int(n)
    return human_age(n * DOCKER_UNIT[m.group(2).lower()])


def docker_ps():
    """Running containers with their published host ports."""
    out = []
    for line in run(["docker", "ps", "-a", "--format", "{{.Names}}\t{{.State}}\t{{.Status}}\t{{.Ports}}"], 15).splitlines():
        f = line.split("\t")
        if len(f) < 4:
            continue
        ports = sorted({int(p) for p in re.findall(r":(\d+)->", f[3])})
        out.append({"name": f[0], "state": f[1], "status": docker_age(f[2]), "ports": ports})
    return out


def http_code(url, method):
    """Status code of one request, None when nothing answers within 3 s."""
    try:
        with urllib.request.urlopen(urllib.request.Request(url, method=method), timeout=3) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return None


def probe(port):
    """HEAD, then GET when HEAD is refused, on the local port (v4 then v6): (state, ms); down when nothing answers."""
    t0 = time.time()
    for host in ("127.0.0.1", "[::1]"):
        for method in ("HEAD", "GET"):
            code = http_code("http://%s:%d/" % (host, port), method)
            if code is None:
                break
            if code < 400 or method == "GET":
                return ("up" if code < 400 else "warn"), int((time.time() - t0) * 1000)
    return "down", int((time.time() - t0) * 1000)


def declared_ports():
    """Ports something on this machine still declares: a compose file under ~/moodle-envs, or a host service of ours."""
    out = {p for p, (n, w, sc, ts, g) in SITES.items() if g == "mine" or g == "metrics"}
    for yml in glob.glob(os.path.join(HOME, "moodle-envs/*/docker-compose.yml")):
        out.update(int(m) for m in re.findall(r'"(\d+):\d+"', open(yml).read()))
    return out


def sites():
    """Every listener worth a link, live from ss and probed over HTTP; unknown ones are flagged stray."""
    rows = []
    live = listeners()
    owner = {p: c["name"] for c in docker_ps() for p in c["ports"]}
    for port, info in sorted(live.items()):
        if port in SKIP_PORTS or port > 30000:
            continue
        known = SITES.get(port)
        name, what, scheme, ts, group = known or ("port %d" % port, info["proc"] or "unknown listener", "http", None, None)
        url = ""
        if scheme == "https" or ts:
            url = "https://%s:%d/" % (PUBLIC_HOST, ts or port)
        elif scheme == "http":
            url = "http://%s:%d/" % (PUBLIC_HOST, port)
        unit = owner.get(port) or (proc_unit(info["pid"]) if info["pid"] else "")
        rows.append({
            "port": port, "name": name, "what": what, "url": url, "group": group,
            "state": "up" if known else "stray", "unit": unit, "pid": info["pid"],
            "uptime": human_age(proc_started(info["pid"])) if info["pid"] else "",
            "proc": info["proc"], "tls": bool(ts or scheme == "https"), "ms": None,
        })
    with ThreadPoolExecutor(8) as pool:
        probed = list(pool.map(lambda r: probe(r["port"]) if r["url"] else (None, None), rows))
    for r, (state, ms) in zip(rows, probed):
        r["ms"] = ms
        if state and r["state"] == "up":
            r["state"] = state
    declared = declared_ports()
    for port, (name, what, scheme, ts, group) in sorted(SITES.items()):
        if port not in live and port not in SKIP_PORTS and scheme and port in declared:
            rows.append({"port": port, "name": name, "what": what, "url": "", "group": group, "ms": None,
                         "state": "down", "unit": "", "pid": None, "uptime": "", "proc": "", "tls": False})
    order = list(SITES)
    rows.sort(key=lambda r: ({"stray": 0, "down": 1, "warn": 2, "up": 3}[r["state"]],
                             order.index(r["port"]) if r["port"] in order else 99))
    return rows
