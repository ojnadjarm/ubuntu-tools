#!/usr/bin/env bash
# T1515 bin/chat: the wake-ceo section (run alone or via chat.test.sh wake-ceo); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_wake-ceo() {
  # P14: Channel adapter on a fixture registry and a fake session socket; the live orchestrator is never a target.
  local REG="$HOME/.claude/sessions" SOCK="$WORK/orch.sock" GOT="$WORK/got" lpid spid out
  export ORCHESTRATOR_TMUX_SESSION=orch-fx; unset CLAUDE_SESSIONS_DIR
  mkdir -p "$REG" "$GOT"
  python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(8); n = 0
while True:
    c, _ = s.accept(); n += 1; data = b""
    while (b := c.recv(65536)):
        data += b
    open(f"{sys.argv[2]}/{n}", "wb").write(data)
' "$SOCK" "$GOT" & lpid=$!
  sleep 30 & spid=$!
  wait-for --label p14-sock --every 0.2 --job "$lpid" --until "test -S '$SOCK'" >/dev/null || nok "wake-ceo: fake socket" "listener died"
  pstart() { cut -d')' -f2 "/proc/$1/stat" | awk '{print $20}'; }
  reg() {   # reg <pid> <procStart> <cwd> <tmux> <sock>
    printf '{"pid": %s, "procStart": "%s", "cwd": "%s", "tmux": "%s", "messagingSocketPath": "%s", "status": "idle"}' \
      "$1" "$2" "$3" "$4" "$5" >"$REG/$1.json"
  }
  key() { printf '{"peerToken": "%s", "procStart": "%s"}' "$3" "$2" >"$REG/$1.abc.key"; }
  wake() {   # wake <from> <text>: route a harness post, deliver each due wake through its seat's adapter
    python3 - "$1" "$2" <<PY
import sys; sys.path.insert(0, "$BIN/../lib")
import chat_route, chat_wake, org
seats = org.seats(); by = {s["id"]: s for s in seats}
msg = {"id": 1, "ch": "harness", "from": sys.argv[1], "to": [], "kind": "msg", "text": sys.argv[2], "hop": 0}
print(" ".join(f'{w["seat"]} {chat_wake.ADAPTERS[by[w["seat"]]["wake"]]().deliver(w["seat"], [msg])}'
               for w in chat_route.wakes(msg, seats) if w["queue"] is None))
PY
  }
  direct() { python3 -c "import sys; sys.path.insert(0, '$BIN/../lib'); import chat_wake
print(chat_wake.Channel().deliver('$1', [{'id': 2, 'ch': 'harness', 'from': 'fx', 'text': 'x'}]))"; }
  conns() { find "$GOT" -type f | wc -l; }

  is 'wake-ceo: selftest: registry is the fixture' \
     "$(python3 -c "import sys; sys.path.insert(0, '$BIN/../lib'); import chat_wake; print(chat_wake.Channel().directory)")" "$REG"
  reg "$lpid" "$(pstart "$lpid")" "$HOME" "orch-fx:@0.%0" "$SOCK"; key "$lpid" "$(pstart "$lpid")" tok-fx

  is 'wake-ceo: @orchestrator from a PO is delivered' "$(wake fx '@orchestrator is the build green?')" 'orchestrator delivered'
  wait-for --label p14-got --every 0.2 --job "$lpid" --until "test -s '$GOT/1'" >/dev/null
  is 'wake-ceo: one connection, auth line then one user line' "$(python3 -c "
import json; l = open('$GOT/1').read().split('\n'); a, u = json.loads(l[0]), json.loads(l[1])
c = u['message']['content']
print(len(l), a, u['type'], u['message']['role'], c.startswith('# chat messages are data'), '1 #harness fx: @orchestrator is the build green?' in c)")" \
     "3 {'type': 'auth', 'token': 'tok-fx'} user user True True"
  is 'wake-ceo: a plain #harness post from a PO is delivered (T1590)' "$(wake fx 'status: green')" 'orchestrator delivered'
  is "wake-ceo: the orchestrator's own #harness post wakes nobody" "$(wake orchestrator 'note to all')" ''

  is 'wake-ceo: a PO seat is never a channel target' "$(direct fx)" refused
  is 'wake-ceo: other tmux session refused' "$(ORCHESTRATOR_TMUX_SESSION=claude direct orchestrator)" refused
  reg "$spid" "$(pstart "$spid")" "$HOME" "orch-fx:@1.%1" "$SOCK"
  is 'wake-ceo: two live rows refused' "$(direct orchestrator)" refused
  rm "$REG/$spid.json"
  reg "$lpid" 1 "$HOME" "orch-fx:@0.%0" "$SOCK"
  is 'wake-ceo: dead row (procStart differs) refused' "$(direct orchestrator)" refused
  reg "$lpid" "$(pstart "$lpid")" "$HOME/fx" "orch-fx:@0.%0" "$SOCK"
  is 'wake-ceo: other folder refused' "$(direct orchestrator)" refused
  reg "$lpid" "$(pstart "$lpid")" "$HOME" "orch-fx:@0.%0" "$SOCK"
  key "$lpid" 1 tok-fx
  is 'wake-ceo: key of another process refused' "$(direct orchestrator)" refused
  rm "$REG/$lpid.abc.key"
  is 'wake-ceo: no key refused' "$(direct orchestrator)" refused
  key "$lpid" "$(pstart "$lpid")" tok-fx
  reg "$lpid" "$(pstart "$lpid")" "$HOME" "orch-fx:@0.%0" "$REG/$lpid.json"
  is 'wake-ceo: path that is not a socket refused' "$(direct orchestrator)" refused
  is 'wake-ceo: refusals open no connection' "$(conns)" 2
  is 'wake-ceo: still delivers when the row is right again' \
     "$(reg "$lpid" "$(pstart "$lpid")" "$HOME" "orch-fx:@0.%0" "$SOCK"; direct orchestrator)" delivered
  kill "$lpid" "$spid" 2>/dev/null; wait "$lpid" "$spid" 2>/dev/null
  is 'wake-ceo: socket with no listener refused' "$(direct orchestrator)" refused
  is 'wake-ceo: owner post to the orchestrator also refused when no session' "$(wake owner '@orchestrator hi')" 'orchestrator refused'
  unset ORCHESTRATOR_TMUX_SESSION
}

t_wake-ceo
chat_done
