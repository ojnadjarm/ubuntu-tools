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
MAX_FILES = 5
FILE_KEYS = {"id", "name", "size", "mime"}
LAST_TEXT = 80
SEARCH_LIMIT = 30
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
    extra = set(msg) - set(KEYS) - {"files"}
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
    files = m.get("files") or []
    if not isinstance(files, list) or len(files) > MAX_FILES or any(
            not isinstance(f, dict) or set(f) != FILE_KEYS for f in files):
        raise ValueError(f"bad files: at most {MAX_FILES} of {{{', '.join(sorted(FILE_KEYS))}}}")
    if not isinstance(m.get("text"), str) or not (m["text"].strip() or files):
        raise ValueError("bad text: empty")
    if len(m["text"]) > MAX_TEXT:
        raise ValueError(f"text over {MAX_TEXT} characters: put it in a file and send the path")
    if type(m["hop"]) is not int or m["hop"] < 0:
        raise ValueError(f"bad hop: {m['hop']!r}")
    if m["re"] is not None and type(m["re"]) is not int:
        raise ValueError(f"bad re: {m['re']!r}")
    return m


def post(msg):
    """Store one message (ch, from, text; to, kind, re, hop, files optional); returns its id (UTC ms, rising)."""
    m = _validate(msg)
    with _locked():
        last_path = os.path.join(root(), "last-id")
        mid = max(_now_ms(), _read_json(last_path, 0) + 1)
        when = _utc(mid)
        row = {"id": mid, "ts": when.strftime("%Y-%m-%dT%H:%M:%S.") + f"{mid % 1000:03d}Z",
               **{k: m[k] for k in KEYS}, **({"files": m["files"]} if m.get("files") else {})}
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


def _tail(path, block=8192):
    """The last valid row of a month file, read backwards from its end in growing blocks; None when it has none."""
    with open(path, "rb") as f:
        end = f.seek(0, os.SEEK_END)
        while True:
            start = max(0, end - block)
            f.seek(start)
            lines = f.read(end - start).split(b"\n")[1 if start else 0:]
            for line in reversed(lines):
                try:
                    return json.loads(line)
                except ValueError:
                    continue
            if not start:
                return None
            block *= 4


def _last(paths):
    """{id, from, ts, kind, text clipped to LAST_TEXT, files: count} of a channel's newest message; None when empty."""
    for p in reversed(paths):
        r = _tail(p)
        if r:
            text = r.get("text", "")
            return {"id": r["id"], "from": r["from"], "ts": r["ts"], "kind": r.get("kind", "msg"),
                    "text": text[:LAST_TEXT] + ("…" if len(text) > LAST_TEXT else ""), "files": len(r.get("files") or [])}
    return None


def read(ch, after=None, limit=200, before=None):
    """Messages of a channel, oldest first: the newest `limit` (older than `before` when given), or with `after` the
    first `limit` newer than it."""
    paths = _files().get(_channel(ch), [])
    if after is None:
        before = None if before is None else int(before)
        month = f"{_utc(before):%Y-%m}" if before else "9999"
        out = []
        for p in reversed(paths):
            if FILE.match(os.path.basename(p)).group(2) > month:
                continue
            out = [r for r in _rows(p) if before is None or r["id"] < before] + out
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


def recent(seat, after=None, before=None, limit=50):
    """Messages of every channel the seat sees, oldest first: the newest `limit` (older than `before`), or with `after`
    the first `limit` newer than it."""
    rows = []
    for c in visible(seat):
        rows += read(c, after=after, before=before, limit=limit)
    rows.sort(key=lambda r: r["id"])
    return rows[:limit] if after is not None else rows[-limit:]


def search(seat, q, ch=None, limit=SEARCH_LIMIT):
    """Messages of the seat's visible channels (or of ch) whose text holds every word of q in any case: the newest
    `limit`, oldest first, read newest month first; ValueError when q has under 2 characters."""
    if not isinstance(q, str) or len(q.strip()) < 2:
        raise ValueError("bad q: 2 characters at least")
    want = q.casefold().split()
    files = _files()
    chans = visible(seat) if ch is None else [c for c in visible(seat) if c == _channel(ch)]
    months = {}
    for c in chans:
        for p in files[c]:
            months.setdefault(FILE.match(os.path.basename(p)).group(2), []).append(p)
    out = []
    for month in sorted(months, reverse=True):
        for p in months[month]:
            out += [r for r in _rows(p) if all(w in (r.get("text") or "").casefold() for w in want)]
        if len(out) >= limit:
            break
    out.sort(key=lambda r: r["id"])
    return out[-limit:] if limit else []


def visible(seat):
    """The channels with a file that the seat sees: direct messages only its own; the owner sees all."""
    return [ch for ch in _files() if not ch.startswith("dm-") or seat == "owner" or seat in ch[3:].split("--")]


def _cursors(seat):
    return os.path.join(root(), "cursors", f"{_name(seat, 'seat')}.json")


def channels(seat):
    """[{ch, unread, last}] the seat can see (direct messages only its own; the owner sees all); unread skips its own,
    last is the newest message in brief (see _last)."""
    cur = _read_json(_cursors(seat), {})
    out = []
    files = _files()
    for ch in visible(seat):
        paths = files[ch]
        seen = cur.get(ch, 0)
        unread = sum(1 for p in paths for r in _rows(p) if r["id"] > seen and r["from"] != seat)
        out.append({"ch": ch, "unread": unread, "last": _last(paths)})
    return out


def cursor(seat, ch):
    """The id the seat last read in a channel (0: never)."""
    return _read_json(_cursors(seat), {}).get(_channel(ch), 0)


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
