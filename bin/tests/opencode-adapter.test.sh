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

cost="$(jq -r '.cost_usd' "$tmp/meta.json")"; tin="$(jq -r '.tokens.input' "$tmp/meta.json")"
[ "$cost" != null ] && [ "$tin" != null ] && ok 1 "meta.json carries cost_usd and tokens" \
  || ok 0 "meta.json carries cost_usd and tokens (cost=$cost input=$tin)"

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

[ "$bad" = 0 ] && echo "all opencode-adapter cases pass" || echo "$bad FAILURES"
exit $([ "$bad" = 0 ] && echo 0 || echo 1)
