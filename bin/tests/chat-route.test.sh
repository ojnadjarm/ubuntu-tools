#!/usr/bin/env bash
# T1515-P11: lib/chat_route.wakes (pure): direct messages, @names, the owner in a seat's own channel, harness asks;
# cap 12 per seat per day, hop 4, pause, plan >= 95 %. Fixture org only; the module does no I/O.
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


w = r.wakes(msg("dm-ceo--moo", "ceo"), ORG, {})
check("dm wakes the other seat, counted", w == [{"seat": "moo", "reason": "dm", "queue": None, "count": True}], w)
check("dm never wakes the sender", go(r.wakes(msg("dm-ceo--moo", "moo"), ORG, {})) == [("ceo", "dm")])
check("@name wakes that seat", go(r.wakes(msg("org", "moo", "ask @disc and @Ceo."), ORG, {})) == [("ceo", "mention"), ("disc", "mention")])
check("@unknown, an email and a self-mention wake nobody",
      r.wakes(msg("org", "moo", "@nobody bob@disc.org @moo"), ORG, {}) == [])
check("to[] wakes the listed seat", go(r.wakes(msg("harness", "ceo", "done", to=["moo"], kind="answer"), ORG, {})) == [("moo", "to")])
check("a seat named twice is woken once", len(r.wakes(msg("dm-ceo--moo", "ceo", "@moo @moo", to=["moo"]), ORG, {})) == 1)
check("owner in a seat's own channel wakes it", go(r.wakes(msg("moo", "owner"), ORG, {})) == [("moo", "own-channel")])
check("an agent in a seat's own channel wakes nobody", r.wakes(msg("moo", "disc"), ORG, {}) == [])
check("a plain channel message wakes nobody", r.wakes(msg("org", "moo", "status: green"), ORG, {}) == [])
check("a harness ask wakes the ceo", go(r.wakes(msg("harness", "moo", "how do I x", kind="ask"), ORG, {})) == [("ceo", "ask")])
check("the owner is never a wake target", r.wakes(msg("dm-moo--owner", "moo", "@owner"), ORG, {}) == [])

# Cap: 12 agent-caused wakes per seat per day; the 13th is queued; the owner is never counted.
counters, seen = {}, []
for i in range(13):
    (x,) = r.wakes(msg("dm-ceo--moo", "ceo"), ORG, counters)
    seen.append(x["queue"])
    if x["count"]:
        counters[x["seat"]] = counters.get(x["seat"], 0) + 1
check("12 wakes go, the 13th is queued (cap)", seen == [None] * 12 + ["cap"], seen)
check("counters hold 12", counters == {"moo": 12}, counters)
check("cap is per seat", go(r.wakes(msg("dm-ceo--disc", "ceo"), ORG, counters)) == [("disc", "dm")])
o = r.wakes(msg("dm-moo--owner", "owner"), ORG, counters)
check("owner's message past the cap goes, not counted", o == [{"seat": "moo", "reason": "dm", "queue": None, "count": False}], o)
check("cap from the caller", r.wakes(msg("dm-ceo--moo", "ceo"), ORG, {"moo": 3}, cap=3)[0]["queue"] == "cap")

# Hop: ping-pong between two product owners parks at hop 4; the owner's message resets it.
hop, frm, trail = 0, "moo", []
for _ in range(8):
    (x,) = r.wakes(msg("dm-disc--moo", frm, hop=hop), ORG, {})
    trail.append((hop, x["queue"]))
    if x["queue"]:
        break
    frm, hop = ("disc" if frm == "moo" else "moo"), r.next_hop(frm, {"from": frm, "hop": hop})
check("ping-pong stops at hop 4", trail == [(0, None), (1, None), (2, None), (3, None), (4, "hop")], trail)
check("owner message ignores hop", r.wakes(msg("moo", "owner", hop=9), ORG, {})[0]["queue"] is None)
check("next_hop: a reply to the owner starts at 1", r.next_hop("moo", {"from": "owner", "hop": 0}) == 1)
check("next_hop: the owner always 0", r.next_hop("owner", {"from": "moo", "hop": 3}) == 0)
check("next_hop: no parent is 0", r.next_hop("moo", None) == 0)

# Plan >= 95 %: agent wakes queue, the owner's still go.
check("plan 95: agent wake queued", r.wakes(msg("dm-ceo--moo", "ceo"), ORG, {}, plan=95)[0]["queue"] == "plan")
check("plan 94: agent wake goes", r.wakes(msg("dm-ceo--moo", "ceo"), ORG, {}, plan=94)[0]["queue"] is None)
check("plan 99: owner wake goes", r.wakes(msg("moo", "owner"), ORG, {}, plan=99)[0]["queue"] is None)

# Pause: stored, nobody woken, the owner included; pause wins over every other reason.
check("paused: agent wake queued", r.wakes(msg("dm-ceo--moo", "ceo", hop=7), ORG, {"moo": 99}, paused=True, plan=99)[0]["queue"] == "paused")
check("paused: owner wake queued too", r.wakes(msg("moo", "owner"), ORG, {}, paused=True)[0]["queue"] == "paused")

ws = r.wakes(msg("org", "ceo", "@moo @disc"), ORG, {"moo": 12})
check("one message, mixed: per-seat verdict", sorted((x["seat"], x["queue"]) for x in ws) == [("disc", None), ("moo", "cap")], ws)
m = msg("dm-ceo--moo", "ceo"); c = {"moo": 1}; snap = (repr(m), repr(ORG), repr(c))
r.wakes(m, ORG, c)
check("pure: inputs unchanged", snap == (repr(m), repr(ORG), repr(c)))
sys.exit(bad)
PY
[ $? = 0 ] || bad=1
exit $bad
