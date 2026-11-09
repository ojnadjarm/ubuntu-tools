"""Live Claude Code sessions from the registry (~/.claude/sessions/<pid>.json) with their org seat; protected ones on/off only."""
import glob
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "bin"))
import org  # noqa: E402
import protectedlib  # noqa: E402

STATES = {"busy": "working", "idle": "idle"}


def registry_dir():
    """The registry folder: $CLAUDE_SESSIONS_DIR, else ~/.claude/sessions."""
    return os.environ.get("CLAUDE_SESSIONS_DIR") or os.path.expanduser("~/.claude/sessions")


def _alive(pid, proc_start):
    """True when pid runs and is the same process (start time in /proc/<pid>/stat matches procStart)."""
    try:
        with open(f"/proc/{int(pid)}/stat") as f:
            return f.read().rsplit(")", 1)[1].split()[19] == str(proc_start)
    except (OSError, ValueError, IndexError):
        return False


def _under(cwd, folder):
    return cwd == folder or cwd.startswith(folder.rstrip("/") + "/")


def _place(cwd, seats):
    """(seat, parent) for a folder: the seat matching it exactly, else no seat under the deepest seat folder holding it."""
    folders = [(os.path.realpath(os.path.expanduser(s["match"])), s) for s in seats if s["match"]]
    exact = next((s for f, s in folders if f == cwd), None)
    if exact:
        return exact["id"], exact["parent"]
    holders = sorted((f for f in folders if _under(cwd, f[0])), key=lambda f: len(f[0]))
    return None, holders[-1][1]["id"] if holders else None


def locate(cwd, protected):
    """(protected project or None, folder) of a session folder; a protected one is matched as written and never resolved
    (no stat), else the real path is matched again. protected None (matcher down) fails closed as project ''."""
    cwd = os.path.normpath(cwd)
    if protected is None:
        return "", cwd
    project = protectedlib.project(protected, cwd)
    if project:
        return project, cwd
    real = os.path.realpath(cwd)
    return protectedlib.project(protected, real), real


def _pull_seat(project, seats):
    """The pull seat named after a protected project: on/off of that project's session, nothing else."""
    return next((s["id"] for s in seats if s["wake"] == "pull" and s["id"] == project), None)


def _started_by(reg):
    """The agent of an `agent-<name>` session (agent-run), else owner for a terminal session, else the entrypoint."""
    name = reg.get("name") or ""
    if name.startswith("agent-"):
        return name[len("agent-"):]
    return "owner" if reg.get("entrypoint") == "cli" else reg.get("entrypoint")


def live(directory=None, seats=None):
    """Live sessions sorted by pid; a session in a protected folder (or any, if the matcher fails) is {seat, state, since},
    its seat the pull seat named after the project; on/off comes from the registry and /proc only."""
    seats = org.seats() if seats is None else seats
    try:
        protected = protectedlib.eres("path")
    except Exception:
        protected = None
    rows = []
    for f in sorted(glob.glob(os.path.join(directory or registry_dir(), "*.json"))):
        try:
            with open(f) as fh:
                reg = json.load(fh)
            pid, cwd = int(reg["pid"]), reg["cwd"]
            if not _alive(pid, reg.get("procStart")):
                continue
            project, cwd = locate(cwd, protected)
        except (OSError, ValueError, KeyError, TypeError):
            continue
        row = {"seat": None, "state": STATES.get(reg.get("status"), "idle"),
               "since": int(reg.get("statusUpdatedAt") or reg.get("startedAt") or 0) // 1000}
        if project is not None:
            row["seat"] = _pull_seat(project, seats) or _place(cwd, seats)[0]
            rows.append((pid, row))
            continue
        row["seat"], parent = _place(cwd, seats)
        row.update(pid=pid, parent=parent, name=reg.get("name"), cwd=cwd, started_by=_started_by(reg))
        rows.append((pid, row))
    return [r for _, r in sorted(rows, key=lambda x: x[0])]
