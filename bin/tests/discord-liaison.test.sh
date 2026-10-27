#!/usr/bin/env bash
# host-only: needs the discord-bot venv built on this box
# discord-liaison fixture tests (discord-bot's fake Discord REST; nothing reaches the real server).
set -uo pipefail
venv="$HOME/agents/discord-bot/.venv/bin/python"
[ -x "$venv" ] || { echo "SKIP owner data absent: $venv"; exit 0; }
out="$("$HOME/agents/bin/discord-liaison" test 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then echo "ok discord-liaison: $(grep -o 'Ran [0-9]* tests' <<<"$out")"; else echo "$out"; echo "FAIL discord-liaison (rc=$rc)"; fi
exit $rc
