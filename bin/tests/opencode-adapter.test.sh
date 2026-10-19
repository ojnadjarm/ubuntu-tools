#!/usr/bin/env bash
# GH16: the opencode adapter's flags, result text, meta and audit conversion, against a
# recorded `opencode run --format json` stream (fixtures/opencode/events.jsonl, v1.18.29).
set -uo pipefail
HOME_DIR="$HOME"
A="$HOME_DIR/agents/adapters/opencode"
F="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/opencode"
bad=0
ok() { if [ "$1" = 1 ]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad+1)); fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf 'do the thing\n' >"$tmp/prompt.md"
printf 'the preamble\n'  >"$tmp/system.md"

out="$(OPENCODE_BIN="$F/bin/opencode" OC_ARGV_OUT="$tmp/argv" \
       HARNESS_HOME="$tmp" PROMPT_FILE="$tmp/prompt.md" SYSTEM_FILE="$tmp/system.md" \
       MODEL=opus AGENT_NAME=hello AGENT_TIMEOUT= BUDGET_USD=1 \
       RAW_OUT="$tmp/raw.json" META_OUT="$tmp/meta.json" "$A/run")"
rc=$?

[ "$rc" = 0 ] && ok 1 "run exits 0" || ok 0 "run exits 0 (got $rc)"
[ "$out" = "DONE" ] && ok 1 "stdout is the joined text parts" || ok 0 "stdout is the joined text parts (got '$out')"
cmp -s "$tmp/raw.json" "$F/events.jsonl" && ok 1 "RAW_OUT keeps the event stream" || ok 0 "RAW_OUT keeps the event stream"

argv="$(tr '\n' ' ' <"$tmp/argv")"
case "$argv" in
  "run --format json --auto --title agent-hello -- "*) ok 1 "flags: run --format json --auto --title, message last";;
  *) ok 0 "flags (got: $argv)";;
esac
case "$argv" in *"--model"*) ok 0 "a bare MODEL name is not passed as provider/model";;
                *) ok 1 "a bare MODEL name is not passed as provider/model";; esac
grep -q 'the preamble' "$tmp/argv" && ok 1 "the system file is prepended to the message" \
  || ok 0 "the system file is prepended to the message"

OPENCODE_BIN="$F/bin/opencode" OC_ARGV_OUT="$tmp/argv2" OPENCODE_MODEL=zen/free \
  HARNESS_HOME="$tmp" PROMPT_FILE="$tmp/prompt.md" SYSTEM_FILE= \
  MODEL= AGENT_NAME= AGENT_TIMEOUT= BUDGET_USD= \
  RAW_OUT="$tmp/raw2.json" META_OUT="$tmp/meta2.json" "$A/run" >/dev/null
grep -qx 'zen/free' "$tmp/argv2" && ok 1 "OPENCODE_MODEL pins the model" || ok 0 "OPENCODE_MODEL pins the model"

