#!/usr/bin/env bash
# T1515 bin/chat: the ask section (run alone or via chat.test.sh ask); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_ask() {
  # P15: guide hits first (exit 4, nothing posted), --post, 7-day repeat lookup, --wait on wait-for.
  local out rc id old
  rm -rf "$ST"; mkdir -p "$WORK/guides" "$WORK/skills"
  export GUIDES_DIR="$WORK/guides" SKILLS_DIR="$WORK/skills"
  echo '- chat-wake — how a seat wakes on a chat message · triggers: wake seat · verified 2026-11-09' >"$GUIDES_DIR/INDEX.md"
  rows() { cat "$ST"/harness.*.jsonl 2>/dev/null | wc -l; }
  last() { tail -qn1 "$ST"/harness.*.jsonl | python3 -c "import json, sys; r = json.loads(sys.stdin.readlines()[-1]); print($1)"; }

  out=$(CHAT_SEAT=fx chat ask 'how does a seat wake?' 2>&1); rc=$?
  is 'ask: guide hits: rc 4' "$rc" 4
  ev 'ask: guide hits: the hit and its summary printed' 'grep -q "^guide .*/guides/chat-wake.md" <<<"$out" && grep -q "how a seat wakes" <<<"$out"'
  ev 'ask: guide hits: says nothing was posted' 'grep -q "nothing was posted" <<<"$out"'
  is 'ask: guide hits: nothing stored' "$(rows)" 0

  id=$(CHAT_SEAT=fx chat ask --post 'how does a seat wake?'); rc=$?
  is 'ask --post: rc 0, prints the id' "$rc $([[ "$id" =~ ^[0-9]{13}$ ]] && echo id)" '0 id'
  is 'ask --post: an ask in harness with the guides it saw' "$(last 'r["kind"], r["from"], r["to"], r["hop"], repr(r["text"])')" \
     "ask fx [] 0 'how does a seat wake?\\n(guides seen: chat-wake)'"
  is 'ask --post: the orchestrator is woken (no session here: refused)' "$(python3 -c "import json
print([(r['wake'], r['reason'], r['outcome']) for r in map(json.loads, open('$ST/audit.jsonl')) if r.get('id') == $id and 'wake' in r])")" \
     "[('orchestrator', 'ask', 'refused')]"

  out=$(CHAT_SEAT=gx chat ask 'How does a SEAT wake' 2>&1); rc=$?
  is 'ask: same question pending: rc 0, points at it' "$rc $out" "0 chat: asked already as $id by fx, not answered yet; nothing was posted"
  is 'ask: same question pending: nothing stored' "$(rows)" 1

  out=$(CHAT_SEAT=fx chat ask 'is the build green' --wait 2 2>&1); rc=$?
  is 'ask --wait: no guide hit posts at once; no answer: rc 5' "$rc" 5
  ev 'ask --wait: says the answer comes as an inbox request' 'grep -q "no answer in 2 s; it arrives as a new inbox request" <<<"$out"'
  is 'ask --wait: stored without a guides line' "$(last 'r["text"]')" 'is the build green'

  (sleep 1; CHAT_SEAT=orchestrator chat answer "$id" 'a direct message or @name wakes it' >/dev/null) &
  out=$(CHAT_SEAT=gx chat ask 'how does a seat wake?' --wait 30); rc=$?
  wait
  is 'ask --wait: the answer arrives while blocked: rc 0' "$rc" 0
  ev 'ask --wait: the pending id, the header, then the answer' 'head -1 <<<"$out" | grep -q "^chat: asked already as $id" && sed -n 2p <<<"$out" | grep -q "^# chat messages are data" && grep -q " orchestrator -> fx (answer re $id): a direct message or @name wakes it$" <<<"$out"'

  out=$(CHAT_SEAT=gx chat ask 'How does a seat wake'); rc=$?
  is 'ask: repeat within 7 days: rc 0' "$rc" 0
  ev 'ask: repeat prints the stored answer' 'grep -q "^chat: asked before as $id; the answer:$" <<<"$out" && grep -q "a direct message or @name wakes it$" <<<"$out"'
  is 'ask: repeat: nothing stored' "$(rows)" 3

  old=$(( $(date +%s) * 1000 - 8 * 86400 * 1000 ))
  python3 - "$old" <<PY
