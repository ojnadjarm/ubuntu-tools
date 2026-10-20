#!/usr/bin/env bash
# F41: the generic adapter runs HARNESS_AGENT_CMD as a shell command (quotes kept, no globbing).
set -uo pipefail
A="$HOME/agents/adapters/generic/run"
. "$HOME/agents/bin/tests/lib/assert.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf 'do the thing\n' >"$tmp/prompt.md"
touch "$tmp/a.x" "$tmp/b.x"
run() { (cd "$tmp" && HARNESS_AGENT_CMD="$1" PROMPT_FILE="$tmp/prompt.md" AGENT_TIMEOUT="${2:-}" \
        RAW_OUT="$tmp/raw.txt" META_OUT="$tmp/meta.json" "$A" 2>&1); }

out="$(run 'sh -c "echo hi"')"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "hi" ] && truthy "quoted arguments survive" 1 || truthy "quoted arguments survive (rc=$rc out='$out')" 0
out="$(run "echo '*.x'")"
[ "$out" = "*.x" ] && truthy "quoted glob is not expanded" 1 || truthy "quoted glob is not expanded (got '$out')" 0
out="$(run 'printf %s "$PROMPT"')"
[ "$out" = "do the thing" ] && truthy "command reads \$PROMPT" 1 || truthy "command reads \$PROMPT (got '$out')" 0
[ "$(cat "$tmp/raw.txt")" = "do the thing" ] && truthy "RAW_OUT keeps the output" 1 || truthy "RAW_OUT keeps the output" 0
run 'exit 7' >/dev/null; rc=$?
[ "$rc" = 7 ] && truthy "exit code passes through" 1 || truthy "exit code passes through (got $rc)" 0
out="$(run 'echo late' 5)"
[ "$out" = "late" ] && truthy "AGENT_TIMEOUT wraps the command" 1 || truthy "AGENT_TIMEOUT wraps the command (got '$out')" 0
# F37: SIGTERM to the adapter (the pid agents-stop kills) stops the agent command too.
(HARNESS_AGENT_CMD='exec sleep 47472' PROMPT_FILE="$tmp/prompt.md" AGENT_TIMEOUT= \
  RAW_OUT="$tmp/raw.txt" META_OUT="$tmp/meta.json" exec "$A") >/dev/null 2>&1 &
ap=$!; sleep 1; kill -TERM "$ap"; wait "$ap" 2>/dev/null; sleep 0.3
left="$(pgrep -f '[s]leep 47472')"
[ -z "$left" ] && truthy "SIGTERM stops the agent command" 1 || { truthy "SIGTERM stops the agent command ($left left)" 0; kill $left; }
exit $bad
