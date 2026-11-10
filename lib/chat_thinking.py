"""Who is thinking in chat (T1515 P38): each woken seat and channel is starting or thinking, read from real process state.

PoInbox: starting while the wake sits in the 20 s batch or the inbox; thinking while its request is in current/ and
po-run holds the PO's lock (/proc/locks). Channel: thinking while the seat's live session is busy; starting while it has
been idle since before the line. Gone when the run ends or the seat posts in that channel after the wake."""
import os

import chat_store
import chat_wake
import org


def _locks():
    """The dev:inode keys of every file lock held on the machine."""
    try:
        with open("/proc/locks") as f:
            return {w for line in f for w in line.split() if w.count(":") == 2}
    except OSError:
        return set()


def _key(path):
    try:
        st = os.stat(path)
    except OSError:
        return None
    return f"{os.major(st.st_dev):02x}:{os.minor(st.st_dev):02x}:{st.st_ino}"


def _po(seat, rec, locks):
    """starting|thinking|None of a PoInbox wake."""
    d = os.path.join(chat_wake._home(), f"po-{seat}")
    if not rec["req"]:
        return "starting" if rec["id"] in chat_wake.pending(seat) else None
    if os.path.exists(os.path.join(d, "inbox", rec["req"])):
        return "starting"
    if os.path.exists(os.path.join(d, "current", rec["req"])) and _key(os.path.join(d, ".po-run.lock")) in locks:
        return "thinking"
    return None


def _channel(seat, rec, seats):
    """starting|thinking|None of a Channel wake, from the seat's session status in the registry."""
    reg = chat_wake.Channel(seats=seats).session(seat)
    if reg is None:
        return None
    if reg.get("status") == "busy":
        return "thinking"
    return "starting" if int(reg.get("statusUpdatedAt") or 0) < rec["at"] else None


def _replied(seat, ch, mid):
    """True when the seat posted in ch after message mid."""
    return any(m["from"] == seat for m in chat_store.read(ch, after=mid))


def now(seats=None):
    """[{seat, ch, state, since}] of every seat woken and still starting or thinking, since = wake time in s."""
    seats = org.seats() if seats is None else seats
    locks, out = None, []
    for s in seats:
        if s.get("wake") not in ("po-inbox", "channel"):
            continue
        for ch, rec in sorted(chat_wake.woken(s["id"]).items()):
            if s["wake"] == "po-inbox":
                locks = _locks() if locks is None else locks
                state = _po(s["id"], rec, locks)
            else:
                state = _channel(s["id"], rec, seats)
            if state and not _replied(s["id"], ch, rec["id"]):
                out.append({"seat": s["id"], "ch": ch, "state": state, "since": rec["at"] // 1000})
    return out