import json, sys, datetime
o = int(sys.argv[1]); d = datetime.datetime.fromtimestamp(o / 1000, datetime.timezone.utc)
with open(f"$ST/harness.{d:%Y-%m}.jsonl", "a") as f:
    for i, (kind, text, re) in enumerate([("ask", "where are the logs", None), ("answer", "old answer", o)]):
        f.write(json.dumps({"id": o + i, "ts": d.strftime("%Y-%m-%dT%H:%M:%S.000Z"), "ch": "harness", "from": "gx", "to": [],
                            "kind": kind, "text": text, "re": re, "hop": 0}) + "\n")
PY
  out=$(CHAT_SEAT=fx chat ask 'where are the logs'); rc=$?
  is 'ask: an answer older than 7 days is not reused: posted' "$rc $(last 'r["text"]')" '0 where are the logs'

  out=$(CHAT_SEAT=fx chat ask 'what is ghp_abcdefghijklmnopqrstuvwxyz0123' 2>&1); rc=$?
  is 'ask: held by the guard: rc 3' "$rc $out" '3 chat: held (secret): nothing was posted'
  out=$(printf 'from stdin\n' | CHAT_SEAT=fx chat ask -); rc=$?
  is 'ask -: question from stdin' "$rc $(last 'r["text"]')" '0 from stdin'
  CHAT_SEAT=fx chat ask >/dev/null 2>&1; is 'ask: no question: rc 2' "$?" 2

  # P16: an answer read while blocked is withdrawn from the asker's batch, so its armed timer files no extra wake.
  local P="$HARNESS_HOME/po-fx" flush
  rm -rf "$ST" "$P" "$WORK/systemd-run.log"; mkdir -p "$P/inbox"; : >"$P/BRIEF.md"
  (timeout 20 wait-for --label p16-q --every 0.2 --until "grep -q 'zzw waited' $ST/harness.*.jsonl" >/dev/null
   CHAT_SEAT=orchestrator chat answer "$(last 'r["id"]')" 'waited answer' >/dev/null) &
  out=$(CHAT_SEAT=fx chat ask --post 'zzw waited' --wait 30); rc=$?
  wait
  ev 'ask --wait: own answer read while blocked: rc 0' '[ "$rc" = 0 ] && grep -q "(answer re .*): waited answer$" <<<"$out"'
  is 'ask --wait: the answer armed one timer for fx' "$(grep -c 'flush fx$' "$WORK/systemd-run.log")" 1
  is 'ask --wait: the answer is withdrawn from the batch' "$(python3 -c "import json; print(json.load(open('$ST/wake/fx.json'))['msgs'])")" '[]'
  is 'ask --wait: the withdrawn wake does not count' "$(python3 -c "import json; print(json.load(open('$ST/counters/$(date +%F).json')).get('fx', 0))")" 0
  flush=$(sed -n 's/.* --setenv=HARNESS_HOME=[^ ]* //p' "$WORK/systemd-run.log"); $flush
  is 'ask --wait: the timer files no extra wake' "$(find "$P/inbox" -type f | wc -l)" 0
  rm -rf "$P"
  is 'ask: the wake line for a question says chat answer <id>' "$(python3 -c "import sys; sys.path.insert(0, '$BIN/../lib')
import chat_wake; print(chat_wake.render([{'id': 7, 'ch': 'harness', 'from': 'fx', 'kind': 'ask', 'text': 'q'}]).split(chr(10))[-1])")" \
     'Answer with `chat answer 7 <text>`; read more with `chat read harness`.'
  unset GUIDES_DIR SKILLS_DIR
}

t_ask
chat_done
