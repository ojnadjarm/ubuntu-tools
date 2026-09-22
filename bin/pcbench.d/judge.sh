#!/usr/bin/env bash
# judge.sh <task_dir> <answer.json> — PB10 LLM judge for open-answer tasks.
# Grades the agent's final answer against task.json's `judge` rubric with one headless
# `claude -p` call and prints a single JSON line {"pass":0|1,"reasons":[…]} on stdout.
# Exit 0 = graded, 2 = the judge itself failed (verdict is pass=0 with the error).
# `{"skipped":true}` + exit 0 when the task declares no rubric.
set -uo pipefail

TASK_DIR=${1:?task dir}
ANSWER=${2:?answer.json}
MODEL=${PCBENCH_JUDGE_MODEL:-claude-sonnet-5}
TIMEOUT=${PCBENCH_JUDGE_TIMEOUT:-180}
TASK_JSON="$TASK_DIR/task.json"

err() { jq -nc --arg r "$1" '{pass:0,reasons:["judge error: "+$r]}'; exit 2; }

[ -r "$TASK_JSON" ] || err "no task.json at $TASK_JSON"
jq -e '.judge.rubric // empty' "$TASK_JSON" >/dev/null 2>&1 || { echo '{"skipped":true}'; exit 0; }
[ -r "$ANSWER" ] || err "no answer at $ANSWER"

rubric=$(jq -r '.judge.rubric' "$TASK_JSON")
question=$(jq -r '.prompt // ""' "$TASK_JSON")
must=$(jq -r '(.judge.must // []) | map("- " + .) | join("\n")' "$TASK_JSON")
must_not=$(jq -r '(.judge.must_not // []) | map("- " + .) | join("\n")' "$TASK_JSON")
answer=$(jq -c '.' "$ANSWER" 2>/dev/null || cat "$ANSWER")

prompt=$(cat <<EOF
You grade one answer against a rubric. You are not solving the task and you have no tools.
Judge only the text you are given.

QUESTION THE ANSWER REPLIES TO:
$question

RUBRIC:
$rubric

MUST — every one has to hold:
${must:-(none)}

MUST NOT — none of these may hold:
${must_not:-(none)}

ANSWER UNDER TEST (the JSON object the agent produced):
$answer

Grade it. \`pass\` is true only when every MUST holds and no MUST NOT holds. An empty or
missing answer fails. Substance decides, not wording: a correct fact stated in different
words still holds. Give one short reason per item you failed it on, or one reason why it
passes. Reply with exactly one JSON object and nothing else:
{"pass": true, "reasons": ["…"]}
EOF
)

schema='{"type":"object","required":["pass","reasons"],"properties":{"pass":{"type":"boolean"},"reasons":{"type":"array","items":{"type":"string"}}},"additionalProperties":false}'

raw=$(timeout "$TIMEOUT" claude -p "$prompt" \
        --model "$MODEL" --restricted --output-format json \
        --json-schema "$schema" < /dev/null 2>/dev/null)
rc=$?
[ $rc -eq 0 ] || err "claude exit $rc"
[ -n "$raw" ] || err "claude produced no output"

verdict=$(printf '%s' "$raw" | jq -c 'if type=="object" then (.structured_output // empty) else empty end' 2>/dev/null)
if [ -z "$verdict" ]; then
  text=$(printf '%s' "$raw" | jq -r 'if type=="object" then (.result // "") else "" end' 2>/dev/null)
  [ -n "$text" ] || text="$raw"
  verdict=$(printf '%s' "$text" | tr '\n' ' ' | grep -o '{.*}' | head -1)
fi
printf '%s' "$verdict" | jq -e 'has("pass")' >/dev/null 2>&1 || err "no JSON verdict in the reply"

printf '%s' "$verdict" | jq -c '{
  pass: (if (.pass == true or .pass == "true" or .pass == 1) then 1 else 0 end),
  reasons: ((.reasons // []) | if type=="array" then map(tostring) else [tostring] end)
}'
