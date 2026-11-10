#!/usr/bin/env bash
# T1515-P6: lib/chat_store.py (post, read, channels, mark, audit, flock, monthly files) on a temp HARNESS_HOME;
# 50 parallel posts give 50 valid lines; the real store is never touched.
set -uo pipefail
AG=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
. "$AG/bin/tests/lib/assert.sh"
REAL="$AG/state/chat"
real_before=$(ls -la --time-style=full-iso "$REAL" 2>/dev/null | md5sum)
export HARNESS_HOME="$WORK/h"
ST="$HARNESS_HOME/state/chat"

for i in $(seq 1 50); do
  python3 -c "import sys; sys.path.insert(0, '$AG/lib'); import chat_store as s
s.post({'ch': 'race', 'from': 'fx', 'text': 'n$i'})" &
done
wait
lines=$(cat "$ST"/race.*.jsonl | wc -l)
is "50 parallel posts give 50 lines" "$lines" 50
valid=$(cat "$ST"/race.*.jsonl | python3 -c "
import json, sys
rows = [json.loads(l) for l in sys.stdin]
ids = [r['id'] for r in rows]
ok = ids == sorted(ids) and len(set(ids)) == 50 and sorted(r['text'] for r in rows) == sorted(f'n{i}' for i in range(1, 51))
print(int(ok))")
truthy "50 parallel posts: valid json, unique ids rising in file order, every text once" "$valid"
is "50 parallel posts: 50 audit lines" "$(wc -l <"$ST/audit.jsonl")" 50

python3 - "$AG" "$WORK" <<'PY'
import json, os, sys
ag, work = sys.argv[1:]
sys.path.insert(0, f"{ag}/lib")
import chat_store as s
os.environ["HARNESS_HOME"] = f"{work}/h2"   # fresh store: the race above left last-id at today
bad = 0
def check(name, cond, got=""):
    global bad
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f": {got}"))
    bad |= not cond
def raises(name, fn, word):
    try:
        fn(); check(name, False, "accepted")
    except ValueError as e:
        check(name, word in str(e), str(e))

check("selftest: store root is the temp home", s.root() == f"{work}/h2/state/chat", s.root())

# Monthly files: ids are UTC ms, the file is the id's month.
clock = iter([1793491200000 - 5, 1793491200000 - 5, 1793491200000 + 7])   # 2026-10-31 23:59:59.995, again, 2026-11-01
s._now_ms = lambda: next(clock)
a = s.post({"ch": "harness", "from": "fx", "text": "how do I x", "kind": "ask"})
b = s.post({"ch": "harness", "from": "ceo", "text": "like this", "kind": "answer", "re": a, "hop": 1})
c = s.post({"ch": "harness", "from": "owner", "to": ["fx"], "text": "thanks"})
check("ids rise even when the clock repeats", a < b < c, (a, b, c))
files = sorted(f for f in os.listdir(s.root()) if f.startswith("harness."))
check("one file per channel per month", files == ["harness.2026-10.jsonl", "harness.2026-11.jsonl"], files)
m = s.read("harness")
check("read: all 3 across months, oldest first", [x["id"] for x in m] == [a, b, c], m)
check("read: message keys", set(m[0]) == {"id", "ts", "ch", "from", "to", "kind", "text", "re", "hop"}, sorted(m[0]))
check("read: defaults (to [], kind msg, re None, hop 0)", (m[2]["to"], m[2]["kind"], m[2]["re"], m[2]["hop"]) == (["fx"], "msg", None, 0), m[2])
check("read: answer keeps re and hop", (m[1]["re"], m[1]["hop"]) == (a, 1), m[1])
check("read: ts is UTC ISO of the id", m[0]["ts"] == "2026-10-31T23:59:59.995Z", m[0]["ts"])
check("read after: only newer", [x["id"] for x in s.read("harness", after=a)] == [b, c])
check("read after as a string (HTTP query)", [x["id"] for x in s.read("harness", after=str(b))] == [c])
check("read after the last: []", s.read("harness", after=c) == [])
check("read limit: the newest N", [x["id"] for x in s.read("harness", limit=2)] == [b, c])
check("read after + limit: the first N after", [x["id"] for x in s.read("harness", after=0, limit=1)] == [a])
check("read unknown channel: []", s.read("nothing") == [])

