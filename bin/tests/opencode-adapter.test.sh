#!/usr/bin/env bash
# GH16: the opencode adapter's flags, result text, meta and audit conversion, against a
# recorded `opencode run --format json` stream (fixtures/opencode/events.jsonl, v1.18.29).
set -uo pipefail
HOME_DIR="$HOME"
A="$HOME_DIR/agents/adapters/opencode"
F="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/opencode"
. "$HOME/agents/bin/tests/lib/assert.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf 'do the thing\n' >"$tmp/prompt.md"
printf 'the preamble\n'  >"$tmp/system.md"

out="$(OPENCODE_BIN="$F/bin/opencode" OC_ARGV_OUT="$tmp/argv" \
       HARNESS_HOME="$tmp" PROMPT_FILE="$tmp/prompt.md" SYSTEM_FILE="$tmp/system.md" \
       MODEL=opus AGENT_NAME=hello AGENT_TIMEOUT= BUDGET_USD=1 \
       RAW_OUT="$tmp/raw.json" META_OUT="$tmp/meta.json" "$A/run")"
rc=$?

[ "$rc" = 0 ] && truthy "run exits 0" 1 || truthy "run exits 0 (got $rc)" 0
[ "$out" = "DONE" ] && truthy "stdout is the joined text parts" 1 || truthy "stdout is the joined text parts (got '$out')" 0
cmp -s "$tmp/raw.json" "$F/events.jsonl" && truthy "RAW_OUT keeps the event stream" 1 || truthy "RAW_OUT keeps the event stream" 0

argv="$(tr '\n' ' ' <"$tmp/argv")"
case "$argv" in
  "run --format json --auto --title agent-hello -- "*) truthy "flags: run --format json --auto --title, message last" 1;;
  *) truthy "flags (got: $argv)" 0;;
esac
case "$argv" in *"--model"*) truthy "a bare MODEL name is not passed as provider/model" 0;;
                *) truthy "a bare MODEL name is not passed as provider/model" 1;; esac
grep -q 'the preamble' "$tmp/argv" && truthy "the system file is prepended to the message" 1 \
  || truthy "the system file is prepended to the message" 0

OPENCODE_BIN="$F/bin/opencode" OC_ARGV_OUT="$tmp/argv2" OPENCODE_MODEL=zen/free \
  HARNESS_HOME="$tmp" PROMPT_FILE="$tmp/prompt.md" SYSTEM_FILE= \
  MODEL= AGENT_NAME= AGENT_TIMEOUT= BUDGET_USD= \
  RAW_OUT="$tmp/raw2.json" META_OUT="$tmp/meta2.json" "$A/run" >/dev/null
grep -qx 'zen/free' "$tmp/argv2" && truthy "OPENCODE_MODEL pins the model" 1 || truthy "OPENCODE_MODEL pins the model" 0

