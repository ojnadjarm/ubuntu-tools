"""Chat store (T1515): the only writer of the chat files; post, read, channels, mark, audit under one flock."""
import contextlib
import datetime
import fcntl
import json
import os
import re
import time

KINDS = ("msg", "ask", "answer", "system")
KEYS = ("ch", "from", "to", "kind", "text", "re", "hop")
MAX_TEXT = 2000
NAME = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
FILE = re.compile(r"^([a-z0-9][a-z0-9-]*)\.(\d{4}-\d{2})\.jsonl$")


def _now_ms():
    return int(time.time() * 1000)


def root():
    """The store folder: $HARNESS_HOME/state/chat (default ~/agents/state/chat)."""
    home = os.environ.get("HARNESS_HOME") or os.path.expanduser("~/agents")
    return os.path.join(home, "state", "chat")


def dm(a, b):
    """The direct-message channel id of two seats, order-free."""
    x, y = sorted((a, b))
    return f"dm-{x}--{y}"


def _utc(ms):
    return datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc)


def _name(value, what):
    if not isinstance(value, str) or not NAME.match(value):
        raise ValueError(f"bad {what}: {value!r}")
    return value


def _channel(ch):
    return _name(ch, "channel")


@contextlib.contextmanager
def _locked():
    os.makedirs(root(), exist_ok=True)
    with open(os.path.join(root(), ".lock"), "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def _append(path, row):
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.write(fd, (json.dumps(row, ensure_ascii=False) + "\n").encode())
    finally:
        os.close(fd)


def _write_json(path, data):
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def _read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _validate(msg):
    extra = set(msg) - set(KEYS)
    if extra:
        raise ValueError(f"unknown keys: {', '.join(sorted(extra))}")
    m = {"to": [], "kind": "msg", "re": None, "hop": 0, **msg}
    _channel(m.get("ch"))
    _name(m.get("from"), "from")
    if not isinstance(m["to"], list):
        raise ValueError("bad to: a list of seats")
    for t in m["to"]:
        _name(t, "to")
    if m["kind"] not in KINDS:
        raise ValueError(f"bad kind: {m['kind']!r} not in {KINDS}")
    if not isinstance(m.get("text"), str) or not m["text"].strip():
        raise ValueError("bad text: empty")
    if len(m["text"]) > MAX_TEXT:
        raise ValueError(f"text over {MAX_TEXT} characters: put it in a file and send the path")
    if type(m["hop"]) is not int or m["hop"] < 0:
        raise ValueError(f"bad hop: {m['hop']!r}")
    if m["re"] is not None and type(m["re"]) is not int:
        raise ValueError(f"bad re: {m['re']!r}")
    return m


def post(msg):
    """Store one message (ch, from, text; to, kind, re, hop optional); returns its id (UTC ms, rising)."""
    m = _validate(msg)
    with _locked():
        last_path = os.path.join(root(), "last-id")
        mid = max(_now_ms(), _read_json(last_path, 0) + 1)
        when = _utc(mid)
        row = {"id": mid, "ts": when.strftime("%Y-%m-%dT%H:%M:%S.") + f"{mid % 1000:03d}Z",
               **{k: m[k] for k in KEYS}}
        _append(os.path.join(root(), f"{m['ch']}.{when:%Y-%m}.jsonl"), row)
        _write_json(last_path, mid)
        _append(os.path.join(root(), "audit.jsonl"), {k: row[k] for k in ("ts", "id", "ch", "from", "kind")})
    return mid


def audit(entry):
    """Append one audit line (a held message: seat, channel, rule; never its text) with a ts."""
    ts = _utc(_now_ms()).strftime("%Y-%m-%dT%H:%M:%SZ")
    with _locked():
        _append(os.path.join(root(), "audit.jsonl"), {"ts": ts, **entry})


def _files():
    """{channel: [month file paths, oldest first]} of the store."""
    out = {}
    try:
        names = sorted(os.listdir(root()))
    except OSError:
        return out
    for n in names:
        f = FILE.match(n)
        if f:
            out.setdefault(f.group(1), []).append(os.path.join(root(), n))
    return out


def _rows(path):
    with open(path) as f:
        for line in f:
            try:
                yield json.loads(line)
            except ValueError:
                continue


def read(ch, after=None, limit=200):
    """Messages of a channel, oldest first: the newest `limit`, or with `after` the first `limit` newer than it."""
    paths = _files().get(_channel(ch), [])
    if after is None:
        out = []
        for p in reversed(paths):
            out = list(_rows(p)) + out
            if len(out) >= limit:
                break
        return out[-limit:] if limit else []
    after = int(after)
    month = f"{_utc(after):%Y-%m}" if after > 0 else ""
    out = []
    for p in paths:
        if FILE.match(os.path.basename(p)).group(2) < month:
            continue
        out += [r for r in _rows(p) if r["id"] > after]
        if len(out) >= limit:
            break
    return out[:limit]


def _cursors(seat):
    return os.path.join(root(), "cursors", f"{_name(seat, 'seat')}.json")


def channels(seat):
    """[{ch, unread}] the seat can see (direct messages only its own; the owner sees all); unread skips its own."""
    cur = _read_json(_cursors(seat), {})
    out = []
    for ch, paths in _files().items():
        if ch.startswith("dm-") and seat != "owner" and seat not in ch[3:].split("--"):
            continue
        seen = cur.get(ch, 0)
        unread = sum(1 for p in paths for r in _rows(p) if r["id"] > seen and r["from"] != seat)
        out.append({"ch": ch, "unread": unread})
    return out


def mark(seat, ch, mid):
    """Move the seat's read cursor of a channel to id `mid`; it never moves back."""
    path, mid = _cursors(seat), int(mid)
    _channel(ch)
    with _locked():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        cur = _read_json(path, {})
        if mid > cur.get(ch, 0):
            cur[ch] = mid
            _write_json(path, cur)
