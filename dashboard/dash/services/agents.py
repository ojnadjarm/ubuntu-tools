"""/api/agents: the orchestrator's live and recent sub-agents, the persistent agents, the orbiter feed and the claims board, read-only."""
import glob, json, os, re, sys, threading, time
from dash.cache import cached, swr
from dash.env import HOME, run
from dash.routes import route
from dash.services import system

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "lib"))
import agent_ends  # noqa: E402
from agent_ends import iso_s  # noqa: E402

PROJ = os.path.join(HOME, ".claude/projects", HOME.replace("/", "-"))
ACTIONS = os.path.join(HOME, "agents/log/actions.jsonl")
CLAIMS = os.path.join(HOME, "agents/FILE-CLAIMS.md")
AGENTS_DIR = os.path.join(HOME, "agents")
ORCH_TMUX = os.environ.get("ORCHESTRATOR_TMUX_SESSION", "claude")
WORKING_S = 900
SLACK_S = 60
RUNNING_S = 60
RECENT_S = 86400
RECENT_N = 10
FEED = re.compile(r"eye status (\S+) (working|done|error)\b")
TICKET = re.compile(r"^[A-Za-z]{1,3}\d+[a-z]?$")
REPORT_SKIP = re.compile(r"^(#|==|(start|end|exit|seconds|cost_usd):)")
_subs = {}
_parent = {}
_feed = {}
_feed_lock = threading.Lock()
_parent_lock = threading.Lock()


def tail(path, size):
    """The last size bytes of a file as lines, the first (partial) line dropped when cut."""
    with open(path, "rb") as f:
        f.seek(0, 2)
        n = f.tell()
        f.seek(max(0, n - size))
        lines = f.read().decode("utf8", "replace").splitlines()
    return lines[1:] if n > size else lines


def feed():
    """{id lowercased: [(unix ts, state)]} from `eye status <id> <state>` calls in the whole action log, read incrementally."""
    with _feed_lock:
        m = _feed.setdefault(ACTIONS, [0, {}])
        try:
            size = os.path.getsize(ACTIONS)
        except OSError:
            return {}
        if size < m[0]:
            m[:] = [0, {}]
        with open(ACTIONS, "rb") as f:
            f.seek(m[0])
            buf = f.read(size - m[0])
        cut = buf.rfind(b"\n") + 1
        m[0] += cut
        for line in buf[:cut].split(b"\n"):
            if b"eye status" not in line:
                continue
            try:
                j = json.loads(line)
            except ValueError:
                continue
            t = iso_s(j.get("ts", ""))
            for g in FEED.finditer(j.get("summary", "")):
                m[1].setdefault(g.group(1).lower(), []).append((t, g.group(2)))
        return m[1]


def orbiters():
    """The live orbiter set the Eye holds, [] when the bridge does not answer."""
    try:
        return json.loads(run(["eye", "status"], 3) or "{}").get("orbiters", [])
    except Exception:
        return []


def transcript(js):
    """(started, doing, first report line, handback ts or 0) of one agent transcript, memoised by mtime and size."""
    st = os.stat(js)
    key = (st.st_mtime_ns, st.st_size)
    hit = _subs.get(js)
    if hit and hit[0] == key:
        return hit[1]
    with open(js, "rb") as f:
        try:
            started = json.loads(f.readline()).get("timestamp", "")
        except ValueError:
            started = ""
    doing, report, handed = "", "", 0
    for line in tail(js, 65536):
        try:
            j = json.loads(line)
            c = (j.get("message") or {}).get("content")
        except (ValueError, AttributeError):
            continue
        for b in c if isinstance(c, list) else []:
            if not isinstance(b, dict) or b.get("type") != "tool_use":
                continue
            inp = b.get("input") or {}
            if b.get("name") == "SubagentHandback":
                report, handed = inp.get("message", ""), iso_s(j.get("timestamp", "")) or st.st_mtime
            else:
                doing = inp.get("description") or b.get("name") or ""
    val = (started, doing[:160], re.sub(r"^\d+\. ", "", next((l.strip() for l in report.splitlines() if l.strip()), ""))[:240], handed)
    _subs[js] = (key, val)
    return val


