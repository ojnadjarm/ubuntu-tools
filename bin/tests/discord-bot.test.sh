#!/usr/bin/env bash
# discord-bot fixture tests (fake Discord REST) through the bot's venv python, which has aiohttp.
set -uo pipefail
out="$("$HOME/agents/bin/discord-bot" test 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then echo "ok discord-bot: $(grep -o 'Ran [0-9]* tests' <<<"$out")"; else echo "$out"; echo "FAIL discord-bot (rc=$rc)"; fi
exit $rc
