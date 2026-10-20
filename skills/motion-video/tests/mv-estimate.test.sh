#!/usr/bin/env bash
# mv-estimate.test.sh: mv-estimate on fixture mv-build summaries in a mktemp ledger; fixtures are created here and deleted on exit.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts/mv-estimate
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-estimate-test.XXXXXX")
trap 'rm -rf "$FX"' EXIT
export CREATIVE_CI_LOG=$FX/creative-ci.jsonl
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
within() { awk -v a="$1" -v b="$2" -v p="$3" 'BEGIN{d=a-b; if (d<0) d=-d; exit !(d<=b*p/100)}' && echo 1 || echo 0; }
build() {  # project file draft seconds fps size cpu_s steps_json
  jq -n --argjson d "$3" --argjson s "$4" --argjson f "$5" --arg sz "$6" --argjson c "$7" --argjson st "$8" \
    '{name: "x", draft: $d, seconds: $s, fps: $f, size: $sz, steps_cpu: $st, cpu_s: $c}' >"$FX/$2.json"
  jq -nc --arg p "$1" --arg s "$FX/$2.json" '{tool: "mv-build", project: $p, ok: true, failed: [], summary: $s}' >>"$CREATIVE_CI_LOG"
}
build film a true 3 12 320x180 60 '{"beats": 2.0, "plate0": 8.0, "composite": 6.0, "encode": 1.0}'
build film b false 20 24 1920x1080 4000 '{"beats": 1.8, "plate0": 1100.0, "composite": 1250.0, "encode": 270.0}'
build solo c false 10 24 1280x720 500 '{"plate0": 300.0, "composite": 150.0}'
echo '{"tool": "mv-build", "project": "film", "summary": "/nonexistent.json"}' >>"$CREATIVE_CI_LOG"

ok "$([[ $("$BIN" --help 2>&1) == *--budget* ]] && echo 1 || echo 0)" "--help names --budget"
t=$("$BIN" "$FX/proj/film/" --seconds 20 --fps 24 --size 1920x1080 --json | jq -r .total)
ok "$(within "$t" 4000 1)" "2 builds: full build total $t within 1 % of 4000"
t=$("$BIN" film --draft --seconds 3 --fps 12 --size 320x180 --json | jq -r .total)
ok "$(within "$t" 60 1)" "2 builds: draft build total $t within 1 % of 60"
ok "$("$BIN" film --json | jq -r '[.steps[].basis] | all(startswith("2 builds"))' | grep -qx true && echo 1 || echo 0)" "2 builds: every step basis says 2 builds"
ok "$("$BIN" film --json | jq -r '.steps.unattributed.cpu > 0' | grep -qx true && echo 1 || echo 0)" "cpu_s minus the steps is an unattributed step"
j=$("$BIN" solo --seconds 20 --json)
ok "$(jq -r '[.steps[].basis] | all(. == "1 build, linear")' <<<"$j" | grep -qx true && echo 1 || echo 0)" "1 build: basis 1 build, linear"
ok "$(within "$(jq -r .total <<<"$j")" 1000 0.1)" "1 build: twice the seconds is twice the CPU"
"$BIN" solo --budget 400 >"$FX/out" 2>&1; rc=$?
ok "$([[ $rc == 1 ]] && grep -qx 'over budget: 500.0 > 400' "$FX/out" && echo 1 || echo 0)" "over budget: rc 1 and the line (rc $rc)"
"$BIN" solo --budget 600 >/dev/null 2>&1; rc=$?
ok "$([[ $rc == 0 ]] && echo 1 || echo 0)" "under budget: rc 0 (rc $rc)"
"$BIN" nothing-here >/dev/null 2>&1; rc=$?
ok "$([[ $rc == 2 ]] && echo 1 || echo 0)" "unknown project: rc 2 (rc $rc)"
"$BIN" film --size huge >/dev/null 2>&1; rc=$?
ok "$([[ $rc == 2 ]] && echo 1 || echo 0)" "bad --size: rc 2 (rc $rc)"
echo "mv-estimate: $((n - bad))/$n"
((bad == 0))