def parent(js):
    """({task id: (ts, state)} from task notifications and TaskStop calls, {run id: (task id, workflow name)}) of the orchestrator transcript, read incrementally."""
    with _parent_lock:
        m = agent_ends.scan(js, _parent.setdefault(js, agent_ends.memo()))
    return m[1], m[2]


def keys(aid, label):
    """Feed ids that may name this agent, most specific first: a sub-ticket (L5), the ticket (T48), the agent id prefix."""
    toks = label.split()
    out = []
    if len(toks) > 1 and TICKET.match(toks[1]):
        out.append(toks[1].lower())
    if toks and TICKET.match(toks[0]):
        out.append(toks[0].lower())
    out.append(aid[:6].lower())
    return out


def state_of(aid, label, started, last, ends, fd, live):
    """The newest end event (feed done/error, handback, task notification; a done/error ≤ SLACK_S before a stop beats it) wins unless the agent has been writing again since;
    else activity < 15 min is working, a live orbiter alone is held (settled by hold()), and anything older is stale."""
    since = iso_s(started) - 120
    for k in keys(aid, label):
        hits = [e for e in fd.get(k, []) if e[0] >= since]
        if hits:
            ev = max(hits)
            if ev[1] in ("done", "error"):
                ends = ends + [ev]
            break
    idle = time.time() - last
    end = max(ends) if ends else None
    if end and end[1] == "stale":
        end = max((e for e in ends if e[1] != "stale" and end[0] - e[0] <= SLACK_S), default=end)
    if end and not (last - end[0] > SLACK_S and idle < WORKING_S):
        return end[1]
    if idle < WORKING_S:
        return "working"
    return "held" if any(k in live for k in keys(aid, label)) else "stale"


def hold(recs):
    """An orbiter-held agent stays working only while no newer agent sharing a feed key is active; else it is stale."""
    active = [(iso_s(r["started"]), set(keys(r["id"], r["label"]))) for r in recs if r["state"] in ("working", "held")]
    for r in recs:
        if r["state"] == "held":
            t, ks = iso_s(r["started"]), set(keys(r["id"], r["label"]))
            r["state"] = "stale" if any(t2 > t and ks & k2 for t2, k2 in active) else "working"
    return recs


def record(js, aid, label, kind, ends, fd, live):
    """The common record every source adapter returns."""
    started, doing, report, handed = transcript(js)
    mt = os.path.getmtime(js)
    ends = ends + ([(handed, "done")] if handed else [])
    return {"id": aid, "label": label, "type": kind, "started": started, "last": int(mt),
            "state": state_of(aid, label, started, mt, ends, fd, live), "doing": doing, "report": report}


def metas(folder):
    """(agent id, transcript, meta dict) for every agent-*.meta.json in folder that has a transcript."""
    for meta in glob.glob(os.path.join(folder, "agent-*.meta.json")):
        js = meta[:-len(".meta.json")] + ".jsonl"
        if not os.path.exists(js):
            continue
        try:
            m = json.load(open(meta))
        except ValueError:
            m = {}
        yield os.path.basename(meta)[len("agent-"):-len(".meta.json")], js, m


def one_offs(subs, notes, fd, live):
    """Agent-tool sub-agents: ended by a handback, a feed done/error or a task notification."""
    return [record(js, aid, m.get("description", ""), m.get("agentType", ""), [notes[aid]] if aid in notes else [], fd, live)
            for aid, js, m in metas(subs)]


def workflow_agents(subs, notes, runs, fd, live):
    """Workflow (swarm) agents: ended by their journal result or failed row, else by a later `started` row with the same label begun after
    the agent went silent (a resumed run), else by the run's task notification or TaskStop."""
    out = []
    for wf in glob.glob(os.path.join(subs, "workflows", "wf_*")):
        tid, name = runs.get(os.path.basename(wf), ("", ""))
        tok = name.split("-")[0]
        run_end = [notes[tid]] if tid in notes else []
        done, starts = agent_ends.journal(wf)
        found = list(metas(wf))
        begun = {aid: iso_s(transcript(js)[0]) for aid, js, m in found}
        for aid, js, m in found:
            label = ((tok + " ") if TICKET.match(tok) else "") + m.get("description", "")
            mt = os.path.getmtime(js)
            end = [(mt, done[aid])] if aid in done else [(mt, "stale")] if agent_ends.resumed(aid, starts, lambda a: begun.get(a, 0), mt) else run_end
            out.append(record(js, aid, label, "workflow", end, fd, live))
    return out


