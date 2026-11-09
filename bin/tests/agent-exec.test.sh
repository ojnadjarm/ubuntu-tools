#!/usr/bin/env bash
# agent-exec argument handling on the generic adapter with a harmless command; fixture dirs only.
set -uo pipefail
AE="$HOME/agents/bin/agent-exec"
. "$HOME/agents/bin/tests/lib/assert.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HARNESS_AGENT=generic HARNESS_AGENT_CMD='printf %s "$PROMPT"'
mkdir "$tmp/sub"; printf 'do the thing' >"$tmp/p.md"

timeout 5 "$AE" --prompt-file "$tmp/p.md" --model >/dev/null 2>&1; eq "a flag without its value is a usage error, not a hang" 2 $?
out=$(cd "$tmp" && "$AE" --prompt-file p.md --cwd sub --raw-out raw.txt --meta-out meta.json 2>&1); rc=$?
eq "relative paths with --cwd: exit 0" 0 "$rc"
eq "relative paths with --cwd: the prompt is read" "do the thing" "$out"
eq "relative --raw-out is under the caller's cwd" "do the thing" "$(cat "$tmp/raw.txt" 2>/dev/null)"
eq "relative --meta-out holds the exit code" 0 "$(jq -r .exit "$tmp/meta.json" 2>/dev/null)"
eq "nothing stray is written under --cwd" "" "$(ls "$tmp/sub")"
exit $bad
