#!/usr/bin/env bash
# F41: the generic adapter runs HARNESS_AGENT_CMD as a shell command (quotes kept, no globbing).
set -uo pipefail
A="$HOME/agents/adapters/generic/run"
bad=0
ok() { if [ "$1" = 1 ]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad+1)); fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf 'do the thing\n' >"$tmp/prompt.md"
touch "$tmp/a.x" "$tmp/b.x"
run() { (cd "$tmp" && HARNESS_AGENT_CMD="$1" PROMPT_FILE="$tmp/prompt.md" AGENT_TIMEOUT="${2:-}" \
        RAW_OUT="$tmp/raw.txt" META_OUT="$tmp/meta.json" "$A" 2>&1); }

out="$(run 'sh -c "echo hi"')"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "hi" ] && ok 1 "quoted arguments survive" || ok 0 "quoted arguments survive (rc=$rc out='$out')"
out="$(run "echo '*.x'")"
[ "$out" = "*.x" ] && ok 1 "quoted glob is not expanded" || ok 0 "quoted glob is not expanded (got '$out')"
out="$(run 'printf %s "$PROMPT"')"
[ "$out" = "do the thing" ] && ok 1 "command reads \$PROMPT" || ok 0 "command reads \$PROMPT (got '$out')"
[ "$(cat "$tmp/raw.txt")" = "do the thing" ] && ok 1 "RAW_OUT keeps the output" || ok 0 "RAW_OUT keeps the output"
run 'exit 7' >/dev/null; rc=$?
[ "$rc" = 7 ] && ok 1 "exit code passes through" || ok 0 "exit code passes through (got $rc)"
out="$(run 'echo late' 5)"
[ "$out" = "late" ] && ok 1 "AGENT_TIMEOUT wraps the command" || ok 0 "AGENT_TIMEOUT wraps the command (got '$out')"
# F37: SIGTERM to the adapter (the pid agents-stop kills) stops the agent command too.
(HARNESS_AGENT_CMD='exec sleep 47472' PROMPT_FILE="$tmp/prompt.md" AGENT_TIMEOUT= \
  RAW_OUT="$tmp/raw.txt" META_OUT="$tmp/meta.json" exec "$A") >/dev/null 2>&1 &
ap=$!; sleep 1; kill -TERM "$ap"; wait "$ap" 2>/dev/null; sleep 0.3
left="$(pgrep -f '[s]leep 47472')"
[ -z "$left" ] && ok 1 "SIGTERM stops the agent command" || { ok 0 "SIGTERM stops the agent command ($left left)"; kill $left; }
exit $bad