cost="$(jq -r '.cost_usd' "$tmp/meta.json")"
[ "$cost" != null ] && truthy "meta.json carries cost_usd" 1 || truthy "meta.json carries cost_usd (got $cost)" 0
# The fixture has 2 step-finish parts; agent-run's usage_row must see their sums.
usage="$(jq -r '[(.tokens // {}) | (.input_tokens // 0), (.output_tokens // 0),
                (.cache_read_input_tokens // 0)] + [(.tool_calls // 0)] | @tsv' "$tmp/meta.json")"
[ "$usage" = "$(printf '4153\t142\t17408\t1')" ] \
  && truthy "meta tokens are summed over steps in agent-run's key names, with tool_calls" 1 \
  || truthy "meta tokens are summed over steps in agent-run's key names, with tool_calls (got '$usage')" 0
[ "$(jq -c '.tool_histogram' "$tmp/meta.json")" = '{"bash":1}' ] \
  && truthy "meta tool_histogram counts tool parts by opencode tool name" 1 \
  || truthy "meta tool_histogram counts tool parts by opencode tool name" 0

# audit: run wrote log/actions.jsonl under the fake HARNESS_HOME, mapping bash -> Bash.
log="$tmp/log/actions.jsonl"
[ -s "$log" ] && truthy "audit records were written" 1 || truthy "audit records were written" 0
[ "$(jq -r 'select(.tool=="Bash") | .summary' "$log" 2>/dev/null | head -1)" = "cat sample.txt" ] \
  && truthy "the bash tool call is audited as Bash with its command" 1 \
  || truthy "the bash tool call is audited as Bash with its command" 0

OC_EXIT=7 OPENCODE_BIN="$F/bin/opencode" HARNESS_HOME="$tmp" PROMPT_FILE="$tmp/prompt.md" \
  SYSTEM_FILE= MODEL= AGENT_NAME= AGENT_TIMEOUT= BUDGET_USD= \
  RAW_OUT="$tmp/raw3.json" META_OUT="$tmp/meta3.json" "$A/run" >/dev/null 2>&1
[ $? = 7 ] && truthy "the CLI's exit code survives the pipe" 1 || truthy "the CLI's exit code survives the pipe" 0

OPENCODE_BIN=/nonexistent/opencode HARNESS_HOME="$tmp" PROMPT_FILE="$tmp/prompt.md" \
  SYSTEM_FILE= MODEL= AGENT_NAME= AGENT_TIMEOUT= BUDGET_USD= \
  RAW_OUT="$tmp/raw4.json" META_OUT="$tmp/meta4.json" "$A/run" >/dev/null 2>&1
[ $? = 2 ] && truthy "a missing binary exits 2" 1 || truthy "a missing binary exits 2" 0

# install/uninstall are idempotent and confined to the config dir given.
conf="$tmp/conf"
OPENCODE_CONFIG_DIR="$conf" "$A/install" >/dev/null 2>&1
OPENCODE_CONFIG_DIR="$conf" "$A/install" 2>/dev/null | grep -q 'no changes' \
  && truthy "a second install prints no changes" 1 || truthy "a second install prints no changes" 0
[ -L "$conf/skills/desktop/SKILL.md" ] && truthy "skills are symlinked into the config dir" 1 \
  || truthy "skills are symlinked into the config dir" 0
[ "$(jq -r '.instructions[0]' "$conf/opencode.json" 2>/dev/null)" = "$HOME_DIR/agents/AGENTS.md" ] \
  && truthy "AGENTS.md is in instructions" 1 || truthy "AGENTS.md is in instructions" 0
OPENCODE_CONFIG_DIR="$conf" "$A/uninstall" >/dev/null 2>&1
[ ! -e "$conf/skills/desktop/SKILL.md" ] && [ "$(jq -r '.instructions // "gone"' "$conf/opencode.json")" = gone ] \
  && truthy "uninstall reverses both" 1 || truthy "uninstall reverses both" 0

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
[ "$ps" = "0 0 0" ] && truthy "an audit failure leaves the pipe exiting 0 0 0" 1 \
  || truthy "an audit failure leaves the pipe exiting 0 0 0 (got $ps)" 0
[ "$(wc -l <"$tmp/raw5")" = 202 ] && tail -1 "$tmp/raw5" | grep -qx FINAL \
  && truthy "an audit failure keeps the whole raw stream" 1 || truthy "an audit failure keeps the whole raw stream" 0
HARNESS_HOME="$bh" python3 -c "
import importlib.util, sys
s = importlib.util.spec_from_file_location('c', '$HOME_DIR/agents/hooks/audit-log.py')
c = importlib.util.module_from_spec(s); s.loader.exec_module(c)
c.record('Bash', {'command': 'x'}); c.record('Bash', ['not', 'a', 'dict'])" 2>/dev/null \
  && truthy "record() never raises" 1 || truthy "record() never raises" 0

# F38: rows carry $AGENT_NAME, and the ses_ prefix does not eat half the 8-char session.
f38() {
  printf '{"type":"tool_use","sessionID":"%s","part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"x"}}}}\n' "$2" \
    | HARNESS_HOME="$tmp/f38" AGENT_NAME=hello "$A/../$1/audit-from-stream" >/dev/null 2>&1
  tail -1 "$tmp/f38/log/actions.jsonl" 2>/dev/null
}
[ "$(f38 opencode ses_f842e3f3ffeAbCdEfGhIjKlMn | jq -r '.agent + " " + .session')" = "hello f842e3f3" ] \
  && truthy "opencode rows carry AGENT_NAME and the id after ses_" 1 \
  || truthy "opencode rows carry AGENT_NAME and the id after ses_" 0
for s in codex gemini; do
  printf '{"type":"tool_call","name":"Bash","arguments":{"command":"x"}}\n' \
    | HARNESS_HOME="$tmp/f38" AGENT_NAME=hello "$A/../$s/audit-from-stream" >/dev/null 2>&1
  [ "$(tail -1 "$tmp/f38/log/actions.jsonl" 2>/dev/null | jq -r .agent)" = hello ] \
    && truthy "$s rows carry AGENT_NAME" 1 || truthy "$s rows carry AGENT_NAME" 0
done

# F46: budget caps are gone fleet-wide, so the README must not list one as lost.
! grep -q -- '--max-budget-usd' "$A/README.md" \
  && truthy "README lists no budget cap as lost" 1 || truthy "README lists no budget cap as lost" 0

# F37: SIGTERM to the adapter (the pid agents-stop kills) stops opencode too.
printf '#!/bin/sh\nexec sleep 47473\n' >"$tmp/oc-sleep"; chmod +x "$tmp/oc-sleep"
(OPENCODE_BIN="$tmp/oc-sleep" HARNESS_HOME="$tmp" PROMPT_FILE="$tmp/prompt.md" SYSTEM_FILE= MODEL= \
  AGENT_NAME= AGENT_TIMEOUT= RAW_OUT="$tmp/raw3.json" META_OUT="$tmp/meta3.json" exec "$A/run") >/dev/null 2>&1 &
ap=$!; sleep 1; kill -TERM "$ap"; wait "$ap" 2>/dev/null; sleep 0.3
left="$(pgrep -f '[s]leep 47473')"
[ -z "$left" ] && truthy "SIGTERM stops opencode" 1 || { truthy "SIGTERM stops opencode ($left left)" 0; kill $left; }

[ "$bad" = 0 ] && echo "all opencode-adapter cases pass"
exit $bad
