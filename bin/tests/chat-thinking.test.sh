#!/usr/bin/env bash
# T1515 bin/chat: the thinking section (run alone or via chat.test.sh thinking); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_thinking() {
  # P38: who is thinking, from real state: woken, starting until a run takes the request; thinking while po-run runs it
  # (its lock held) or the orchestrator's session is busy; gone when the run ends or the seat replies in that channel.
  local P="$HARNESS_HOME/po-fx" REG="$HOME/.claude/sessions" flush run spid at
  rm -rf "$ST" "$WORK/systemd-run.log" "$WORK/running" "$WORK/go"; mkdir -p "$P/inbox" "$WORK/think"; : >"$P/BRIEF.md"
  think() { python3 -c "import sys; sys.path.insert(0, '$BIN/../lib'); import chat_thinking
print(' '.join(f\"{t['seat']}:{t['ch']}:{t['state']}\" for t in chat_thinking.now()) or 'none')"; }
  woke() { python3 -c "import json; print('$2' in json.load(open('$ST/woke/$1.json')))"; }
  printf '#!/bin/sh\ntouch "$WORK/running"\nwhile [ ! -e "$WORK/go" ]; do sleep 0.1; done\n' >"$WORK/think/agent-run"
  chmod +x "$WORK/think/agent-run"
  start() { rm -f "$WORK/running" "$WORK/go"; PATH="$WORK/think:$PATH" "$BIN/po-run" fx >/dev/null 2>&1 & run=$!
    wait-for --label p38-run --every 0.1 --job "$run" --until "test -e '$WORK/running'" >/dev/null || nok 'thinking: fixture run' 'never started'; }

  is 'thinking: nobody woken, nobody thinking' "$(think)" none
  CHAT_SEAT=gx chat post @fx 'are you there?' >/dev/null
  is 'thinking: an armed batch: woken, starting' "$(think)" 'fx:dm-fx--gx:starting'
  flush=$(sed -n 's/.* --setenv=HARNESS_HOME=[^ ]* //p' "$WORK/systemd-run.log" | tail -1); $flush
  is 'thinking: filed in the inbox, not started: starting' "$(think)" 'fx:dm-fx--gx:starting'
  start
  is 'thinking: po-run runs the request: thinking' "$(think)" 'fx:dm-fx--gx:thinking'
  touch "$WORK/go"; wait "$run"
  is 'thinking: the run exited: gone' "$(think)" none
  is 'thinking: the wake of a finished run is dropped from disk' "$(woke fx dm-fx--gx)" False

  CHAT_SEAT=gx chat post fx '@fx and again' >/dev/null; $flush; start
  is 'thinking: second wake, run alive: thinking in that channel' "$(think)" 'fx:fx:thinking'
  CHAT_SEAT=fx chat post fx 'here it is' >/dev/null
  is 'thinking: its reply in the channel clears it while the run lives' "$(think)" none
  is 'thinking: a replied wake is dropped from disk' "$(woke fx fx)" False
  touch "$WORK/go"; wait "$run"
  "$BIN/po-ask" fx --from orchestrator 'unrelated' >/dev/null
  is 'thinking: a later run for another request is not this wake' "$(start; think; touch "$WORK/go"; wait "$run")" none

  export ORCHESTRATOR_TMUX_SESSION=orch-fx; unset CLAUDE_SESSIONS_DIR; rm -rf "$REG"; mkdir -p "$REG"
  sleep 60 & spid=$!
  at=$(python3 -c "import sys, time; sys.path.insert(0, '$BIN/../lib'); import chat_wake
chat_wake.woke('orchestrator', [{'id': 5, 'ch': 'harness'}]); print(int(time.time() * 1000))")
  status() { printf '{"pid": %s, "procStart": "%s", "cwd": "%s", "tmux": "orch-fx:@0.%%0", "status": "%s", "statusUpdatedAt": %s}' \
    "$spid" "$(cut -d')' -f2 "/proc/$spid/stat" | awk '{print $20}')" "$HOME" "$1" "$2" >"$REG/$spid.json"; }
  status idle $((at - 5000))
  is 'thinking: orchestrator idle since before the line: starting' "$(think)" 'orchestrator:harness:starting'
  status busy $((at + 100))
  is 'thinking: orchestrator busy after the line: thinking' "$(think)" 'orchestrator:harness:thinking'
  python3 -c "import json; p = '$ST/woke/orchestrator.json'; w = json.load(open(p)); w['harness']['at'] -= 31 * 60000
json.dump(w, open(p, 'w'))"
  is 'thinking: busy, wake older than 30 min: gone' "$(think)" none
  is 'thinking: an expired wake is dropped from disk' "$(woke orchestrator harness)" False
  status idle $((at + 9000))
  is 'thinking: orchestrator idle again: gone' "$(think)" none
  status busy $((at + 9500)); kill "$spid"; wait "$spid" 2>/dev/null
  is 'thinking: orchestrator session gone: gone' "$(think)" none

  # T1545-I: a warm poll starts no process; `protected` runs again only when its config changes; /proc/locks is read
  # only for a request in current/.
  sleep 60 & spid=$!
  at=$(python3 -c "import os, sys, time; sys.path.insert(0, '$BIN/../lib'); import chat_wake
chat_wake.woke('orchestrator', [{'id': 5, 'ch': 'harness'}])
chat_wake.woke('fx', [{'id': 1, 'ch': 'dm-fx--orchestrator'}], os.path.basename(sys.argv[1])); print(int(time.time() * 1000))" \
    "$("$BIN/po-ask" fx --from orchestrator 'queued')")
  status busy $((at + 100))
  strace -f -qq -o "$WORK/warm.trace" -e trace=execve,openat,clone,clone3,fork,vfork python3 -c "
import os, sys; sys.path.insert(0, '$BIN/../lib'); import chat_thinking
first = chat_thinking.now(); open('$WORK/mark-a', 'w').close()
same = all(chat_thinking.now() == first for _ in range(50)); open('$WORK/mark-b', 'w').close()
st = os.stat('$HARNESS_CONFIG'); os.utime('$HARNESS_CONFIG', ns=(st.st_atime_ns, st.st_mtime_ns + 10**9))
print(same and chat_thinking.now() == first, ' '.join(f\"{t['seat']}:{t['ch']}:{t['state']}\" for t in first))" >"$WORK/warm.out"
  kill "$spid"; wait "$spid" 2>/dev/null
  is 'thinking: 50 warm calls give the same answer' "$(cat "$WORK/warm.out")" \
     'True orchestrator:harness:thinking fx:dm-fx--orchestrator:starting'
  is 'thinking: 50 warm calls start 0 processes' "$(sed -n '/mark-a/,/mark-b/p' "$WORK/warm.trace" | grep -cE '(execve|clone3?|v?fork)\(')" 0
  is 'thinking: protected runs once cold, once more after its config changed' \
     "$(grep -c 'execve("[^"]*/bin/protected"' "$WORK/warm.trace")" 2
  is 'thinking: no /proc/locks read while no request is in current/' "$(grep -c '/proc/locks' "$WORK/warm.trace")" 0
}

t_thinking
chat_done
