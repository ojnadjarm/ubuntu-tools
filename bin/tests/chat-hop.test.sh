#!/usr/bin/env bash
# T1515 bin/chat: the hop section (run alone or via chat.test.sh hop); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_hop() {
  # A1: a post's hop is the newest other seat's message hop + 1; no hop limit (T1576): every turn is delivered; the owner resets.
  local id5 id9 i
  rm -rf "$ST" "$WORK/systemd-run.log"
  for i in fx gx; do mkdir -p "$HARNESS_HOME/po-$i/inbox"; : >"$HARNESS_HOME/po-$i/BRIEF.md"; done
  hops() { cat "$ST"/$1.*.jsonl | python3 -c "import json, sys; print(' '.join(str(json.loads(l)['hop']) for l in sys.stdin))"; }
  wake() { python3 -c "import json; print(' '.join(r['outcome'] for r in map(json.loads, open('$ST/audit.jsonl')) if r.get('id') == $1 and 'wake' in r))"; }
  for i in 1 2; do CHAT_SEAT=fx chat post @gx "ping $i" >/dev/null; CHAT_SEAT=gx chat post @fx "pong $i" >/dev/null; done
  id5=$(CHAT_SEAT=fx chat post @gx 'ping 3')
  for i in 4 5; do CHAT_SEAT=gx chat post @fx "pong $((i - 1))" >/dev/null; [[ $i == 5 ]] || CHAT_SEAT=fx chat post @gx "ping $i" >/dev/null; done
  id9=$(CHAT_SEAT=fx chat post @gx 'ping 5')
  is 'hop: nine fx-gx turns in one dm: hops 0..8' "$(hops dm-fx--gx)" '0 1 2 3 4 5 6 7 8'
  ev 'hop: the 5th turn is delivered' '[[ "$(wake "$id5")" =~ ^(delivered|queued)$ ]]'
  ev 'hop: the 9th turn is delivered' '[[ "$(wake "$id9")" =~ ^(delivered|queued)$ ]]'
  ev 'hop: nothing parks as hop' '! grep -qs "\"hop\"" "$ST"/queue/*.jsonl'
  mkdir -p "$ST/queue"; echo "{\"id\": $id5, \"ch\": \"dm-fx--gx\", \"why\": \"hop\"}" >>"$ST/queue/gx.jsonl"
  is 'hop: drain re-sends an old hop park, queue empty' \
     "$(python3 -c "import sys; sys.path.insert(0, '$BIN/../lib'); import chat_dispatch; print([s for s, _ in chat_dispatch.drain()])") $(grep -c . "$ST/queue/gx.jsonl")" "['gx'] 0"

  CHAT_SEAT=fx chat post org '@gx a' >/dev/null; CHAT_SEAT=gx chat post org '@fx b' >/dev/null
  python3 -c "import sys; sys.path.insert(0, '$BIN/../lib'); import chat_store, chat_dispatch
m = {'ch': 'org', 'from': 'owner', 'to': [], 'text': 'owner word', 'hop': 0}
chat_dispatch.dispatch({**m, 'id': chat_store.post(m), 'kind': 'msg'})" >/dev/null
  id5=$(CHAT_SEAT=fx chat post org '@gx c')
  is 'hop: an owner post resets the chain: 0 1 0 1' "$(hops org)" '0 1 0 1'
  ev 'hop: the post after the owner is delivered' '[[ "$(wake "$id5")" =~ ^(delivered|queued)$ ]]'
}

t_hop
chat_done
