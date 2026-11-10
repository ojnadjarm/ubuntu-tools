#!/usr/bin/env bash
# T1515 bin/chat: the answer section (run alone or via chat.test.sh answer); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_answer() {
  # P15: answer <id>: an answer row (re, to the asker, hop + 1) that wakes the asker; only questions in #harness.
  local q m out rc a
  rm -rf "$ST"
  q=$(CHAT_SEAT=fx chat ask --post 'zzq unmatched question')
  m=$(CHAT_SEAT=fx chat post harness 'just a message')
  a=$(CHAT_SEAT=orchestrator chat answer "$q" 'the answer'); rc=$?
  is 'answer: rc 0, prints the id' "$rc $([[ "$a" =~ ^[0-9]{13}$ ]] && echo id)" '0 id'
  is 'answer: stored as an answer to the asker, hop 1' "$(python3 -c "
import json, glob; r = [json.loads(l) for f in glob.glob('$ST/harness.*.jsonl') for l in open(f)][-1]
print(r['id'], r['from'], r['to'], r['kind'], r['re'], r['hop'], r['text'])")" "$a orchestrator ['fx'] answer $q 1 the answer"
  is 'answer: the asker is woken (no PO folder here: refused)' "$(python3 -c "import json
print([(r['wake'], r['reason']) for r in map(json.loads, open('$ST/audit.jsonl')) if r.get('id') == $a and 'wake' in r])")" \
     "[('fx', 'to')]"
  out=$(printf 'own\nanswer\n' | CHAT_SEAT=fx chat answer "$q" -); rc=$?
  is 'answer -: own question from stdin: rc 0' "$rc" 0
  is 'answer: own question addresses nobody' "$(python3 -c "
import json, glob; r = [json.loads(l) for f in glob.glob('$ST/harness.*.jsonl') for l in open(f)][-1]
print(r['to'], repr(r['text']))")" "[] 'own\\nanswer'"
  CHAT_SEAT=orchestrator chat answer "$m" 'x' >/dev/null 2>&1; is 'answer: a plain message is not a question (rc 2)' "$?" 2
  CHAT_SEAT=orchestrator chat answer 1 'x' >/dev/null 2>&1; is 'answer: unknown id (rc 2)' "$?" 2
  CHAT_SEAT=orchestrator chat answer abc 'x' >/dev/null 2>&1; is 'answer: id not a number (rc 2)' "$?" 2
  out=$(CHAT_SEAT=orchestrator chat answer "$q" 'see ~/acme/x' 2>&1); rc=$?
  is 'answer: held by the guard: rc 3' "$rc $out" '3 chat: held (protected path): nothing was posted'
  CHAT_SEAT=owner chat answer "$q" 'x' >/dev/null 2>&1; is 'answer: CHAT_SEAT=owner refused (rc 2)' "$?" 2
  is 'answer: 4 rows in harness' "$(cat "$ST"/harness.*.jsonl | wc -l)" 4
}

t_answer
chat_done
