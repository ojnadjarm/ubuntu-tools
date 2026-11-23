#!/usr/bin/env bash
# task-ram hook (T1841): start line and digest at SubagentStart, digest after a compaction, 70 % warning, bounded tail,
# RAM_TICKET, window lookup order, close on a green check, the TASK_RAM kill switch, malformed input.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
HOOK="$BIN/../adapters/claude/hooks/task-ram"
RAM="$BIN/ram"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export AGENT_WORK="$T/aw" XDG_RUNTIME_DIR="$T/run" HOME="$T/home" HARNESS_CONFIG="$T/config.env"
unset TASK_RAM RAM_TICKET CLAUDE_CODE_AUTO_COMPACT_WINDOW
mkdir -p "$HOME/.claude/agents" "$XDG_RUNTIME_DIR"
fail=0 n=0
ok() { n=$((n+1)); echo "ok - $1"; }
no() { n=$((n+1)); echo "not ok - $1"; fail=1; }
run() { printf '%s' "$1" | "$HOOK"; echo "rc=$?"; }
# spawn <session> <agent>: a session transcript with this agent's pending Agent call naming briefs/T77-x.md, then SubagentStart.
spawn() {
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu-%s","name":"Agent","input":{"subagent_type":"worker","prompt":"Your brief is ~/agent-work/briefs/T77-x.md"}}]}}\n' "$2" >"$T/$1.jsonl"
  run "{\"hook_event_name\":\"SubagentStart\",\"session_id\":\"$1\",\"agent_id\":\"$2\",\"agent_type\":\"worker\",\"transcript_path\":\"$T/$1.jsonl\"}"
}
post() { run "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"session_id\":\"$1\",\"agent_id\":\"$2\",\"transcript_path\":\"$T/$1.jsonl\"}"; }
# agent transcript of <session> <agent>: a compact_boundary <uuid> (or none: -), then an assistant row using <tokens>.
tx() {
  mkdir -p "$T/$1/subagents"
  { [ "$3" = - ] || printf '{"type":"system","subtype":"compact_boundary","uuid":"%s"}\n' "$3"
    printf '{"type":"assistant","message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":%s,"output_tokens":50}}}\n' "$4"
  } >>"$T/$1/subagents/agent-$2.jsonl"
}
ctx() { python3 -c 'import json,sys; t=sys.stdin.read().rsplit("rc=",1)[0].strip(); print(json.loads(t)["hookSpecificOutput"]["additionalContext"] if t else "")'; }

