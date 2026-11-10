#!/usr/bin/env bash
# T1515 bin/chat: the vass section (run alone or via chat.test.sh vass); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_vass() {
  # P20: a pull seat (fixture `acme`, named after the fixture protected project) has #harness and direct messages only,
  # is never woken, meets the strict guard, and nothing opens, lists or stats its folder or reaches a container runtime.
  local out rc id REG="$HOME/.claude/sessions" spid
  rm -rf "$ST" "$REG"; rm -f "$WORK/notify.log" "$WORK/systemd-run.log"; mkdir -p "$WORK/no-guides" "$REG"
  sed 's/^]}/,{"id": "acme", "name": "Acme seat", "role": "po", "parent": "orchestrator", "wake": "pull", "match": null}\n]}/' \
    "$HARNESS_HOME/org.json" >"$WORK/org-acme.json"
  export ORG_FILE="$WORK/org-acme.json" GUIDES_DIR="$WORK/no-guides"; unset CLAUDE_SESSIONS_DIR
  msgs() { cat "$ST"/harness.*.jsonl "$ST"/dm-*.jsonl 2>/dev/null | wc -l; }
  wakes() { python3 -c "import json
print([(r['wake'], r['outcome']) for r in map(json.loads, open('$ST/audit.jsonl')) if r.get('wake') == 'acme'])"; }

  CHAT_SEAT=acme chat post harness 'how do I run behat headless?' >/dev/null; rc=$?
  is 'vass: the seat posts in #harness' "$rc $(msgs)" '0 1'
  id=$(CHAT_SEAT=acme chat ask --post 'how do I purge caches from the cli?'); rc=$?
  is 'vass: one command asks in #harness' "$rc $([[ "$id" =~ ^[0-9]{13}$ ]] && echo id) $(msgs)" '0 id 2'
  CHAT_SEAT=acme chat post @orchestrator 'hello' >/dev/null; rc=$?
  is 'vass: the seat writes a direct message' "$rc $(ls "$ST" | grep -c '^dm-acme--orchestrator')" '0 1'
  out=$(CHAT_SEAT=acme chat post org 'x' 2>&1); rc=$?
  is 'vass: no #org for the seat (rc 2)' "$rc $out" '2 chat: acme has #harness and direct messages only'
  out=$(CHAT_SEAT=fx chat post acme 'x' 2>&1); rc=$?
  is 'vass: no project channel named after the seat (rc 2)' "$rc ${out%%:*}" '2 chat'
  is 'vass: refused posts stored nothing' "$(msgs)" 3

  held() {   # held <name> <seat> <where> <text> <rule>
    local before; before=$(msgs)
    out=$(CHAT_SEAT=$2 chat post "$3" "$4" 2>&1); rc=$?
    is "vass: held, not stored: $1" "$rc $(msgs) $out" "3 $before chat: held ($5): nothing was posted"
  }
  held 'ticket key from the seat' acme harness 'stuck on XY-12 again' 'ticket key'
  held 'protected word from the seat, any case' acme harness 'my ACME env is slow' 'protected word'
  held 'deny word from the seat' acme harness 'the globex course' 'deny word'
  held 'protected path from the seat' acme harness 'see ~/acme/x' 'protected path'
  held 'ticket key in a direct message to the seat' fx @acme 'about AB-7' 'ticket key'
  held 'ticket key naming @the seat' fx harness '@acme about AB-7' 'ticket key'
  out=$(CHAT_SEAT=orchestrator chat answer "$id" 'like AB-7 did' 2>&1); rc=$?
  is 'vass: held, not stored: ticket key in an answer to the seat' "$rc $(msgs)" '3 3'
  CHAT_SEAT=fx chat post harness 'fixed AB-7' >/dev/null; rc=$?
  is 'vass: fleet seats keep ticket keys among themselves' "$rc $(msgs)" '0 4'
  ev 'vass: held audit lines name the rule, never the text' \
     '! grep -q "XY-12\|AB-7\|ACME\|globex" <(grep "\"held\"" "$ST/audit.jsonl")'

  CHAT_SEAT=orchestrator chat answer "$id" 'php admin/cli/purge_caches.php' >/dev/null
  CHAT_SEAT=fx chat post @acme 'ping' >/dev/null
  is 'vass: pull: every wake of the seat is queued, nothing delivered' "$(wakes)" "[('acme', 'queued'), ('acme', 'queued')]"
  ev 'vass: pull: no timer, no inbox, no parked wake, no count' \
     '[ ! -s "$WORK/systemd-run.log" ] && [ ! -e "$HARNESS_HOME/po-acme" ] && [ ! -e "$ST/queue/acme.jsonl" ] && ! grep -qs acme "$ST"/counters/2*.json'
  CHAT_SEAT=fx chat post org 'fleet news' >/dev/null; CHAT_SEAT=orchestrator chat post fx 'fx only' >/dev/null
  is 'vass: read lists #harness and its direct messages only' "$(CHAT_SEAT=acme chat read | awk '{print $1}' | sort | tr '\n' ' ')" \
     'dm-acme--fx dm-acme--orchestrator harness '
  out=$(CHAT_SEAT=acme chat read org 2>&1); rc=$?
  is 'vass: reading #org refused (rc 2)' "$rc $out" '2 chat: acme has #harness and direct messages only'
  out=$(CHAT_SEAT=acme chat read --unread)
  ev 'vass: the answer and the direct message wait in the store' \
     'grep -q "orchestrator -> acme (answer re $id): php admin/cli/purge_caches.php" <<<"$out" && grep -q "fx -> acme: ping" <<<"$out"'
  CHAT_SEAT=acme chat post @owner 'can we talk' >/dev/null
  is 'vass: a phone ping from the seat carries no text' "$(tail -1 "$WORK/notify.log")" \
     '-t|chat: Acme seat|[acme] wrote to you; read it on the Chat screen|'

  # Proof: the seat's whole flow under strace, with its session live in the fixture registry.
  sleep 60 & spid=$!
  printf '{"pid": %s, "procStart": "%s", "cwd": "%s", "status": "busy"}' "$spid" \
    "$(cut -d')' -f2 "/proc/$spid/stat" | awk '{print $20}')" "$HOME/acme/sub" >"$REG/$spid.json"
  strace -f -y -qq -o "$WORK/vass.trace" -e trace=%file,getdents64,fchdir bash -c '
    python3 -c "import sys; sys.path.insert(0, \"$1/../lib\"); import sessions; print(sessions.live())"
    CHAT_SEAT=acme python3 "$1/chat" ask --post "is the build green?"
    CHAT_SEAT=fx python3 "$1/chat" post @acme "yes"
    CHAT_SEAT=acme python3 "$1/chat" read --unread' _ "$BIN" >"$WORK/vass.out" 2>&1
  kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null
  is 'vass: on/off: the live session shows as the seat, 3 keys' "$(head -1 "$WORK/vass.out")" \
     "[{'seat': 'acme', 'state': 'working', 'since': 0}]"
  ev 'vass: proof selftest: the trace saw the registry and the store' 'grep -q "$REG" "$WORK/vass.trace" && grep -q "$ST" "$WORK/vass.trace"'
  is 'vass: no open, list or stat of the protected folder, no container runtime' \
     "$(python3 "$BIN/tests/lib/no_touch.py" "$WORK/vass.trace" "$HOME/acme")" ''
  unset ORG_FILE GUIDES_DIR
}

t_vass
chat_done
