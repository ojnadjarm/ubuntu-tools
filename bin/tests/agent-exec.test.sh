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
m=$(cd "$tmp" && MODEL=m-env HARNESS_AGENT_CMD='printf %s "$MODEL"' "$AE" --prompt-file p.md --cwd sub --raw-out r1 --meta-out m1 2>/dev/null)
eq "MODEL from the environment reaches the adapter" m-env "$m"
m=$(cd "$tmp" && MODEL=m-env HARNESS_AGENT_CMD='printf %s "$MODEL"' "$AE" --prompt-file p.md --cwd sub --model m-flag --raw-out r2 --meta-out m2 2>/dev/null)
eq "--model wins over MODEL" m-flag "$m"
out=$("$AE" --help 2>/dev/null); rc=$?
eq "--help: exit 0" 0 "$rc"
grep -q '^usage: agent-exec' <<<"$out" && ok "--help: usage on stdout" || nok "--help: usage on stdout" "$out"
grep -q 'MODEL=<id> EFFORT=<level>' <<<"$out" && ok "--help: MODEL/EFFORT from the environment" || nok "--help: MODEL/EFFORT" "$out"
grep -qF 'MODEL=claude-fable-5-2 EFFORT=medium agent-exec --prompt-file F' <<<"$out" && ok "--help: the example" || nok "--help: the example" "$out"
grep -q 'worker, worker-max, planner are Agent-tool agent types, not commands' <<<"$out" && ok "--help: agent types line" || nok "--help: agent types line" "$out"
is "-h: same as --help" "$("$AE" -h 2>/dev/null)" "$out"
out=$("$AE" --bogus 2>&1 >/dev/null); rc=$?
eq "bad option: exit 2" 2 "$rc"
grep -q '^usage: agent-exec' <<<"$out" && ok "bad option: usage on stderr" || nok "bad option: usage on stderr" "$out"
is "bad option: nothing on stdout" "$("$AE" --bogus 2>/dev/null)" ""
exit $bad
