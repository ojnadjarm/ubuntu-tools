"""Phone alert (T1515): an agent's message to the owner pings notify-owner, at most PER_DAY a day per seat."""
import fcntl
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "bin"))
import chat_dispatch  # noqa: E402
import chat_route  # noqa: E402
import chat_store  # noqa: E402
import org  # noqa: E402
import protectedlib  # noqa: E402

PER_DAY = 3
LIMIT = 200


def to_owner(msg):
    """True when an agent's message is a direct message to the owner or names @owner."""
    if msg["from"] == "owner":
        return False
    dm = msg["ch"][3:].split("--") if msg["ch"].startswith("dm-") else []
    return ("owner" in dm or "owner" in (msg.get("to") or [])
            or "owner" in chat_route.MENTION.findall(msg["text"].lower()))


def _protected(seat):
    """True for a pull seat or a seat whose folder is in a protected project; fails closed."""
    try:
        if seat.get("wake") == "pull":
            return True
        folder = os.path.expanduser(seat["match"]) if seat.get("match") else ""
        return bool(folder) and protectedlib.project(protectedlib.eres("path"), folder) is not None
    except Exception:
        return True


def line(msg, seat):
    """The push text: seat, where, one line of the message cut to LIMIT; a protected seat's text is never sent."""
    if _protected(seat):
        return f"[{seat['id']}] wrote to you; read it on the Chat screen"
    where = "to you" if msg["ch"].startswith("dm-") else f"#{msg['ch']}"
    text = f"[{seat['id']}] {where}: {' '.join(msg['text'].split())}"
    return text if len(text) <= LIMIT else text[:LIMIT - 1] + "…"


def alert(msg, seats=None):
    """sent|cap|paused|fail for an agent's message to the owner (audited), else None; a failed push is not counted."""
    if not to_owner(msg):
        return None
    seats = {s["id"]: s for s in (org.seats() if seats is None else seats)}
    seat = seats[msg["from"]]
    root = chat_store.root()
    folder = os.path.join(root, "counters")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"alerts-{time.strftime('%Y-%m-%d')}.json")
    with open(os.path.join(folder, ".alerts.lock"), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(path) as f:
                today = json.load(f)
        except (OSError, ValueError):
            today = {}
        if chat_dispatch.paused():
            outcome = "paused"
        elif today.get(seat["id"], 0) >= PER_DAY:
            outcome = "cap"
        else:
            try:
                rc = subprocess.run(["notify-owner", "-t", f"chat: {seat['name']}", line(msg, seat)],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30).returncode
            except (OSError, subprocess.TimeoutExpired):
                rc = 1
            outcome = "sent" if rc == 0 else "fail"
        if outcome == "sent":
            today[seat["id"]] = today.get(seat["id"], 0) + 1
            with open(f"{path}.tmp", "w") as f:
                json.dump(today, f)
            os.replace(f"{path}.tmp", path)
    chat_store.audit({"alert": seat["id"], "id": msg["id"], "outcome": outcome})
    return outcome