s._now_ms = lambda: 1793491300000
with open(os.path.join(s.root(), "harness.2026-11.jsonl"), "a") as f:
    f.write('{"broken\n')
d = s.post({"ch": "harness", "from": "fx", "text": "after a torn line"})
check("read skips a torn line", [x["id"] for x in s.read("harness", after=c)] == [d])

# Validation: nothing is stored on a bad message.
before = sorted(os.listdir(s.root()))
raises("text over 2000 chars", lambda: s.post({"ch": "org", "from": "fx", "text": "x" * 2001}), "2000")
raises("empty text", lambda: s.post({"ch": "org", "from": "fx", "text": ""}), "text")
raises("channel with a path", lambda: s.post({"ch": "../etc", "from": "fx", "text": "hi"}), "channel")
raises("bad kind", lambda: s.post({"ch": "org", "from": "fx", "text": "hi", "kind": "order"}), "kind")
raises("bad sender", lambda: s.post({"ch": "org", "from": "Fx/..", "text": "hi"}), "from")
raises("bad to", lambda: s.post({"ch": "org", "from": "fx", "text": "hi", "to": "ceo"}), "to")
raises("negative hop", lambda: s.post({"ch": "org", "from": "fx", "text": "hi", "hop": -1}), "hop")
raises("caller-set id", lambda: s.post({"ch": "org", "from": "fx", "text": "hi", "id": 1}), "id")
raises("unknown key", lambda: s.post({"ch": "org", "from": "fx", "text": "hi", "x": 1}), "x")
check("bad messages store nothing", sorted(os.listdir(s.root())) == before, sorted(os.listdir(s.root())))
check("exactly 2000 chars is fine", s.post({"ch": "org", "from": "fx", "text": "y" * 2000}) > 0)

# Audit: one line per post, no text; held lines through audit().
s.audit({"held": "token", "from": "fx", "ch": "org"})
rows = [json.loads(l) for l in open(os.path.join(s.root(), "audit.jsonl"))]
check("audit: no message text", not any("text" in r for r in rows) and "how do I" not in json.dumps(rows))
check("audit: post line has id, ch, from, kind", {"id", "ts", "ch", "from", "kind"} <= set(rows[-2]), rows[-2])
check("audit: held line kept with a ts", rows[-1].get("held") == "token" and "ts" in rows[-1], rows[-1])

# Channels and cursors.
s.post({"ch": s.dm("gx", "fx"), "from": "gx", "text": "psst"})
s.post({"ch": s.dm("ceo", "gx"), "from": "ceo", "text": "private"})
check("dm id is sorted", s.dm("gx", "fx") == "dm-fx--gx" == s.dm("fx", "gx"))
ch = {c["ch"]: c["unread"] for c in s.channels("fx")}
check("channels(fx): own dm, no one else's", "dm-fx--gx" in ch and "dm-ceo--gx" not in ch, ch)
check("channels(fx): unread skips own messages", ch.get("harness") == 2 and ch.get("org") == 0 and ch.get("dm-fx--gx") == 1, ch)
check("channels(owner): sees every dm", {"dm-fx--gx", "dm-ceo--gx"} <= {c["ch"] for c in s.channels("owner")})
s.mark("fx", "harness", c)
check("mark: unread drops", {c["ch"]: c["unread"] for c in s.channels("fx")}["harness"] == 0)
s.mark("fx", "harness", a)
check("mark never moves back", json.load(open(os.path.join(s.root(), "cursors", "fx.json"))) == {"harness": c})
raises("mark: bad seat", lambda: s.mark("../x", "harness", c), "seat")
check("channels: a two-month channel listed once", [x["ch"] for x in s.channels("ceo")].count("harness") == 1)

# Last message per channel (P41): from the newest month file's tail, even when older than every other channel's 50 newest.
os.environ["HARNESS_HOME"] = f"{work}/h3"
real_now = s._now_ms
s._now_ms = lambda: 1700000000000
s.post({"ch": "attic", "from": "gx", "text": "old " + "x" * 200, "files": [{"id": "a", "name": "a.png", "size": 1, "mime": "image/png"}]})
s._now_ms = real_now
for i in range(60):
    s.post({"ch": "busy", "from": "fx", "text": f"b{i}"})
