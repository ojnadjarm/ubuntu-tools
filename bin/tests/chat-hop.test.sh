#!/usr/bin/env bash
# T1515 bin/chat: the hop section (run alone or via chat.test.sh hop); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_hop() {
  # A1: a post's hop is the newest other seat's message hop + 1; the 5th agent-to-agent turn parks; the owner resets.
  local id i
  rm -rf "$ST" "$WORK/systemd-run.log"
  for i in fx gx; do mkdir -p "$HARNESS_HOME/po-$i/inbox"; : >"$HARNESS_HOME/po-$i/BRIEF.md"; done
  hops() { cat "$ST"/$1.*.jsonl | python3 -c "import json, sys; print(' '.join(str(json.loads(l)['hop']) for l in sys.stdin))"; }
  wake() { python3 -c "import json; print(' '.join(r['outcome'] for r in map(json.loads, open('$ST/audit.jsonl')) if r.get('id') == $1 and 'wake' in r))"; }
  for i in 1 2; do CHAT_SEAT=fx chat post @gx "ping $i" >/dev/null; CHAT_SEAT=gx chat post @fx "pong $i" >/dev/null; done
  id=$(CHAT_SEAT=fx chat post @gx 'ping 3')
  is 'hop: fx-gx-fx-gx-fx in one dm: hops 0 1 2 3 4' "$(hops dm-fx--gx)" '0 1 2 3 4'
  is 'hop: the 5th post parks with hop' "$(wake "$id")" hop
  is 'hop: parked as hop for gx' "$(python3 -c "import json; print([json.loads(l)['why'] for l in open('$ST/queue/gx.jsonl')])")" "['hop']"
  CHAT_SEAT=fx chat post @gx 'ping again' >/dev/null
  is 'hop: a second post of the same seat keeps the parent: hop 4 again' "$(hops dm-fx--gx | awk '{print $NF}')" 4
  is 'hop: drain drops hop rows, re-sends nothing' \
     "$(python3 -c "import sys; sys.path.insert(0, '$BIN/../lib'); import chat_dispatch; print(chat_dispatch.drain())") $(grep -c . "$ST/queue/gx.jsonl")" '[] 0'

  CHAT_SEAT=fx chat post org '@gx a' >/dev/null; CHAT_SEAT=gx chat post org '@fx b' >/dev/null
  python3 -c "import sys; sys.path.insert(0, '$BIN/../lib'); import chat_store, chat_dispatch
m = {'ch': 'org', 'from': 'owner', 'to': [], 'text': 'owner word', 'hop': 0}
chat_dispatch.dispatch({**m, 'id': chat_store.post(m), 'kind': 'msg'})" >/dev/null
  id=$(CHAT_SEAT=fx chat post org '@gx c')
  is 'hop: an owner post resets the chain: 0 1 0 1' "$(hops org)" '0 1 0 1'
  ev 'hop: the post after the owner is not parked' '[[ "$(wake "$id")" =~ ^(delivered|queued)$ ]]'
}

t_hop
chat_done
