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

is "real store untouched" "$(ls -la --time-style=full-iso "$REAL" 2>/dev/null | md5sum)" "$real_before"
exit $bad
