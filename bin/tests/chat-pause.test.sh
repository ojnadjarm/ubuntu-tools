#!/usr/bin/env bash
# T1515 bin/chat: the pause section (run alone or via chat.test.sh pause); fixture and sandbox: lib/chat-fixture.sh.
. "$(dirname "$(readlink -f "$0")")/lib/chat-fixture.sh"

t_pause() {
  # P18: chat pause|resume [--apply] sets or clears PAUSED (dry run without --apply, any shell); agents-stop sets it.
  local out rc id SB="$HARNESS_HOME/bin" P="$HARNESS_HOME/po-fx" day
  rm -rf "$ST" "$WORK/systemd-run.log"; mkdir -p "$P/inbox"; : >"$P/BRIEF.md"
  wakes() { python3 -c "import json
print([(r['wake'], r['outcome']) for r in map(json.loads, open('$ST/audit.jsonl')) if r.get('id') == $1 and 'wake' in r])"; }
  queued() { cat "$ST/queue/fx.jsonl" 2>/dev/null | wc -l; }
  is 'pause: dry run prints would, rc 0' "$(chat pause; echo "rc $?")" "$(printf 'would: running → paused\nrc 0')"
  ev 'pause: dry run changes nothing' '[ ! -e "$ST/PAUSED" ]'
  is 'pause --apply: reads back paused' "$(chat pause --apply)" 'chat: paused (undo: chat resume --apply)'
  ev 'pause --apply: PAUSED exists' '[ -e "$ST/PAUSED" ]'
  is 'pause --apply twice: still paused' "$(chat pause --apply)" 'chat: paused (undo: chat resume --apply)'
  id=$(CHAT_SEAT=gx chat post @fx 'while paused'); rc=$?
  is 'paused: post stored (rc 0)' "$rc $(grep -c "\"id\": $id" "$ST"/dm-fx--gx.*.jsonl)" '0 1'
  is 'paused: nobody woken, the wake is parked' "$(wakes "$id") $(queued)" "[('fx', 'paused')] 1"
  is 'resume: dry run prints would' "$(chat resume)" 'would: paused → running'
  is 'resume --apply: reads back running, re-sends the parked wake' "$(chat resume --apply)" \
     "$(printf 'chat: running (undo: chat pause --apply)\nchat: 1 held wake re-sent: fx delivered')"
  ev 'resume --apply: PAUSED gone' '[ ! -e "$ST/PAUSED" ]'
  is 'resume: the parked wake went through the adapter, queue empty' "$(wakes "$id") $(queued)" \
     "[('fx', 'paused'), ('fx', 'delivered')] 0"
  is 'pause: audit has one line per applied switch' "$(grep -c '"pause"' "$ST/audit.jsonl")" 3

  day="$ST/counters/$(date +%F).json"
  echo 1 >"$WORK/plan.rc"
  id=$(CHAT_SEAT=gx chat post @fx 'plan full')
  is 'plan 95 %: parked' "$(wakes "$id") $(queued)" "[('fx', 'plan')] 1"
  chat pause --apply >/dev/null
  is 'resume while the plan is still full: parked again, nothing lost' "$(chat resume --apply | tail -1) $(queued)" \
     'chat: 1 held wake re-sent: fx plan 1'
  rm "$day" "${day%.json}.drained" "$WORK/plan.rc"
  CHAT_SEAT=fx chat post harness 'first post of a new day' >/dev/null
  is "new day: the first post re-sends the parked wake" "$(wakes "$id" | grep -o "'fx', '[a-z]*')]$") $(queued)" \
     "'fx', 'queued')] 0"
  CHAT_SEAT=fx chat post harness 'second post' >/dev/null
  is 'new day: only the first post drains' "$(grep -c "\"id\": $id" "$ST/audit.jsonl")" 4

  # agents-stop on fakes: systemctl, claude, notify-owner in the fixture's bin; no user bus to reach.
  mkdir -p "$HOME/agents/bin" "$SB" "$WORK/run"
  ln -sf "$BIN/fleetlib.sh" "$HOME/agents/bin/fleetlib.sh"
  ln -sf "$BIN/chat" "$SB/chat"
  printf '#!/bin/sh\necho "$*" >>"$WORK/systemctl.log"\ncase "$*" in *is-active*) echo inactive ;; esac\n' >"$SB/systemctl"
  printf '#!/bin/sh\necho "[]"\n' >"$SB/claude"
  cp "$WORK/stubs/notify-owner" "$SB/notify-owner"
  chmod +x "$SB/systemctl" "$SB/claude" "$SB/notify-owner"
  rm -f "$WORK/notify.log"
  out=$(HARNESS_ENV_LOADED=1 DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent XDG_RUNTIME_DIR="$WORK/run" \
        bash "$BIN/agents-stop" 2>&1)
  ev 'agents-stop: selftest: the fake systemctl answered' '[ -s "$WORK/systemctl.log" ]'
  ev 'agents-stop: sets PAUSED' '[ -e "$ST/PAUSED" ]'
  is 'agents-stop: says chat is paused' "$out" 'agents-stop: nothing; chat paused'
  is 'agents-stop: the push says so too' "$(cat "$WORK/notify.log")" '-p|high|-t|agents-stop|kill switch: stopped nothing; chat paused|'
  chat resume --apply >/dev/null
}

t_pause
chat_done
