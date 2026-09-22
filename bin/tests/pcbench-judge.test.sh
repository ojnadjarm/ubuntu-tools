#!/usr/bin/env bash
# PB10: the LLM judge for open-answer tasks. Every case runs against a stubbed `claude` on
# PATH that replays a canned verdict — no model is ever contacted (AGENTS.md §5.6). The stub
# records every invocation and each case asserts the stub was hit before it reads the verdict.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JUDGE="$BIN/pcbench.d/judge.sh"
PB="$BIN/pcbench"
TASKS="$HOME/agents/bench/tasks"
fail=0
t() { printf '%-56s' "judge: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }
eq() { [ "$2" = "$3" ] && ok || no "$1: got $2, want $3"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STUBDIR="$TMP/bin"; mkdir -p "$STUBDIR"
export PCBENCH_STUB_LOG="$TMP/claude.calls"
export PCBENCH_STUB_OUT="$TMP/claude.out"
export PCBENCH_STUB_RC=0

cat > "$STUBDIR/claude" <<'STUB'
#!/usr/bin/env bash
# Stubbed `claude` for the judge tests: records the call, replays a canned reply, never
# reaches a model. $PCBENCH_STUB_OUT is the reply, $PCBENCH_STUB_RC the exit status.
{ echo CALL; printf '%s\n' "$*"; } >> "${PCBENCH_STUB_LOG:?}"
[ "${PCBENCH_STUB_RC:-0}" = 0 ] || exit "${PCBENCH_STUB_RC}"
cat "${PCBENCH_STUB_OUT:?}"
STUB
chmod +x "$STUBDIR/claude"
export PATH="$STUBDIR:$PATH"

reply() { printf '%s' "$1" > "$PCBENCH_STUB_OUT"; }
verdict_json() { jq -nc --argjson v "$1" '{type:"result",subtype:"success",structured_output:$v}'; }
calls() { [ -f "$PCBENCH_STUB_LOG" ] || { echo 0; return; }; grep -c '^CALL$' "$PCBENCH_STUB_LOG"; }
runjudge() { : > "$PCBENCH_STUB_LOG"; bash "$JUDGE" "$@"; }

# --- 0. the sandbox itself: the stub is what `claude` resolves to ------------
t "the stub is the claude on PATH"
[ "$(command -v claude)" = "$STUBDIR/claude" ] && ok || no "claude resolves to $(command -v claude)"
t "no real model is reachable from the stub"
grep -q 'replays a canned reply' "$STUBDIR/claude" && ! grep -q 'api[.]anthropic' "$STUBDIR/claude" && ok \
  || no "the stub is not the canned-reply stub"

# --- 1. a task with a rubric, judge says pass -------------------------------
printf '%s' '{"sink":"alsa_output.pci-0000_00_1f.3.hdmi-stereo","is_buds":false}' > "$TMP/a.json"
reply "$(verdict_json '{"pass":true,"reasons":["raw sink name, is_buds agrees"]}')"
out=$(runjudge "$TASKS/O02" "$TMP/a.json"); rc=$?
t "O02 pass: the stub was called";  eq n "$(calls)" '1'
t "O02 pass: verdict";              eq v "$(echo "$out" | jq -c '.pass')" '1'
t "O02 pass: exit 0";               eq rc "$rc" '0'
t "the prompt carried the rubric";  grep -q 'raw sink name the audio server prints' "$PCBENCH_STUB_LOG" && ok || no "rubric missing from the call"
t "the judge runs with no tools";   grep -q -- '--restricted' "$PCBENCH_STUB_LOG" && ok || no "--restricted not passed"

# --- 2. judge says fail -----------------------------------------------------
reply "$(verdict_json '{"pass":false,"reasons":["sink is a prose description"]}')"
out=$(runjudge "$TASKS/O02" "$TMP/a.json"); rc=$?
t "fail: the stub was called";      eq n "$(calls)" '1'
t "fail: pass=0";                   eq v "$(echo "$out" | jq -c '.pass')" '0'
t "fail: the reason is carried";    eq r "$(echo "$out" | jq -r '.reasons[0]')" 'sink is a prose description'
t "fail: exit 0 (graded, not broken)"; eq rc "$rc" '0'

# --- 3. plain text reply (no structured output) is still parsed -------------
reply '{"type":"result","subtype":"success","result":"Here is my verdict:\n{\"pass\": true, \"reasons\": [\"holds\"]}\n"}'
out=$(runjudge "$TASKS/D02" "$TMP/a.json")
t "text reply: the stub was called"; eq n "$(calls)" '1'
t "text reply: parsed";              eq v "$(echo "$out" | jq -c '[.pass,(.reasons|length)]')" '[1,1]'

# --- 4. a task with no rubric is skipped, without calling the model ---------
: > "$PCBENCH_STUB_LOG"
out=$(bash "$JUDGE" "$TASKS/O01" "$TMP/a.json"); rc=$?
t "no rubric: skipped";             eq s "$(echo "$out" | jq -c '.skipped')" 'true'
t "no rubric: no model call";       eq n "$(calls)" '0'
t "no rubric: exit 0";              eq rc "$rc" '0'

# --- 5. a broken judge fails the answer, it never passes it silently --------
export PCBENCH_STUB_RC=1
out=$(runjudge "$TASKS/O02" "$TMP/a.json"); rc=$?
export PCBENCH_STUB_RC=0
t "claude failed: pass=0";          eq v "$(echo "$out" | jq -c '.pass')" '0'
t "claude failed: reason says so";  case $(echo "$out" | jq -r '.reasons[0]') in "judge error:"*) ok;; *) no "$out";; esac
t "claude failed: exit 2";          eq rc "$rc" '2'

