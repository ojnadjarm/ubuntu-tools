"""Chat dispatch (T1515): after a post, route the message and hand each due wake to its seat's adapter."""
import contextlib
import fcntl
import glob
import json
import os
import subprocess
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


def new_day():
    """True for the one call that creates today's counters file: a new day has started."""
    folder = os.path.join(chat_store.root(), "counters")
    os.makedirs(folder, exist_ok=True)
    try:
        path = os.path.join(folder, f"{time.strftime('%Y-%m-%d')}.json")
        os.close(os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
    except FileExistsError:
        return False
    return True


def drain(seats=None):
    """[(seat, outcome)] of re-sending each parked wake once; none while paused, still-held ones park again."""
    if paused():
        return []
    seats = org.seats() if seats is None else seats
    out = []
    for path in sorted(glob.glob(os.path.join(chat_store.root(), "queue", "*.jsonl"))):
        seat = os.path.basename(path)[:-len(".jsonl")]
        with open(path, "r+") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            rows = [json.loads(line) for line in f if line.strip()]
            f.seek(0)
            f.truncate()
        done = set()
        for r in rows:
            if r["id"] in done:
                continue
            done.add(r["id"])
            got = chat_store.read(r["ch"], after=r["id"] - 1, limit=1)
            if got and got[0]["id"] == r["id"]:
                out += dispatch(got[0], seats, only=seat)
    return out


def dispatch(msg, seats=None, only=None):
    """[(seat, outcome)] of a stored message (only: one seat's wakes); a day's first dispatch drains the queue first."""
    seats = org.seats() if seats is None else seats
    if only is None and new_day():
        drain(seats)
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