cost="$(jq -r '.cost_usd' "$tmp/meta.json")"
[ "$cost" != null ] && ok 1 "meta.json carries cost_usd" || ok 0 "meta.json carries cost_usd (got $cost)"
# The fixture has 2 step-finish parts; agent-run's usage_row must see their sums.
usage="$(jq -r '[(.tokens // {}) | (.input_tokens // 0), (.output_tokens // 0),
                (.cache_read_input_tokens // 0)] + [(.tool_calls // 0)] | @tsv' "$tmp/meta.json")"
[ "$usage" = "$(printf '4153\t142\t17408\t1')" ] \
  && ok 1 "meta tokens are summed over steps in agent-run's key names, with tool_calls" \
  || ok 0 "meta tokens are summed over steps in agent-run's key names, with tool_calls (got '$usage')"
[ "$(jq -c '.tool_histogram' "$tmp/meta.json")" = '{"bash":1}' ] \
  && ok 1 "meta tool_histogram counts tool parts by opencode tool name" \
  || ok 0 "meta tool_histogram counts tool parts by opencode tool name"

# audit: run wrote log/actions.jsonl under the fake HARNESS_HOME, mapping bash -> Bash.
log="$tmp/log/actions.jsonl"
[ -s "$log" ] && ok 1 "audit records were written" || ok 0 "audit records were written"
[ "$(jq -r 'select(.tool=="Bash") | .summary' "$log" 2>/dev/null | head -1)" = "cat sample.txt" ] \
  && ok 1 "the bash tool call is audited as Bash with its command" \
  || ok 0 "the bash tool call is audited as Bash with its command"

OC_EXIT=7 OPENCODE_BIN="$F/bin/opencode" HARNESS_HOME="$tmp" PROMPT_FILE="$tmp/prompt.md" \
  SYSTEM_FILE= MODEL= AGENT_NAME= AGENT_TIMEOUT= BUDGET_USD= \
  RAW_OUT="$tmp/raw3.json" META_OUT="$tmp/meta3.json" "$A/run" >/dev/null 2>&1
[ $? = 7 ] && ok 1 "the CLI's exit code survives the pipe" || ok 0 "the CLI's exit code survives the pipe"

OPENCODE_BIN=/nonexistent/opencode HARNESS_HOME="$tmp" PROMPT_FILE="$tmp/prompt.md" \
  SYSTEM_FILE= MODEL= AGENT_NAME= AGENT_TIMEOUT= BUDGET_USD= \
  RAW_OUT="$tmp/raw4.json" META_OUT="$tmp/meta4.json" "$A/run" >/dev/null 2>&1
[ $? = 2 ] && ok 1 "a missing binary exits 2" || ok 0 "a missing binary exits 2"

# install/uninstall are idempotent and confined to the config dir given.
conf="$tmp/conf"
OPENCODE_CONFIG_DIR="$conf" "$A/install" >/dev/null 2>&1
OPENCODE_CONFIG_DIR="$conf" "$A/install" 2>/dev/null | grep -q 'no changes' \
  && ok 1 "a second install prints no changes" || ok 0 "a second install prints no changes"
[ -L "$conf/skills/desktop/SKILL.md" ] && ok 1 "skills are symlinked into the config dir" \
  || ok 0 "skills are symlinked into the config dir"
[ "$(jq -r '.instructions[0]' "$conf/opencode.json" 2>/dev/null)" = "$HOME_DIR/agents/AGENTS.md" ] \
  && ok 1 "AGENTS.md is in instructions" || ok 0 "AGENTS.md is in instructions"
OPENCODE_CONFIG_DIR="$conf" "$A/uninstall" >/dev/null 2>&1
[ ! -e "$conf/skills/desktop/SKILL.md" ] && [ "$(jq -r '.instructions // "gone"' "$conf/opencode.json")" = gone ] \
  && ok 1 "uninstall reverses both" || ok 0 "uninstall reverses both"

# F42: an unwritable audit log or a malformed tool event must not stop the stdin echo.
bh="$tmp/badhome"; mkdir -p "$bh/log/actions.jsonl"
producer() {
  printf '%s\n' '{"type":"tool_use","part":{"type":"tool","tool":"bash","state":{"status":"completed","input":"oops"}}}'
  for i in $(seq 200); do
    printf '{"type":"tool_use","part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"echo %s"}}}}\n' "$i"
  done
  echo FINAL
}
producer | tee "$tmp/raw5" | HARNESS_HOME="$bh" "$A/audit-from-stream" >/dev/null 2>"$tmp/err5"
ps="${PIPESTATUS[*]}"
[ "$ps" = "0 0 0" ] && ok 1 "an audit failure leaves the pipe exiting 0 0 0" \
  || ok 0 "an audit failure leaves the pipe exiting 0 0 0 (got $ps)"
[ "$(wc -l <"$tmp/raw5")" = 202 ] && tail -1 "$tmp/raw5" | grep -qx FINAL \
  && ok 1 "an audit failure keeps the whole raw stream" || ok 0 "an audit failure keeps the whole raw stream"
HARNESS_HOME="$bh" python3 -c "
import importlib.util, sys
s = importlib.util.spec_from_file_location('c', '$HOME_DIR/agents/hooks/audit-log.py')
c = importlib.util.module_from_spec(s); s.loader.exec_module(c)
c.record('Bash', {'command': 'x'}); c.record('Bash', ['not', 'a', 'dict'])" 2>/dev/null \
  && ok 1 "record() never raises" || ok 0 "record() never raises"

# F38: rows carry $AGENT_NAME, and the ses_ prefix does not eat half the 8-char session.
f38() {
  printf '{"type":"tool_use","sessionID":"%s","part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"x"}}}}\n' "$2" \
    | HARNESS_HOME="$tmp/f38" AGENT_NAME=hello "$A/../$1/audit-from-stream" >/dev/null 2>&1
  tail -1 "$tmp/f38/log/actions.jsonl" 2>/dev/null
}
[ "$(f38 opencode ses_f842e3f3ffeAbCdEfGhIjKlMn | jq -r '.agent + " " + .session')" = "hello f842e3f3" ] \
  && ok 1 "opencode rows carry AGENT_NAME and the id after ses_" \
  || ok 0 "opencode rows carry AGENT_NAME and the id after ses_"
for s in codex gemini; do
  printf '{"type":"tool_call","name":"Bash","arguments":{"command":"x"}}\n' \
    | HARNESS_HOME="$tmp/f38" AGENT_NAME=hello "$A/../$s/audit-from-stream" >/dev/null 2>&1
  [ "$(tail -1 "$tmp/f38/log/actions.jsonl" 2>/dev/null | jq -r .agent)" = hello ] \
    && ok 1 "$s rows carry AGENT_NAME" || ok 0 "$s rows carry AGENT_NAME"
done

# F46: budget caps are gone fleet-wide, so the README must not list one as lost.
! grep -q -- '--max-budget-usd' "$A/README.md" \
  && ok 1 "README lists no budget cap as lost" || ok 0 "README lists no budget cap as lost"

# F37: SIGTERM to the adapter (the pid agents-stop kills) stops opencode too.
printf '#!/bin/sh\nexec sleep 47473\n' >"$tmp/oc-sleep"; chmod +x "$tmp/oc-sleep"
(OPENCODE_BIN="$tmp/oc-sleep" HARNESS_HOME="$tmp" PROMPT_FILE="$tmp/prompt.md" SYSTEM_FILE= MODEL= \
  AGENT_NAME= AGENT_TIMEOUT= RAW_OUT="$tmp/raw3.json" META_OUT="$tmp/meta3.json" exec "$A/run") >/dev/null 2>&1 &
ap=$!; sleep 1; kill -TERM "$ap"; wait "$ap" 2>/dev/null; sleep 0.3
left="$(pgrep -f '[s]leep 47473')"
[ -z "$left" ] && ok 1 "SIGTERM stops opencode" || { ok 0 "SIGTERM stops opencode ($left left)"; kill $left; }

[ "$bad" = 0 ] && echo "all opencode-adapter cases pass" || echo "$bad FAILURES"
exit $([ "$bad" = 0 ] && echo 0 || echo 1)
