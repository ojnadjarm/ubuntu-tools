"""Chat dispatch (T1515): after a post, route the message and hand each due wake to its seat's adapter."""
import contextlib
import fcntl
import glob
import json
import os
import subprocess
import sys
import time

import chat_route
import chat_store
import chat_wake
import org


def paused():
    """True while the PAUSED file exists in the store (`chat pause`, `agents-stop`)."""
    return os.path.exists(os.path.join(chat_store.root(), "PAUSED"))


def plan_pct():
    """95 when `plan-usage --check 95 --cached` says the plan is at or above it, else 0 (no reading counts as 0)."""
    try:
        rc = subprocess.run(["plan-usage", "--check", str(chat_route.PLAN_STOP), "--cached"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10).returncode
    except (OSError, subprocess.TimeoutExpired):
        return 0
    return chat_route.PLAN_STOP if rc == 1 else 0


@contextlib.contextmanager
def counters():
    """Today's {seat: agent-caused wakes} under the counters lock; changes are written back on exit."""
    folder = os.path.join(chat_store.root(), "counters")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"{time.strftime('%Y-%m-%d')}.json")
    with open(os.path.join(folder, ".lock"), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(path) as f:
                data = json.load(f)
        except (OSError, ValueError):
            data = {}
        yield data
        tmp = f"{path}.{os.getpid()}.tmp"
        with open(tmp, "w") as f:
            json.dump(data, f)
        os.replace(tmp, path)


def today():
    """Today's {seat: agent-caused wakes}, read without the lock (the file is replaced whole)."""
    try:
        with open(os.path.join(chat_store.root(), "counters", f"{time.strftime('%Y-%m-%d')}.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def uncount(seat):
    """Take back one of today's wakes of a seat whose batch was withdrawn before it fired."""
    with counters() as day:
        if day.get(seat, 0) > 0:
            day[seat] -= 1


def park(seat, msg, why):
    """Append a wake that was not delivered to state/chat/queue/<seat>.jsonl (id, ch, why) for a later run."""
    folder = os.path.join(chat_store.root(), "queue")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, f"{seat}.jsonl"), "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.write(json.dumps({"id": msg["id"], "ch": msg["ch"], "why": why}) + "\n")


def dead(seat, row, err):
    """Move a parked row that made the drain raise to state/chat/queue/dead.jsonl and warn once on stderr."""
    with open(os.path.join(chat_store.root(), "queue", "dead.jsonl"), "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.write(json.dumps({"seat": seat, **row, "error": str(err)}) + "\n")
    print(f"chat: queue row {seat} {row['id']} moved to queue/dead.jsonl: {err}", file=sys.stderr)


def new_day():
    """True for the one call that creates today's drain marker counters/<day>.drained: a new day has started."""
    folder = os.path.join(chat_store.root(), "counters")
    os.makedirs(folder, exist_ok=True)
    try:
        path = os.path.join(folder, f"{time.strftime('%Y-%m-%d')}.drained")
        os.close(os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
    except FileExistsError:
        return False
    return True


def parsed(f):
    """The parked rows of an open queue file; a line that does not parse is skipped."""
    rows = []
    for line in f:
        try:
            r = json.loads(line)
            rows.append({"id": int(r["id"]), "ch": r["ch"], "why": r["why"]})
        except (ValueError, TypeError, KeyError):
            continue
    return rows


def drain(seats=None):
    """[(seat, outcome)] of re-sending each parked wake once after a sweep of dead-timer batches; none while paused;
    old hop parks re-sent too; a row that raises is dead-lettered; rows not reached on an abort are parked
    again."""
    if paused():
        return []
    chat_wake.sweep()
    seats = org.seats() if seats is None else seats
    out = []
    for path in sorted(glob.glob(os.path.join(chat_store.root(), "queue", "*.jsonl"))):
        if os.path.basename(path) == "dead.jsonl":
            continue
        seat = os.path.basename(path)[:-len(".jsonl")]
        with open(path, "r+") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            rows = parsed(f)
            f.seek(0)
            f.truncate()
        done = set()
        try:
            while rows:
                r = rows[0]
                if r["id"] not in done:
                    done.add(r["id"])
                    try:
                        got = chat_store.read(r["ch"], after=r["id"] - 1, limit=1)
                        if got and got[0]["id"] == r["id"]:
                            out += dispatch(got[0], seats, only=seat)
                    except Exception as e:
                        dead(seat, r, e)
                rows.pop(0)
        finally:
            for r in rows:
                park(seat, r, r["why"])
    return out


def dispatch(msg, seats=None, only=None):
    """[(seat, outcome)] of a stored message (only: one seat's wakes); a day's first dispatch drains the queue first;
    each one not paused sweeps dead-timer batches."""
    seats = org.seats() if seats is None else seats
    if only is None and new_day():
        drain(seats)
    if only is None and not paused():
        chat_wake.sweep()
    by_id = {s["id"]: s for s in seats}
    plan = 0 if msg["from"] == "owner" else plan_pct()
    due = chat_route.wakes(msg, seats, paused=paused(), plan=plan)
    out = []
    for w in due:
        if only and w["seat"] != only:
            continue
        cls = chat_wake.ADAPTERS.get(by_id[w["seat"]]["wake"])
        if w["queue"]:
            outcome = w["queue"]
        elif cls is None:
            outcome = chat_wake.REFUSED
        else:
            outcome = cls(seats=seats).deliver(w["seat"], [msg])
        if outcome == chat_wake.DELIVERED and w["count"]:
            with counters() as today:
                today[w["seat"]] = today.get(w["seat"], 0) + 1
        if outcome not in (chat_wake.DELIVERED, chat_wake.QUEUED):
            park(w["seat"], msg, outcome)
        chat_store.audit({"wake": w["seat"], "id": msg["id"], "reason": w["reason"], "outcome": outcome})
        out.append((w["seat"], outcome))
    return out