def shown(recs, now=None):
    """Every working agent, then the ended ones of the last 24 h, newest first, at most 10."""
    now = now or time.time()
    live = [r for r in recs if r["state"] == "working"]
    ended = sorted((r for r in recs if r["state"] != "working" and now - r["last"] < RECENT_S), key=lambda r: r["last"], reverse=True)
    return sorted(live, key=lambda r: r["started"], reverse=True) + ended[:RECENT_N]


def subagents(fd, live):
    """(session id, live and recent agents) of the newest session that spawned any, one adapter per source."""
    dirs = sorted(glob.glob(os.path.join(PROJ, "*/subagents")), key=os.path.getmtime)
    if not dirs:
        return "", []
    session = os.path.basename(os.path.dirname(dirs[-1]))
    notes, runs = parent(os.path.join(PROJ, session + ".jsonl"))
    recs = one_offs(dirs[-1], notes, fd, live) + workflow_agents(dirs[-1], notes, runs, fd, live)
    return session, shown(hold(recs))


def tmux_sessions():
    """Names of the running tmux sessions."""
    return set(run(["tmux", "ls", "-F", "#{session_name}"], 3).split())


def unit_states(names):
    """{name: ActiveState} of agent@<name>.service."""
    props = system.unit_props(["ActiveState"], ["agent@%s.service" % n for n in names])
    return {n: props.get("agent@%s.service" % n, {}).get("ActiveState", "") for n in names}


def newest_write(folder):
    """Unix mtime of the newest transcript in a project folder, 0 when there is none."""
    return max((os.path.getmtime(p) for p in glob.glob(os.path.join(folder, "*.jsonl"))), default=0)


def newest_session():
    """Id of the orchestrator session, from the newest transcript in PROJ, "" when there is none."""
    return max(glob.glob(os.path.join(PROJ, "*.jsonl")), key=os.path.getmtime, default="")[len(PROJ) + 1:-len(".jsonl")]


def persistent(roster, session):
    """Roster rows with state running|idle|off, and the orchestrator's state; running = an active unit or a transcript written < 60 s ago."""
    tmux, units, now = tmux_sessions(), unit_states([r["name"] for r in roster]), time.time()
    projects = os.path.dirname(PROJ)
    out = []
    for r in roster:
        if units.get(r["name"]) in ("active", "activating", "reloading", "deactivating"):
            st = "running"
        elif r["name"] in tmux:
            st = "running" if now - newest_write(os.path.join(projects, (os.path.join(AGENTS_DIR, r["name"])).replace("/", "-"))) < RUNNING_S else "idle"
        else:
            st = "idle" if r.get("enabled") == "enabled" else "off"
        out.append(dict(r, state=st))
    js = os.path.join(PROJ, session + ".jsonl")
    orch = "off" if ORCH_TMUX not in tmux else "running" if os.path.exists(js) and now - os.path.getmtime(js) < RUNNING_S else "idle"
    return out, orch


def report_line(name):
    """First body line of ~/agents/<name>/REPORT.md, run metadata skipped."""
    p = os.path.join(AGENTS_DIR, name, "REPORT.md")
    if not os.path.exists(p):
        return ""
    for l in open(p, errors="replace"):
        l = l.strip()
        if l and not REPORT_SKIP.match(l):
            return re.sub(r"^[-*] |^\d+\. ", "", l)[:240]
    return ""


def claims():
    if not os.path.exists(CLAIMS):
        return []
    return [l[2:].strip() for l in open(CLAIMS, errors="replace") if l.startswith("- ")]


def collect():
    orb = orbiters()
    live = {o.get("id", "").lower() for o in orb}
    session, subs = subagents(feed(), live)
    session = newest_session() or session
    roster = [dict(a, report=report_line(a["name"])) for a in swr({"agents": system.BLOCKS["agents"]})["agents"]]
    roster, orch = cached("agents_persist", 5, lambda: persistent(roster, session), (roster, "idle"))
    return {"orchestrator": {"name": "DarkSaddler", "session": session[:8], "state": orch}, "subagents": subs, "orbiters": orb,
            "roster": roster, "claims": claims()}


def payload():
    return cached("agents_view", 3, collect, {})


@route("GET", "/api/agents")
def agents_route(h, path):
    h.json(payload())
