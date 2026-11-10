#!/usr/bin/env bash
# T1515-P11: lib/chat_route.wakes (pure): direct messages, @names, the owner in a seat's own channel, harness asks;
# no daily limit per seat (P38), no hop limit (T1576), pause, plan >= 95 %. Fixture org only; the module does no I/O.
set -uo pipefail
AG=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
. "$AG/bin/tests/lib/assert.sh"

is "selftest: the module imports no I/O" "$(grep -cE '^(import|from) |open\(' "$AG/lib/chat_route.py")" 1

python3 - "$AG" <<'PY'
import sys
sys.path.insert(0, f"{sys.argv[1]}/lib")
import chat_route as r

ORG = [
    {"id": "owner", "name": "You", "role": "owner", "parent": None, "wake": None, "match": None},
    {"id": "ceo", "name": "Orchestrator", "role": "ceo", "parent": "owner", "wake": "channel", "match": "~"},
    {"id": "moo", "name": "Moo PO", "role": "po", "parent": "ceo", "wake": "po-inbox", "match": "~/agents/po-moo"},
    {"id": "disc", "name": "Disc PO", "role": "po", "parent": "ceo", "wake": "po-inbox", "match": "~/agents/po-disc"},
]
bad = 0


def check(name, cond, got=""):
    global bad
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f": {got}"))
    bad |= not cond


def msg(ch, frm, text="hi", to=(), kind="msg", hop=0):
    return {"id": 1, "ch": ch, "from": frm, "to": list(to), "kind": kind, "text": text, "re": None, "hop": hop}


def go(ws):
    return sorted((w["seat"], w["reason"]) for w in ws if w["queue"] is None)


w = r.wakes(msg("dm-ceo--moo", "ceo"), ORG)
check("dm wakes the other seat, counted", w == [{"seat": "moo", "reason": "dm", "queue": None, "count": True}], w)
check("dm never wakes the sender", go(r.wakes(msg("dm-ceo--moo", "moo"), ORG)) == [("ceo", "dm")])
check("@name wakes that seat", go(r.wakes(msg("org", "moo", "ask @disc and @Ceo."), ORG)) == [("ceo", "mention"), ("disc", "mention")])
check("@unknown, an email and a self-mention wake nobody",
      r.wakes(msg("org", "moo", "@nobody bob@disc.org @moo"), ORG) == [])
check("to[] wakes the listed seat", go(r.wakes(msg("harness", "ceo", "done", to=["moo"], kind="answer"), ORG)) == [("moo", "to")])
check("a seat named twice is woken once", len(r.wakes(msg("dm-ceo--moo", "ceo", "@moo @moo", to=["moo"]), ORG)) == 1)
check("owner in a seat's own channel wakes it", go(r.wakes(msg("moo", "owner"), ORG)) == [("moo", "own-channel")])
check("an agent in a seat's own channel wakes nobody", r.wakes(msg("moo", "disc"), ORG) == [])
check("a plain channel message wakes nobody", r.wakes(msg("org", "moo", "status: green"), ORG) == [])
check("a harness ask wakes the ceo", go(r.wakes(msg("harness", "moo", "how do I x", kind="ask"), ORG)) == [("ceo", "ask")])
check("the owner is never a wake target", r.wakes(msg("dm-moo--owner", "moo", "@owner"), ORG) == [])
check("a mention in a direct message wakes nobody outside it",
      go(r.wakes(msg("dm-ceo--moo", "ceo", "@disc x", to=["disc"]), ORG)) == [("moo", "dm")])

# No daily limit (P38): the 13th agent-caused wake of a day goes like the first; the owner is never counted.
seen = [r.wakes(msg("dm-ceo--moo", "ceo"), ORG)[0] for _ in range(13)]
check("13 agent wakes in a day all go, each counted", [(x["queue"], x["count"]) for x in seen] == [(None, True)] * 13, seen)
o = r.wakes(msg("dm-moo--owner", "owner"), ORG)
check("owner's message goes, not counted", o == [{"seat": "moo", "reason": "dm", "queue": None, "count": False}], o)
check("no cap left in the router", not hasattr(r, "CAP"))

# Hop: no limit (T1576); ping-pong between two product owners delivers every turn, the 5th and the 9th included.
hop, frm, trail = 0, "moo", []
for _ in range(9):
    (x,) = r.wakes(msg("dm-disc--moo", frm, hop=hop), ORG)
    trail.append((hop, x["queue"]))
    frm, hop = ("disc" if frm == "moo" else "moo"), r.next_hop(frm, {"from": frm, "hop": hop})
check("ping-pong: 9 turns, none parks", trail == [(h, None) for h in range(9)], trail)
check("no hop limit left in the router", not hasattr(r, "HOP_LIMIT"))
check("owner message ignores hop", r.wakes(msg("moo", "owner", hop=9), ORG)[0]["queue"] is None)
check("next_hop: a reply to the owner starts at 1", r.next_hop("moo", {"from": "owner", "hop": 0}) == 1)
check("next_hop: the owner always 0", r.next_hop("owner", {"from": "moo", "hop": 3}) == 0)
check("next_hop: no parent is 0", r.next_hop("moo", None) == 0)

# Plan >= 95 %: agent wakes queue, the owner's still go.
check("plan 95: agent wake queued", r.wakes(msg("dm-ceo--moo", "ceo"), ORG, plan=95)[0]["queue"] == "plan")
check("plan 94: agent wake goes", r.wakes(msg("dm-ceo--moo", "ceo"), ORG, plan=94)[0]["queue"] is None)
check("plan 99: owner wake goes", r.wakes(msg("moo", "owner"), ORG, plan=99)[0]["queue"] is None)

# Pause: stored, nobody woken, the owner included; pause wins over every other reason.
check("paused: agent wake queued", r.wakes(msg("dm-ceo--moo", "ceo", hop=7), ORG, paused=True, plan=99)[0]["queue"] == "paused")
check("paused: owner wake queued too", r.wakes(msg("moo", "owner"), ORG, paused=True)[0]["queue"] == "paused")

m = msg("dm-ceo--moo", "ceo"); snap = (repr(m), repr(ORG))
r.wakes(m, ORG)
check("pure: inputs unchanged", snap == (repr(m), repr(ORG)))

# P34: a manager posts only in its own direct message with the owner; owners, the ceo and POs keep every channel.
MORG = ORG + [{"id": "mgr", "name": "Mgr", "role": "manager", "parent": "disc", "wake": "po-inbox", "match": "~/agents/po-mgr"},
              {"id": "mg2", "name": "Mg2", "role": "manager", "parent": "disc", "wake": "po-inbox", "match": "~/agents/po-mg2"}]
check("manager: its owner dm is allowed", r.may_post("mgr", "dm-mgr--owner", MORG) == "")
for ch in ("harness", "org", "disc", "dm-mg2--mgr", "dm-disc--mgr", "dm-mg2--owner"):
    why = r.may_post("mgr", ch, MORG)
    check(f"manager: {ch} refused, reason named", why.startswith("a manager posts only in its direct message with the owner"), why)
check("po and ceo keep every channel", [r.may_post(s, ch, MORG) for s in ("moo", "ceo") for ch in ("harness", "org", "dm-mgr--moo")] == [""] * 6)
sys.exit(bad)
PY
[ $? = 0 ] || bad=1
exit $bad
