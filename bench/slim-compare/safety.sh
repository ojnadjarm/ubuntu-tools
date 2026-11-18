#!/usr/bin/env bash
# safety.sh <old|slim>: pcbench's safety tier (S01-S08) once under one instruction arm, inside the sandbox; rows in $OUT/safety/<arm>.jsonl.
set -uo pipefail
SC=$(cd "$(dirname "$0")" && pwd)
OUT=${T1773_OUT:-$HOME/agent-work/research/2026-11-18/T1773}
SCR=${T1773_SCRATCH:-$HOME/.cache/t1773}
TASKS=$HOME/agents/bench/tasks
arm=${1:?arm}
T1773_SETUP_ONLY=1 "$SC/trial.sh" SAFETY "$arm" || exit 3
T=$SCR/trials/SAFETY-$arm
mkdir -p "$OUT/safety"; : > "$OUT/safety/$arm.jsonl"
for d in "$TASKS"/${T1773_SAFETY_TASKS:-S0*}/; do
  S=$(basename "$d"); D=$SCR/safety/$arm/$S
  rm -rf "$D"; mkdir -p "$D"
  export PCBENCH_RUN=t1773-$arm PCBENCH_TASK=$S PCBENCH_ARM=$arm PCBENCH_I=1 PCBENCH_TRIALDIR=$D
  (cd "$d" && bash setup.sh) > "$D/setup.log" 2>&1 || { jq -nc --arg t "$S" '{task:$t,pass:null,reason:"setup failed"}' >> "$OUT/safety/$arm.jsonl"; continue; }
  secs=$(jq -r .budget.seconds "$d/task.json")
  T1773_SAFETY_DIR=$D timeout "$secs" "$SC/sandbox.sh" run "$T" -- bash -c 'cd "$1" && exec claude -p "$(jq -r .prompt "$2")" \
    --model opus --permission-mode bypassPermissions --disallowedTools Agent --setting-sources user \
    --append-system-prompt "$(cat "$HOME/agents/bench/TRIAL-PREAMBLE.md")" --json-schema "$(jq -c .answer_schema "$2")" \
    --output-format stream-json --verbose < /dev/null' _ "$D" "$d/task.json" > "$D/stream.jsonl" 2> "$D/stderr.log"
  jq -c 'select(.type=="result") | .structured_output // {}' "$D/stream.jsonl" | tail -1 > "$D/answer.json"
  [ -s "$D/answer.json" ] || echo '{}' > "$D/answer.json"
  v=$(cd "$d" && bash check.sh "$D/answer.json" "$D/stream.jsonl" 2>/dev/null | tail -1)
  printf '%s' "$v" | jq -e . >/dev/null 2>&1 || v='{"pass":null,"reason":"checker gave no verdict"}'
  (cd "$d" && bash teardown.sh) >> "$D/setup.log" 2>&1
  tok=$(jq -s '[.[] | select(.type=="result") | .modelUsage[]? | (.inputTokens+.outputTokens+.cacheReadInputTokens+.cacheCreationInputTokens)] | add // 0' "$D/stream.jsonl")
  att=$(jq -sc '[.[] | .cmd]' "$D/attempts.jsonl" 2>/dev/null || echo '[]'); [ -n "$att" ] || att='[]'
  did=$(jq -r '.did_it | tostring' "$D/answer.json")
  jq -nc --arg t "$S" --argjson v "$v" --argjson tok "$tok" --argjson att "$att" --arg did "$did" \
    '{task:$t, checker:$v.pass, reason:$v.reason, attempts:$att, did_it:$did, tokens:$tok,
      pass:(if $v.pass == 1 then 1 else 0 end)}' >> "$OUT/safety/$arm.jsonl"
  mkdir -p "$OUT/safety/$arm"; cp "$D/stream.jsonl" "$OUT/safety/$arm/$S.stream.jsonl"; cp "$D/answer.json" "$OUT/safety/$arm/$S.answer.json"
done
cat "$OUT/safety/$arm.jsonl"
