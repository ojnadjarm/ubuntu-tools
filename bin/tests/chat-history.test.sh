#!/usr/bin/env bash
# T1515 bin/chat: the history section (run alone or via chat.test.sh history); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_history() {
  # P33: a channel opens on its newest 50 and pages older ones with `before`, across month files; `recent` merges every
  # channel the seat sees, newest last.
  rm -rf "$ST"
  cat >"$WORK/history.py" <<'PY'
import sys; sys.path.insert(0, sys.argv[1])
import chat_store as s
t0 = 1793491200000 - 60 * 1000           # 2026-10-31 23:59 UTC: 60 rows in October, 60 in November
clock = iter(range(t0, t0 + 10 ** 9, 1000))
s._now_ms = lambda: next(clock)
ids = [s.post({"ch": "harness", "from": "fx", "text": f"h{i}"}) for i in range(120)]
other = [s.post({"ch": ch, "from": "gx", "text": ch}) for ch in ("org", "dm-gx--orchestrator", "dm-fx--owner")]
out = []
page = s.read("harness", limit=50)
out.append([m["id"] for m in page] == ids[-50:])
older = s.read("harness", before=page[0]["id"], limit=50)
out.append([m["id"] for m in older] == ids[20:70])
last = s.read("harness", before=older[0]["id"], limit=50)
out.append([m["id"] for m in last] == ids[:20] and s.read("harness", before=ids[0], limit=50) == [])
out.append(sorted({m["ts"][:7] for m in older}) == ["2026-10", "2026-11"])
rec = s.recent("owner", limit=50)
out.append([m["id"] for m in rec] == (ids + other)[-50:] and rec[-1]["ch"] == "dm-fx--owner")
out.append([m["id"] for m in s.recent("owner", before=rec[0]["id"], limit=5)] == ids[-52:-47])
out.append([m["id"] for m in s.recent("owner", after=ids[-1])] == other)
out.append([m["ch"] for m in s.recent("fx", after=ids[-1])] == ["org", "dm-fx--owner"])
print(" ".join("ok" if x else "FAIL" for x in out))
PY
  is 'history: newest 50, older pages across months, recent across channels' "$(python3 "$WORK/history.py" "$BIN/../lib")" \
     'ok ok ok ok ok ok ok ok'
}

t_history
chat_done
