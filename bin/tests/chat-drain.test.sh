#!/usr/bin/env bash
# T1515 bin/chat: the drain section (run alone or via chat.test.sh drain); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_drain() {
  # A6: the day's first post drains the queue even when po_count made the day file; A9: a bad queue line is skipped.
  local id n a b c out rc P="$HARNESS_HOME/po-fx" day="$ST/counters/$(date +%F)"
  rm -rf "$ST" "$WORK/systemd-run.log"; mkdir -p "$P/inbox"; : >"$P/BRIEF.md"
  last() { python3 -c "import json
print([r['outcome'] for r in map(json.loads, open('$ST/audit.jsonl')) if r.get('id') == $1 and 'wake' in r][-1])"; }
  queued() { cat "$ST/queue/fx.jsonl" 2>/dev/null | wc -l; }
  plan() { echo 1 >"$WORK/plan.rc"; CHAT_SEAT=gx chat post @fx "$1"; rm "$WORK/plan.rc"; }
  newday() { rm -f "$day.json" "$day.drained"; }

  id=$(plan 'parked yesterday'); newday
  python3 "$BIN/../lib/po_count.py" add fx
  CHAT_SEAT=fx chat post harness 'day start' >/dev/null
  is 'drain (A6): po_count first, then a post: the parked wake is re-sent, queue empty' "$(last "$id") $(queued)" 'delivered 0'
  n=$(grep -c "\"id\": $id," "$ST/audit.jsonl"); id=$(plan 'parked today')
  CHAT_SEAT=fx chat post harness 'second post' >/dev/null
  is 'drain (A6): only the first post drains' "$n $(last "$id") $(queued)" '3 plan 1'

  a=$(plan 'good one'); printf '{"id": 1, "ch\n' >>"$ST/queue/fx.jsonl"; b=$(plan 'good two'); newday
  out=$(CHAT_SEAT=fx chat post harness 'day start 2' 2>&1); rc=$?
  is 'drain (A9): a torn queue line: the post exits 0, prints only its id' "$rc $(grep -vc '^[0-9]*$' <<<"$out")" '0 0'
  is 'drain (A9): both good rows re-sent, queue empty' "$(last "$a") $(last "$b") $(queued)" 'queued queued 0'

  chat pause --apply >/dev/null; c=$(CHAT_SEAT=gx chat post @fx 'while paused'); printf 'not json\n' >>"$ST/queue/fx.jsonl"
  out=$(chat resume --apply 2>&1); rc=$?
  is 'drain (A9): resume with a bad line: rc 0, the good row re-sent' "$rc ${out##*$'\n'} $(last "$c") $(queued)" \
     '0 chat: 1 held wake re-sent: fx queued queued 0'

  a=$(plan 'after the crash'); printf '{"id": 5, "ch": "../x", "why": "plan"}\n' >"$ST/queue/fx.jsonl"
  printf '{"id": %s, "ch": "dm-fx--gx", "why": "plan"}\n' "$a" >>"$ST/queue/fx.jsonl"; newday
  out=$(CHAT_SEAT=fx chat post harness 'day start 3' 2>&1); rc=$?
  is 'drain (X6): a row that raises: the post exits 0 with one warning naming dead.jsonl' \
     "$rc $(grep -vc '^[0-9]*$' <<<"$out") $(grep -c '^chat: queue row fx 5 moved to queue/dead.jsonl: ' <<<"$out")" '0 1 1'
  is 'drain (X6): the row is dead-lettered, the next row re-sent, queue empty' \
     "$(python3 -c "import json; print([(r['seat'], r['id']) for r in map(json.loads, open('$ST/queue/dead.jsonl'))])") $(last "$a") $(queued)" \
     "[('fx', 5)] queued 0"
  newday; out=$(CHAT_SEAT=fx chat post harness 'day start 4' 2>&1)
  is 'drain (X6): the next day: dead.jsonl is no seat queue, no warning, kept' \
     "$(grep -vc '^[0-9]*$' <<<"$out") $(wc -l <"$ST/queue/dead.jsonl")" '0 1'
}

t_drain
chat_done
