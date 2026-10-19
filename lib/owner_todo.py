"""Owner to-do ledger: append-only JSONL of add/done/reopen events; the latest event per id decides its state."""
import fcntl, json, os
from datetime import datetime

REL = "agents/state/owner-todo.jsonl"


def path(home=None):
    """The ledger file: $OWNER_TODO_LEDGER, else <home>/agents/state/owner-todo.jsonl."""
    return os.environ.get("OWNER_TODO_LEDGER") or os.path.join(home or os.path.expanduser("~"), REL)


def _events(data):
    """Valid events from the ledger bytes, plus one problem string per line that is not UTF-8, not JSON or not an event."""
    out, bad = [], []
    for n, raw in enumerate(data.split(b"\n"), 1):
        if not raw.strip():
            continue
        try:
            line = raw.decode()
        except UnicodeDecodeError:
            line = raw.decode(errors="replace")
            bad.append("line %d: not UTF-8" % n)
        try:
            e = json.loads(line)
        except ValueError:
            bad.append("line %d: not JSON" % n)
            continue
        if not (isinstance(e, dict) and e.get("id") not in (None, "") and isinstance(e.get("op"), str)):
            bad.append("line %d: not an event" % n)
            continue
        if not isinstance(e["id"], str):
            bad.append("line %d: id is not a string" % n)
            e["id"] = str(e["id"])
        for k in ("text", "how", "src", "ts", "note"):
            if k in e and not isinstance(e[k], str):
                e[k] = str(e[k])
        out.append(e)
    return out, bad


def _fold(events):
    items = {}
    for e in events:
        i = items.get(e["id"])
        if e["op"] == "add" and i is None:
            items[e["id"]] = {"id": e["id"], "text": e.get("text", ""), "how": e.get("how", ""), "src": e.get("src", ""),
                              "added": e.get("ts", ""), "done": False, "done_at": "", "note": ""}
        elif e["op"] == "done" and i:
            i.update(done=True, done_at=e.get("ts", ""), note=e.get("note", ""))
        elif e["op"] == "reopen" and i:
            i.update(done=False, done_at="", note="")
    return sorted(items.values(), key=lambda i: int(i["id"]) if i["id"].isdigit() else 0)


def read(home=None, all=False):
    """(items, problems): every item (all=True) or only the open ones, oldest first, and the lines that were skipped."""
    try:
        with open(path(home), "rb") as f:
            ev, bad = _events(f.read())
    except OSError:
        return [], []
    out = _fold(ev)
    return (out if all else [i for i in out if not i["done"]]), bad


def items(home=None, all=False):
    """Every item (all=True) or only the open ones, oldest first."""
    return read(home, all)[0]


def _append(home, make):
    p = path(home)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "a+b") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        data = f.read()
        e = make(_fold(_events(data)[0]))
        e = dict(ts=datetime.now().astimezone().isoformat(timespec="seconds"), **e)
        lead = b"\n" if data and not data.endswith(b"\n") else b""
        f.write(lead + (json.dumps(e, ensure_ascii=False) + "\n").encode())
    return e


def add(text, how="", src="", by="", home=None):
    """Append a new open item; returns its id (one more than the highest so far)."""
    if not text.strip():
        raise ValueError("text is empty")
    nxt = lambda cur: str(max([int(i["id"]) for i in cur if i["id"].isdigit()] + [0]) + 1)
    return _append(home, lambda cur: {"op": "add", "id": nxt(cur), "text": text.strip(), "how": how.strip(), "src": src, "by": by})["id"]


def _change(op, want_done, id, by, home, **extra):
    def make(cur):
        hit = [i for i in cur if i["id"] == str(id)]
        if not hit:
            raise KeyError("no item %s" % id)
        if hit[0]["done"] != want_done:
            raise ValueError("item %s is already %s" % (id, "done" if hit[0]["done"] else "open"))
        return dict(op=op, id=str(id), by=by, **extra)
    return _append(home, make)


def done(id, note="", by="", home=None):
    """Mark an open item done."""
    return _change("done", False, id, by, home, note=note)


def reopen(id, by="", home=None):
    """Undo a done: the item is open again."""
    return _change("reopen", True, id, by, home)
