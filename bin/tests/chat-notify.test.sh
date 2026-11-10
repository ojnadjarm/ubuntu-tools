#!/usr/bin/env bash
# T1515 bin/chat: the notify section (run alone or via chat.test.sh notify); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_notify() {
  # P18: an agent's message to the owner pings notify-owner (the fake), 3 a day per seat; a protected seat's text never.
  local out rc
  rm -rf "$ST"; rm -f "$WORK/notify.log" "$WORK/notify.rc"
  calls() { cat "$WORK/notify.log" 2>/dev/null | wc -l; }
  last() { python3 -c "import json; r = [json.loads(l) for l in open('$ST/audit.jsonl') if '\"alert\"' in l]
print(r[-1]['alert'], r[-1]['outcome'])"; }
  CHAT_SEAT=fx chat post @owner 'build is done' >/dev/null
  is 'notify: dm to the owner pings once, title is the seat' "$(cat "$WORK/notify.log")" '-t|chat: Fixture PO|[fx] to you: build is done|'
  is 'notify: audit says sent' "$(last)" 'fx sent'
  CHAT_SEAT=fx chat post harness 'no ping here, @gx' >/dev/null
  CHAT_SEAT=orchestrator chat post @fx 'not for you' >/dev/null
  CHAT_SEAT=fx chat post harness 'mail owner@example.org' >/dev/null
  is 'notify: messages not to the owner do not ping' "$(calls)" 1
  CHAT_SEAT=fx chat post harness $'look @owner\nsecond line' >/dev/null
  is 'notify: @owner in a channel pings, text on one line' "$(tail -1 "$WORK/notify.log")" \
     '-t|chat: Fixture PO|[fx] #harness: look @owner second line|'
  CHAT_SEAT=fx chat post @owner "$(printf 'y%.0s' $(seq 400))" >/dev/null
  is 'notify: text cut to 200 characters' "$(tail -1 "$WORK/notify.log" | cut -d'|' -f3 | tr -d '\n' | wc -m)" 200
  out=$(CHAT_SEAT=fx chat post @owner 'fourth'); rc=$?
  is 'notify: 4th of the day from fx is stored (rc 0), not pinged' "$rc $(calls)" '0 3'
  is 'notify: audit says cap' "$(last)" 'fx cap'
  CHAT_SEAT=gx chat post @owner 'from gx' >/dev/null
  is 'notify: the cap is per seat' "$(calls) $(last)" '4 gx sent'
  echo 1 >"$WORK/notify.rc"
  CHAT_SEAT=gx chat post @owner 'phone down' >/dev/null; rc=$?
  is 'notify: a failed push keeps the post (rc 0), audit fail' "$rc $(last)" '0 gx fail'
  rm "$WORK/notify.rc"
  CHAT_SEAT=gx chat post @owner 'two' >/dev/null; CHAT_SEAT=gx chat post @owner 'three' >/dev/null
  CHAT_SEAT=gx chat post @owner 'four' >/dev/null
  is 'notify: a failed push is not counted' "$(calls) $(last)" '7 gx cap'
  touch "$ST/PAUSED"
  CHAT_SEAT=orchestrator chat post @owner 'quiet please' >/dev/null
  is 'notify: paused, no ping' "$(calls) $(last)" '7 orchestrator paused'
  rm "$ST/PAUSED"
  is 'notify: an owner message never pings' "$(python3 -c "import sys; sys.path.insert(0, '$BIN/../lib'); import chat_notify
print(chat_notify.alert({'id': 1, 'ch': 'dm-fx--owner', 'from': 'owner', 'to': ['fx'], 'text': '@owner'}))")" None
  sed 's/^]}/,{"id": "hx", "name": "Held PO", "role": "po", "parent": "orchestrator", "wake": "pull", "match": "~\/acme"}\n]}/' \
    "$HARNESS_HOME/org.json" >"$WORK/org-hx.json"
  ORG_FILE="$WORK/org-hx.json" CHAT_SEAT=hx chat post @owner 'the plan' >/dev/null
  is 'notify: a protected seat pings without its text' "$(tail -1 "$WORK/notify.log")" \
     '-t|chat: Held PO|[hx] wrote to you; read it on the Chat screen|'
}

t_notify
chat_done