o=$(spawn s1 a1)
c=$(ctx <<<"$o")
grep -q '"ticket": "T77"' "$XDG_RUNTIME_DIR/task-ram/s1-a1.json" && grep -q 'ram note T77' <<<"$c" && [ ${#c} -le 300 ] \
  && grep -q 'rc=0' <<<"$o" && ok "SubagentStart: state file, start line (${#c} chars)" || no "start: $o"
"$RAM" note T77 next "write the guide"
c=$(spawn s2 a2 | ctx)
grep -q 'ram note T77' <<<"$c" && grep -q 'next · write the guide' <<<"$c" && ok "SubagentStart with notes: start line + digest" \
  || no "start+digest: $c"

o=$(post s9 a9)
[ "$o" = rc=0 ] && ok "PostToolUse with no ticket: nothing" || no "no ticket: $o"

tx s1 a1 - 20000
o=$(post s1 a1)
[ "$o" = rc=0 ] && ok "PostToolUse, low usage, no boundary: nothing" || no "quiet: $o"
tx s1 a1 b1 5000
c=$(post s1 a1 | ctx); c2=$(post s1 a1 | ctx)
grep -q 'next · write the guide' <<<"$c" && [ -z "$c2" ] && ok "unseen compact_boundary: digest once" || no "boundary: '$c' then '$c2'"

export CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000
tx s1 a1 - 75000
c=$(post s1 a1 | ctx); c2=$(post s1 a1 | ctx)
grep -qi 'compaction is near' <<<"$c" && [ -z "$c2" ] && ok "70 % of the window: warning once" || no "warning: '$c' then '$c2'"
tx s1 a1 b2 5000; post s1 a1 >/dev/null; tx s1 a1 - 75000
c=$(post s1 a1 | ctx)
grep -qi 'compaction is near' <<<"$c" && ok "a new window warns again" || no "second window: '$c'"

printf -- '---\nname: worker\nautoCompactWindow: 100000\n---\n' >"$HOME/.claude/agents/worker.md"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000
spawn s3 a3 >/dev/null; tx s3 a3 - 75000
c=$(post s3 a3 | ctx)
[ -z "$c" ] && ok "window: the environment wins over the agent definition" || no "env window: '$c'"
unset CLAUDE_CODE_AUTO_COMPACT_WINDOW
c=$(post s3 a3 | ctx)
grep -qi 'compaction is near' <<<"$c" && ok "window: the agent definition's autoCompactWindow" || no "agent def window: '$c'"
echo '{"autoCompactWindow": 300000}' >"$HOME/.claude/settings.json"
rm "$HOME/.claude/agents/worker.md"
spawn s4 a4 >/dev/null; tx s4 a4 - 75000
c=$(post s4 a4 | ctx)
echo '{"autoCompactWindow": 100000}' >"$HOME/.claude/settings.json"
c2=$(post s4 a4 | ctx)
[ -z "$c" ] && grep -qi 'compaction is near' <<<"$c2" && ok "window: settings.json autoCompactWindow" || no "settings window: '$c' / '$c2'"

tx s1 a1 b3 5000
python3 -c 'import sys; sys.stdout.write("{\"type\":\"user\",\"message\":{\"content\":\"" + "A"*8000000 + "\"}}\n")' \
  >>"$T/s1/subagents/agent-a1.jsonl"
o=$(post s1 a1)
[ "$o" = rc=0 ] && ok "8 MB last row: bounded read (the earlier unseen boundary stays unseen), nothing" || no "big row: ${o:0:200}"

c=$(RAM_TICKET=F1 run '{"hook_event_name":"PostToolUse","tool_name":"Bash","session_id":"s5","transcript_path":"/nonexistent.jsonl"}' | ctx)
c2=$(RAM_TICKET=F1 run '{"hook_event_name":"PostToolUse","tool_name":"Bash","session_id":"s5","transcript_path":"/nonexistent.jsonl"}' | ctx)
grep -q 'ram note F1' <<<"$c" && [ -z "$c2" ] && ok "RAM_TICKET=F1, no state: start line on the first PostToolUse" || no "RAM_TICKET: '$c' / '$c2'"

stop() { run "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s1\",\"agent_id\":\"a1\",\"transcript_path\":\"$T/s1.jsonl\"}"; }
stop >/dev/null
mkdir -p "$AGENT_WORK/evidence/T77"; echo '{"ok": false, "rc": 1}' >"$AGENT_WORK/evidence/T77/check.json"
stop >/dev/null
[ -e "$AGENT_WORK/ram/T77/notes.md" ] && [ ! -e "$AGENT_WORK/evidence/T77/ram.md" ] && ok "SubagentStop: no or red check keeps the notes" \
  || no "red stop closed"
echo '{"ok": true, "rc": 0}' >"$AGENT_WORK/evidence/T77/check.json"
o=$(stop)
[ "$o" = rc=0 ] && [ ! -e "$AGENT_WORK/ram/T77" ] && grep -q 'write the guide' "$AGENT_WORK/evidence/T77/ram.md" \
  && ok "SubagentStop: green check closes" || no "green stop: $o $(ls -R "$AGENT_WORK")"

"$RAM" note T77 next "again"
o=$(TASK_RAM=off spawn s6 a6)
tx s2 a2 b9 5000
o2=$(TASK_RAM=off post s2 a2)
o3=$(RAM_TICKET=F2 TASK_RAM=off run '{"hook_event_name":"PostToolUse","tool_name":"Bash","session_id":"s7"}')
[ "$o" = rc=0 ] && [ "$o2" = rc=0 ] && [ "$o3" = rc=0 ] && ok "TASK_RAM=off in the environment: every event silent" \
  || no "off env: $o / $o2 / $o3"
echo 'TASK_RAM=off' >"$HARNESS_CONFIG"
o=$(post s2 a2)
c=$(TASK_RAM=on post s2 a2 | ctx)
[ "$o" = rc=0 ] && grep -q 'next · again' <<<"$c" && ok "TASK_RAM=off in config.env silences; the environment wins" \
  || no "config off: $o / $c"
rm "$HARNESS_CONFIG"

o=$(run 'not json'); o2=$(run ''); o3=$(run '{"hook_event_name":"PostToolUse","session_id":[1]}')
[ "$o" = rc=0 ] && [ "$o2" = rc=0 ] && [ "$o3" = rc=0 ] && ok "malformed input: exit 0, silent" || no "malformed: $o / $o2 / $o3"

echo "$n tests"
exit $fail
