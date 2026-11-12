"""Chat router (T1515): pure; a message + org seats give the list of wakes, no I/O; no daily or hop limit (P38, T1576)."""
import re

PLAN_STOP = 95
MENTION = re.compile(r"(?<![\w@.-])@([a-z0-9][a-z0-9-]*)")


def next_hop(sender, parent):
    """Hop of a new message: 0 from the owner or with no parent, else the parent's hop + 1."""
    if sender == "owner" or not parent:
        return 0
    return parent["hop"] + 1


def needs(msg):
    """True when a message wakes the CEO seat: the owner's, a question or answer, or a post marked needs (T1695)."""
    return msg["from"] == "owner" or msg.get("kind") in ("ask", "answer") or bool(msg.get("needs"))


def may_post(seat, ch, org):
    """'' when seat may post in ch, else the refusal; a manager posts only in its direct message with the owner."""
    role = next((s["role"] for s in org if s["id"] == seat), None)
    if role == "manager" and ch != "dm-" + "--".join(sorted((seat, "owner"))):
        return f"a manager posts only in its direct message with the owner (chat post @owner), not in {ch}"
    return ""


def _targets(msg, seats):
    """[(seat id, reason)] the message addresses (a dm: its two members only), first reason per seat, sender and owner left out."""
    out = []
    if msg["ch"].startswith("dm-"):
        out += [(s, "dm") for s in msg["ch"][3:].split("--")]
    else:
        out += [(s, "to") for s in msg.get("to") or []]
        out += [(s, "mention") for s in MENTION.findall(msg["text"].lower())]
    if msg["from"] == "owner" and msg["ch"] in seats:
        out.append((msg["ch"], "own-channel"))
    if msg["ch"] == "harness":
        out += [(s["id"], "ask" if msg.get("kind") == "ask" else "harness") for s in seats.values() if s["role"] == "ceo"]
    seen, uniq = set(), []
    for seat, reason in out:
        if seat in seen or seat == msg["from"] or seat not in seats or seats[seat]["role"] == "owner":
            continue
        seen.add(seat)
        uniq.append((seat, reason))
    return uniq


def wakes(msg, org, paused=False, plan=0):
    """[{seat, reason, queue, count}]: deliver now when queue is None (else paused|plan); count = add 1 to counters."""
    seats = {s["id"]: s for s in org}
    owner = msg["from"] == "owner"
    out = []
    for seat, reason in _targets(msg, seats):
        if paused:
            queue = "paused"
        elif owner:
            queue = None
        elif plan >= PLAN_STOP:
            queue = "plan"
        else:
            queue = None
        out.append({"seat": seat, "reason": reason, "queue": queue, "count": queue is None and not owner})
    return out