reply 'I could not decide, sorry.'
out=$(runjudge "$TASKS/O02" "$TMP/a.json"); rc=$?
t "no JSON in the reply: pass=0";   eq v "$(echo "$out" | jq -c '.pass')" '0'
t "no JSON in the reply: exit 2";   eq rc "$rc" '2'

reply "$(verdict_json '{"pass":true,"reasons":["fine"]}')"
out=$(runjudge "$TASKS/O02" "$TMP/missing.json"); rc=$?
t "missing answer: pass=0";         eq v "$(echo "$out" | jq -c '.pass')" '0'
t "missing answer: no model call";  eq n "$(calls)" '0'

# --- 6. pcbench's side: run_judge maps the verdict onto the row -------------
reply "$(verdict_json '{"pass":false,"reasons":["no health check named"]}')"
: > "$PCBENCH_STUB_LOG"
py=$(PCBENCH_PB="$PB" python3 - "$TASKS/D02" "$TMP/a.json" <<'PY'
import json, os, sys
from importlib.machinery import SourceFileLoader
pb = SourceFileLoader("pcbench", os.environ["PCBENCH_PB"]).load_module()
print(json.dumps(pb.run_judge(sys.argv[1], sys.argv[2], dict(os.environ))))
PY
)
t "run_judge: the stub was called";  eq n "$(calls)" '1'
t "run_judge: row fields";           eq f "$(echo "$py" | jq -c '[.judge_pass,.judge_reasons[0]]')" '[0,"no health check named"]'
: > "$PCBENCH_STUB_LOG"
py=$(PCBENCH_PB="$PB" python3 - "$TASKS/O01" "$TMP/a.json" <<'PY'
import json, os, sys
from importlib.machinery import SourceFileLoader
pb = SourceFileLoader("pcbench", os.environ["PCBENCH_PB"]).load_module()
print(json.dumps(pb.run_judge(sys.argv[1], sys.argv[2], dict(os.environ))))
PY
)
t "run_judge: no rubric adds nothing"; eq e "$py" '{}'

# --- 7. the trial's verdict is checker AND judge ----------------------------
t "run_trial ANDs the checker with the judge"
if grep -q 'checker_ok = 1 if task.get("judge_only") else verdict\["pass"\]' "$PB" &&
   grep -q 'row\["pass"\] = 1 if (checker_ok and j\["judge_pass"\]) else 0' "$PB"; then ok
else no "pcbench no longer composes pass = checker AND judge"; fi

# --- 8. every judge block in the pack validates -----------------------------
for tid in O02 D02 D04 D05; do
  t "$tid declares a judge rubric"
  jq -e '.judge.rubric and (.judge.must|length>0) and (.judge.must_not|length>0)' \
     "$TASKS/$tid/task.json" >/dev/null 2>&1 && ok || no "$tid judge block is incomplete"
done
t "validate rejects a judge with no rubric"
FAKE="$TMP/tasks/O02"; mkdir -p "$FAKE"; cp "$TASKS/O02"/*.sh "$FAKE/"
jq '.judge = {"must":["x"]}' "$TASKS/O02/task.json" > "$FAKE/task.json"
py=$(PCBENCH_PB="$PB" PCBENCH_FAKE_TASKS="$TMP/tasks" python3 - <<'PYV'
import json, os
from importlib.machinery import SourceFileLoader
pb = SourceFileLoader("pcbench", os.environ["PCBENCH_PB"]).load_module()
pb.TASKS = os.environ["PCBENCH_FAKE_TASKS"]
print(json.dumps(pb.validate_task("O02")))
PYV
)
case $py in *rubric*) ok;; *) no "validate_task said $py";; esac
t "validate still accepts the shipped judge tasks"
out=$("$PB" validate --task O02 --task D02 --task D04 --task D05 2>&1)
case $out in *FAIL*) no "$(echo "$out" | tr '\n' ' ')";; *) ok;; esac

[ $fail = 0 ] && echo "pcbench-judge.test.sh: all green" || echo "pcbench-judge.test.sh: FAILURES"
exit $fail
