#!/usr/bin/env bash
# host-only: needs the bot venv built on this box
# discord-bot fixture tests (fake Discord REST) through the bot's venv python, which has aiohttp.
set -uo pipefail
venv="$HOME/agents/discord-bot/.venv/bin/python"
[ -x "$venv" ] || { echo "SKIP owner data absent: $venv"; exit 0; }
out="$("$HOME/agents/bin/discord-bot" test 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then echo "ok discord-bot: $(grep -o 'Ran [0-9]* tests' <<<"$out")"; else echo "$out"; echo "FAIL discord-bot (rc=$rc)"; fi
exit $rc
