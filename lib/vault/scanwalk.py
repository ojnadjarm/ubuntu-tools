"""The client half of `secret scan`: which files to look at, opened here and handed to the broker by descriptor."""
import glob
import os
import socket

from . import wire
from .scan import MAX_FDS

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", "backups"}
MAX_BYTES = 64 << 20


def roots(wide, env=os.environ):
    """The logs (audit log, every agent's logs); wide adds transcripts, the drop, papers, memory and shell history."""
    home = env.get("HOME", os.path.expanduser("~"))
    agents = env.get("HARNESS_HOME", os.path.join(home, "agents"))
    out = [os.path.join(agents, "log")] + sorted(glob.glob(os.path.join(agents, "*", "logs")))
    if wide:
        out += [os.path.join(env.get("HARNESS_CONTEXT_DIR", os.path.join(home, ".claude")), "projects"),
                os.path.join(home, "drop"), env.get("AGENT_WORK", os.path.join(home, "agent-work")),
                env.get("MEMORY_HOME", os.path.join(home, "memory")), os.path.join(home, ".bash_history")]
    return [p for p in out if os.path.exists(p)]


def files(paths):
    """(path) of every regular file under paths up to MAX_BYTES; symlinks and SKIP_DIRS are not followed."""
    for p in paths:
        if os.path.isfile(p) and not os.path.islink(p):
            yield p
            continue
        for d, subs, names in os.walk(p):
            subs[:] = [s for s in subs if s not in SKIP_DIRS]
            for n in names:
                f = os.path.join(d, n)
                try:
                    st = os.lstat(f)
                except OSError:
                    continue
                if os.path.isfile(f) and not os.path.islink(f) and st.st_size <= MAX_BYTES:
                    yield f


def batch(sock_path, paths, agent=""):
    """Send one batch (at most MAX_FDS paths) to the broker; the reply dict, with unopenable paths in `skipped`."""
    fds, labels, skipped = [], [], []
    for p in paths:
        try:
            fds.append(os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK))
            labels.append(p)
        except OSError:
            skipped.append(p)
    try:
        if not fds:
            return {"ok": True, "files": 0, "bytes": 0, "hits": {}, "where": [], "skipped": skipped}
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(600)
            s.connect(sock_path)
            with s.makefile("rwb") as f:
                wire.write_msg(f, {"op": "scan", "files": labels, "agent": agent})
                r = wire.read_msg(f)
                if not r.get("ok"):
                    return r
                socket.send_fds(s, [b"F"], fds)
                r = wire.read_msg(f)
    finally:
        for fd in fds:
            os.close(fd)
    if r.get("ok"):
        r["skipped"] = skipped + r.get("skipped", [])
    return r


def run(sock_path, paths, agent=""):
    """Scan every file under paths in batches; the summed reply."""
    total = {"ok": True, "files": 0, "bytes": 0, "values": 0, "hits": {}, "where": [], "skipped": []}
    todo = list(files(paths))
    for i in range(0, len(todo), MAX_FDS):
        r = batch(sock_path, todo[i:i + MAX_FDS], agent)
        if not r.get("ok"):
            return r
        total["files"] += r["files"]
        total["bytes"] += r["bytes"]
        total["values"] = max(total["values"], r.get("values", 0))
        for k, v in r["hits"].items():
            total["hits"][k] = total["hits"].get(k, 0) + v
        total["where"] += r["where"]
        total["skipped"] += r["skipped"]
    return total
