#!/usr/bin/env bash
# host-only: needs the discord-bot venv built on this box
# discord-liaison fixture tests (discord-bot's fake Discord REST; nothing reaches the real server).
set -uo pipefail
venv="$HOME/agents/discord-bot/.venv/bin/python"
[ -x "$venv" ] || { echo "SKIP owner data absent: $venv"; exit 0; }
out="$("$HOME/agents/bin/discord-liaison" test 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then echo "ok discord-liaison: $(grep -o 'Ran [0-9]* tests' <<<"$out")"; else echo "$out"; echo "FAIL discord-liaison (rc=$rc)"; fi

# The wrapper in a fixture HOME with a stub python: agent.env's job model and effort reach the worker's environment.
H=$(mktemp -d); trap 'rm -rf "$H"' EXIT
mkdir -p "$H/agents/bin" "$H/agents/discord-liaison" "$H/agents/discord-bot/.venv/bin"
cp "$HOME/agents/bin/discord-liaison" "$H/agents/bin/"; : >"$H/agents/bin/env.sh"
cp "$HOME/agents/discord-liaison/agent.env" "$H/agents/discord-liaison/"
printf '#!/bin/sh\necho "$LIAISON_JOB_MODEL|$LIAISON_JOB_EFFORT"\n' >"$H/agents/discord-bot/.venv/bin/python"; chmod +x "$H/agents/discord-bot/.venv/bin/python"
want=$(. "$H/agents/discord-liaison/agent.env"; echo "$LIAISON_JOB_MODEL|$LIAISON_JOB_EFFORT")
got=$(HOME="$H" env -u LIAISON_JOB_MODEL -u LIAISON_JOB_EFFORT bash "$H/agents/bin/discord-liaison" status)
if [ "$got" = "$want" ] && [ "$want" != '|' ]; then echo "ok wrapper exports the job model and effort ($got)"; else echo "FAIL wrapper exports: expected '$want', got '$got'"; rc=1; fi
exit $rc