open(os.path.join(s.root(), "busy.2000-01.jsonl"), "w").write('{"id": 1, "ts": "2000-01-01T00:00:00.000Z", "from": "fx", "text": "ancient"}\n')
with open(next(p for p in s._files()["busy"] if "2000-01" not in p), "a") as f:
    f.write("{torn line\n")
last = {c["ch"]: c["last"] for c in s.channels("owner")}
check("channels: last of an old channel", last["attic"] and (last["attic"]["id"], last["attic"]["from"], last["attic"]["ts"][:10], last["attic"]["files"]) ==
      (1700000000000, "gx", "2023-11-14", 1), last.get("attic"))
check("channels: last text clipped to 80 characters", len(last["attic"]["text"]) <= 81 and last["attic"]["text"].startswith("old x"), last["attic"]["text"])
check("channels: last of a busy channel, a torn tail line skipped", last["busy"]["text"] == "b59" and last["busy"]["files"] == 0, last["busy"])
for i in range(10):
    for j in range(2000):
        s._append(os.path.join(s.root(), f"load{i}.2026-11.jsonl"), {"id": j, "ts": "x", "from": "fx", "text": "y" * 200})
import time
t = time.perf_counter()
for c in s.visible("owner"):
    s._last(s._files()[c])
ms = (time.perf_counter() - t) * 1000
print(f"info last of {len(s.visible('owner'))} channels: {ms:.1f} ms")
check("channels: last of 12 channels of 2000 rows under 20 ms", ms < 20, ms)
sys.exit(bad)
PY
[ $? = 0 ] || bad=1

# T1545-C: search(seat, q, ch, limit) over the seat's visible channels, every word, any case, newest `limit` oldest first.
python3 - "$AG" "$WORK" <<'PY'
import os, sys, time
ag, work = sys.argv[1:]
sys.path.insert(0, f"{ag}/lib")
import chat_store as s
os.environ["HARNESS_HOME"] = f"{work}/h4"
bad = 0
def check(name, cond, got=""):
    global bad
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f": {got}"))
    bad |= not cond
def raises(name, fn, word):
    try:
        fn(); check(name, False, "accepted")
    except ValueError as e:
        check(name, word in str(e), str(e))
ids = lambda rows: [r["id"] for r in rows]

clock = iter([1793491200000 - 9, 1793491200000 + 3])   # 2026-10-31, then 2026-11-01
s._now_ms = lambda: next(clock)
a = s.post({"ch": "harness", "from": "fx", "text": "Build is GREEN on main"})
b = s.post({"ch": "org", "from": "gx", "text": "main build green again\nsecond line"})
s._now_ms = lambda: 1793491300000
c = s.post({"ch": "harness", "from": "ceo", "kind": "system", "text": "build paused: green light later"})
d = s.post({"ch": s.dm("ceo", "gx"), "from": "ceo", "text": "green build, private"})
e = s.post({"ch": s.dm("fx", "gx"), "from": "gx", "text": "the BUILD is green"})
with open(os.path.join(s.root(), "harness.2026-11.jsonl"), "a") as f:
    f.write('{"torn green build\n')
f2 = s.post({"ch": "harness", "from": "fx", "text": "red build"})

check("search: words in any order, any case, across two months, oldest first", ids(s.search("fx", "green BUILD")) == [a, b, c, e],
      ids(s.search("fx", "green BUILD")))
check("search: every word must match", ids(s.search("fx", "green red")) == [] and ids(s.search("fx", "red build")) == [f2])
check("search: rows carry ch and keep their keys", [r["ch"] for r in s.search("fx", "main")] == ["harness", "org"]
      and s.search("fx", "main")[1]["text"].endswith("second line"))
check("search: a system line is included", s.search("fx", "paused light")[0]["kind"] == "system")
check("search: another pair's direct message hidden from a third seat", d not in ids(s.search("fx", "green build")))
check("search: the pair and the owner see it", d in ids(s.search("gx", "private")) and d in ids(s.search("owner", "private")))
check("search: one channel", ids(s.search("fx", "green build", ch="harness")) == [a, c])
check("search: a channel the seat cannot see gives nothing", s.search("fx", "private", ch=s.dm("ceo", "gx")) == [])
check("search: an unknown channel gives nothing", s.search("fx", "green", ch="nothing") == [])
check("search: a torn line skipped", "torn" not in str(s.search("owner", "green build")))
check("search: surrounding spaces stripped", ids(s.search("fx", "  red  ")) == [f2])
for q in ("", " ", "x", " x ", None, 5):
    raises(f"search: q {q!r} refused", lambda: s.search("fx", q), "q")
