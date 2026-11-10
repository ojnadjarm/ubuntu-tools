#!/usr/bin/env bash
# T1515 bin/chat: the manager section (run alone or via chat.test.sh manager); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_manager() {
  # P34: a manager answers the owner in its own direct message with him and posts nowhere else (rc 2, nothing stored);
  # the wake note names the command that is allowed.
  local out rc n0 note
  rm -rf "$ST"
  sed 's/^]}/,{"id": "mx", "name": "Mgr", "role": "manager", "parent": "fx", "wake": "po-inbox", "match": "~\/mx"},\n{"id": "my", "name": "Mgr 2", "role": "manager", "parent": "fx", "wake": "po-inbox", "match": "~\/my"}\n]}/' \
    "$HARNESS_HOME/org.json" >"$WORK/org-mgr.json"
  export ORG_FILE="$WORK/org-mgr.json"
  msgs() { cat "$ST"/*.20*.jsonl 2>/dev/null | wc -l; }
  out=$(CHAT_SEAT=mx chat post @owner 'two PRs open, one green'); rc=$?
  is 'manager: reply in its owner dm: rc 0, an id' "$rc $([[ "$out" =~ ^[0-9]{13}$ ]] && echo id)" '0 id'
  is 'manager: stored in dm-mx--owner, to the owner' "$(python3 -c "
import json, glob; r = json.loads(open(glob.glob('$ST/dm-mx--owner.*.jsonl')[0]).readline()); print(r['from'], r['to'], r['text'])")" \
     "mx ['owner'] two PRs open, one green"
  n0=$(msgs)
  for where in harness org fx @gx @my @orchestrator @fx; do
    out=$(CHAT_SEAT=mx chat post "$where" 'status' 2>&1); rc=$?
    is "manager: post $where refused: rc 2, nothing stored" "$rc $(msgs)" "2 $n0"
  done
  ev 'manager: the refusal names the rule' 'grep -q "a manager posts only in its direct message with the owner" <<<"$out"'
  CHAT_SEAT=mx chat ask --post 'how do I x' >/dev/null 2>&1; rc=$?
  is 'manager: ask refused: rc 2, nothing stored' "$rc $(msgs)" "2 $n0"
  id=$(CHAT_SEAT=fx chat ask --post 'q for all' 2>/dev/null); n0=$(msgs)
  CHAT_SEAT=mx chat answer "$id" 'an answer' >/dev/null 2>&1; rc=$?
  is 'manager: answer refused: rc 2, nothing stored' "$rc $(msgs)" "2 $n0"
  out=$(CHAT_SEAT=fx chat post @mx 'po to its manager'); rc=$?
  is 'manager: its po still posts to it: rc 0' "$rc" 0
  note() { python3 -c "import sys; sys.path.insert(0, '$BIN/../lib')
import chat_wake; print(chat_wake.render([{'id': 7, 'ch': sys.argv[1], 'from': sys.argv[2], 'text': 'q'}], sys.argv[3]).split(chr(10))[-1])" "$@"; }
  is 'manager: the owner-dm wake note says chat post @owner' "$(note dm-mx--owner owner mx)" \
     'Answer with `chat post @owner <text>`; read more with `chat read dm-mx--owner`.'
  is 'manager: a note elsewhere says it may not post there' "$(note harness orchestrator mx)" \
     'You may not post in #harness: put what matters in REPORT.md; read more with `chat read harness`.'
  is 'po: a dm wake note says chat post @<sender>' "$(note dm-fx--gx gx fx)" \
     'Answer with `chat post @gx <text>`; read more with `chat read dm-fx--gx`.'
  unset ORG_FILE
}

t_po_run() {
  # A8: a process under `po-run <p>` takes seat <p> only; any other CHAT_SEAT is exit 2, nothing stored, one audit line.
  local out rc n0
  rm -rf "$ST"
  printf '#!/bin/bash\nshift\n"$@"\nexit $?\n' >"$WORK/stubs/po-run"; chmod +x "$WORK/stubs/po-run"
  msgs() { cat "$ST"/*.20*.jsonl 2>/dev/null | wc -l; }
  n0=$(msgs)
  out=$(CHAT_SEAT=gx po-run mg python3 "$BIN/chat" post harness x 2>&1); rc=$?
  is 'po-run: under po-run mg, CHAT_SEAT=gx post refused: rc 2, nothing stored' "$rc $(msgs)" "2 $n0"
  ev 'po-run: the refusal names the rule' 'grep -q "under \`po-run mg\` the seat is mg, not gx" <<<"$out"'
  is 'po-run: the refusal is audited' "$(grep -c '"po_run": "mg"' "$ST/audit.jsonl" 2>/dev/null)" 1
  CHAT_SEAT=orchestrator po-run mg python3 "$BIN/chat" read --unread >/dev/null 2>&1
  is 'po-run: read as another seat refused too (rc 2)' "$?" 2
  out=$(CHAT_SEAT=fx po-run fx python3 "$BIN/chat" post harness 'own seat'); rc=$?
  is 'po-run: under po-run fx, CHAT_SEAT=fx posts: rc 0' "$rc" 0
  mkdir -p "$HOME/gx"
  (cd "$HOME/gx" && po-run fx python3 "$BIN/chat" post harness y >/dev/null 2>&1); rc=$?
  is 'po-run: no CHAT_SEAT, a cwd seat other than fx refused (rc 2)' "$rc" 2
  rm -f "$WORK/stubs/po-run"
}

t_manager
t_po_run
chat_done
