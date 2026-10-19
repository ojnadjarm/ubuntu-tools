"""End signals of Claude Code sub-agents, shared by the dashboard's Agents list and orbit-hook's sweep (stdlib only)."""
import json, os, re
from datetime import datetime

NOTE = re.compile(r"<task-id>([\w-]+)</task-id>.*?<status>(completed|failed|killed|stopped)</status>")
STOP = re.compile(r'"name": ?"TaskStop", ?"input": ?\{"task_id": ?"(\w+)"')
LAUNCH = re.compile(r'"taskId": ?"(\w+)", ?"taskType": ?"local_workflow", ?"workflowName": ?"([^"]*)", ?"runId": ?"([^"]+)"')
NOTE_STATE = {"completed": "done", "failed": "error", "killed": "stale", "stopped": "stale"}
SLACK_S = 60
CHUNK = 4 << 20


def iso_s(ts):
    """Unix seconds of an ISO timestamp, 0 when it does not parse."""
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return 0


def memo():
    """An empty scan state: [bytes read, {task id: (ts, state)}, {run id: (task id, workflow name)}, {task id: run id}]."""
    return [0, {}, {}, {}]


def scan(js, m):
    """Fold the lines appended to an orchestrator transcript since the last call into m (task notifications, TaskStop calls, workflow launches)."""
    try:
        size = os.path.getsize(js)
    except OSError:
        return m
    if size < m[0]:
        m[:] = memo()
    with open(js, "rb") as f:
        f.seek(m[0])
        buf, left = b"", size - m[0]
        while left > 0:
            got = f.read(min(CHUNK, left))
            if not got:
                break
            left -= len(got)
            buf += got
            cut = buf.rfind(b"\n") + 1
            m[0] += cut
            fold(buf[:cut], m)
            buf = buf[cut:]
    return m


def fold(raw, m):
    """Fold complete transcript lines (bytes) into the scan state m."""
    for line in raw.decode("utf8", "replace").splitlines():
        notes, runs, stops = NOTE.findall(line), LAUNCH.findall(line), STOP.findall(line)
        if not notes and not runs and not stops:
            continue
        try:
            t = iso_s(json.loads(line).get("timestamp", ""))
        except ValueError:
            continue
        for tid, status in notes:
            if t >= m[1].get(tid, (0,))[0]:
                m[1][tid] = (t, NOTE_STATE[status])
        for tid in stops:
            m[1].setdefault(tid, (t, "stale"))
        for tid, name, rid in runs:
            m[2][rid] = (tid, name)
            m[3][tid] = rid


def journal(wf):
    """({agent id: done|error} from `result`/`failed` rows, [(label, agent id)] of `started` rows) of a workflow run folder."""
    done, starts = {}, []
    jr = os.path.join(wf, "journal.jsonl")
    for line in open(jr, errors="replace") if os.path.exists(jr) else []:
        try:
            j = json.loads(line)
        except ValueError:
            continue
        if j.get("type") == "started":
            starts.append((j.get("label"), j.get("agentId")))
        if j.get("type") in ("result", "failed"):
            done[j.get("agentId")] = "done" if j["type"] == "result" else "error"
    return done, starts


def began(js):
    """Unix seconds of a transcript's first line, 0 when unreadable."""
    try:
        with open(js, "rb") as f:
            return iso_s(json.loads(f.readline()).get("timestamp", ""))
    except (OSError, ValueError, AttributeError):
        return 0


def resumed(aid, starts, begun, last):
    """True when a later `started` row with this agent's label belongs to an agent that began (begun(id) → s) after this one went silent at last."""
    mine = [i for i, s in enumerate(starts) if s[1] == aid]
    return bool(mine) and any(l == starts[mine[0]][0] and begun(a) >= last for l, a in starts[mine[0] + 1:])