raises("search: a bad channel name refused", lambda: s.search("fx", "green", ch="../x"), "channel")

os.environ["HARNESS_HOME"] = f"{work}/h5"
s._now_ms = lambda: 1793491200000 - 86400000
old = [s.post({"ch": "harness", "from": "fx", "text": f"hit old {i}"}) for i in range(5)]
s._now_ms = lambda: 1793491300000
new = [s.post({"ch": ("harness", "org")[i % 2], "from": "fx", "text": f"hit new {i}"}) for i in range(40)]
check("search limit: the newest 30, oldest first", ids(s.search("fx", "hit")) == new[-30:])
check("search limit 5", ids(s.search("fx", "hit", limit=5)) == new[-5:])
check("search: not full in the newest month reads the older one", ids(s.search("fx", "hit", limit=44)) == old[-4:] + new)
opened, real_rows = [], s._rows
s._rows = lambda p: (opened.append(os.path.basename(p)), real_rows(p))[1]
s.search("fx", "hit")
s._rows = real_rows
check("search: full from the newest month, the older month is never opened", not any("2026-10" in p for p in opened), opened)

os.environ["HARNESS_HOME"] = f"{work}/h6"
for i in range(500):
    s._now_ms = lambda: 1793491300000 - (0 if i >= 250 else 86400000 * 3)
    s.post({"ch": f"c{i % 5}", "from": "fx", "text": f"message {i} about the dashboard " + "x" * 300})
t = time.perf_counter()
got = s.search("owner", "DASHBOARD 499")
ms = (time.perf_counter() - t) * 1000
print(f"info search of 500 messages: {ms:.1f} ms")
check("search: 500 messages, one hit", ids(got) and got[0]["text"].startswith("message 499 "), got)
check("search: 500 messages under 20 ms", ms < 20, ms)
os.environ["HARNESS_HOME"] = f"{work}/h7"
month = {}
for m, t in (("09", 1788220800000), ("10", 1790812800000), ("11", 1793491200000)):   # 2026-09-01 .. 2026-11-01 UTC
    for i in range(2):
        s._now_ms = lambda: t + i * 1000
        month[m, "a", i] = s.post({"ch": "ca", "from": "gx", "text": f"{m} {i}"})
        month[m, "b", i] = s.post({"ch": "cb", "from": "gx", "text": f"{m} {i}"})
def unread_and_opened(seat):
    opened, real_rows = [], s._rows
    s._rows = lambda p: (opened.append(os.path.basename(p)), real_rows(p))[1]
    try:
        return {c["ch"]: c["unread"] for c in s.channels(seat)}, sorted(opened)
    finally:
        s._rows = real_rows
got, opened = unread_and_opened("fx")
check("channels: no cursor, every month counted", got == {"ca": 6, "cb": 6}, got)
s.mark("fx", "ca", month["11", "a", 0]); s.mark("fx", "cb", month["11", "b", 0])
got, opened = unread_and_opened("fx")
check("channels: cursor in the newest month, unread counts its newer rows", got == {"ca": 1, "cb": 1}, got)
check("channels: cursor in the newest month opens 1 file per channel", opened == ["ca.2026-11.jsonl", "cb.2026-11.jsonl"], opened)
s.mark("gy", "ca", month["10", "a", 0]); s.mark("gy", "cb", month["11", "b", 0])
got, opened = unread_and_opened("gy")
check("channels: cursor a month back counts that month and the newer one", got == {"ca": 3, "cb": 1}, got)
check("channels: cursor a month back skips the older month", "ca.2026-09.jsonl" not in opened, opened)
sys.exit(bad)
PY
[ $? = 0 ] || bad=1

is "real store untouched" "$(ls -la --time-style=full-iso "$REAL" 2>/dev/null | md5sum)" "$real_before"
exit $bad
