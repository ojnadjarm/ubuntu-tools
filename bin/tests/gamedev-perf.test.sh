#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # ok() evals its single-quoted checks
# T520/T548/T617/T687/T744/T786/T857/T902/T949: gamedev-perf maps a stub perfgate's and a stub cpp-ci's pass/skip/regress to rc 0/0/1 (cpp culprit pass named), fetches assets once, locks out a second run, discards rows on a mid-run load spike, CPU pressure peak or GPU client, skips while the GPU is busy, checks each cpp pass against perf-budgets.json (line, csv column, red creative-ci row, rc unchanged), counts timing-gate skip rows (--skips), compares two runs per pass (--compare), shows per-pass drift over the last rows (--trend) and its edge cases (extra fields, missing or non-object budgets, NaN, WARN after the pass lines).
set -uo pipefail
BIN="$HOME/agents/bin/gamedev-perf"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/slice/scripts"
echo 'main' >"$W/slice/scripts/main.gd"
printf '#!/bin/sh\necho fetched >>"%s/assets.calls"\nmkdir -p "$(dirname "$0")/assets"\n' "$W" >"$W/slice/assets.sh"
cat >"$W/perfgate" <<'EOF'
#!/bin/sh
while [ $# -gt 1 ]; do [ "$1" = --csv ] && csv=$2; shift; done
echo "args $csv $1" >>"$STUB_LOG"
if [ -n "${STUB_HOLD:-}" ]; then touch "$STUB_HOLD.started"; while [ ! -e "$STUB_HOLD.release" ]; do sleep 0.1; done; fi
[ -n "${STUB_SPIKE:-}" ] && echo "20.00 18.00 9.00 3/900 1" >"$GAMEDEV_LOADAVG"
[ -n "${STUB_PSI:-}" ] && echo "some avg10=$STUB_PSI avg60=5.00 avg300=2.00 total=1" >"$GAMEDEV_PSI"
[ -n "${STUB_GPU:-}" ] && cp -r "$GPU_BUSY/." "$QUIET_FDINFO/"
case $STUB_RC in
  0) echo "row" >>"$csv"; echo "PERFGATE PASS median_fps=100" ;;
  1) echo "row" >>"$csv"; echo "PERFGATE FAIL median_fps=50 < floor=90" ;;
  3) echo "PERFGATE SKIP load1=15 >= 8: numbers would be noise" ;;
esac
exit "$STUB_RC"
EOF
chmod +x "$W/slice/assets.sh" "$W/perfgate"
export GAMEDEV_PERFGATE="$W/perfgate" GAMEDEV_SLICE="$W/slice" GAMEDEV_PERF_DIR="$W/state" STUB_LOG="$W/gate.log" \
	GAMEDEV_LOADAVG="$W/loadavg" GAMEDEV_PSI="$W/psi" GAMEDEV_LOAD_EVERY=0.1 GAMEDEV_GPU_EVERY=0.1 QUIET_FDINFO="$W/fd" GPU_BUSY="$W/fd-busy"
# stub cpp-ci: STUB_CPP pass|regress|skip|buildfail; logs stages|out|project|sources|seeded csv lines; perf appends a cpp row like cpp-ci
mkdir -p "$W/tpl/src"; echo 'int main() {}' >"$W/tpl/src/main.cpp"
cat >"$W/cppci" <<'EOF'
#!/bin/sh
while [ $# -gt 1 ]; do case $1 in --out) out=$2; shift ;; --stages) stages=$2; shift ;; esac; shift; done
echo "$stages|$out|$1|$(ls "$1/src")|$(grep -c ,cpp, "$out/perf.csv" 2>/dev/null)" >>"$STUB_CPPLOG"
case $stages in *perf*) ;; *) [ "${STUB_CPP:-pass}" = buildfail ] && exit 1; exit 0 ;; esac
hdr=date,project,frames,avg_fps,load1,gpu_ms_p50,gpu_ms_p99,cpu_ms_p50,bound,status,vram_used_mb,vram_budget_mb,draws,culled,post_ms_p50,gpu_ms_p50_shadow,gpu_ms_p50_scene,gpu_ms_p50_skin
[ "$(head -1 "$out/perf.csv" 2>/dev/null)" = "$hdr" ] || { [ -f "$out/perf.csv" ] && mv "$out/perf.csv" "$out/perf.old.csv"; echo "$hdr" >"$out/perf.csv"; }
case ${STUB_CPP:-pass} in
  pass) echo "$(date +%s%N),cpp,600,120,0.5,4.0,5.0,3.0,gpu,pass,300,4000,10,2,1.0,1.5,1.2,0.3" >>"$out/perf.csv"
    echo '{"stages":{"perf":{"status":"pass","avg_fps":120,"gpu_ms_p50":4.0,"vram_used_mb":300}}}' >"$out/summary.json" ;;
  regress) echo "$(date +%s%N),cpp,600,90,0.5,6.0,7.0,3.0,gpu,fail,300,4000,10,2,1.0,3.5,1.2,0.3" >>"$out/perf.csv"
    echo '{"stages":{"perf":{"status":"fail","avg_fps":90,"gpu_ms_p50":6.0,"baseline_gpu_ms_p50":4.0,"delta_pct":50.0,"culprit":{"pass":"shadow","delta_ms":2.0}}}}' >"$out/summary.json"; exit 1 ;;
  skip) echo "$(date +%s%N),cpp,600,,0.5,,,,,skip,,,,,,,," >>"$out/perf.csv"
    echo '{"stages":{"perf":{"status":"skip","reason":"load","load1":9}}}' >"$out/summary.json" ;;
esac
EOF
chmod +x "$W/cppci"
# fixture budgets above the stub's pass row (post 1.0, shadow 1.5, scene 1.2, skin 0.3, frame 4.0); the ledger goes to the sandbox
budgets() { jq -n --argjson s "$1" '{resolution: "1280x720", post: {col: "post_ms_p50", ms: 2}, shadow: {col: "gpu_ms_p50_shadow", ms: 2},
	scene: {col: "gpu_ms_p50_scene", ms: 2}, skin: {col: "gpu_ms_p50_skin", ms: $s}, frame: {col: "gpu_ms_p50", ms: 5}}' >"$W/budgets.json"; }
budgets 1
export GAMEDEV_CPPCI="$W/cppci" GAMEDEV_CPP_TEMPLATE="$W/tpl" STUB_CPPLOG="$W/cpp.log" GAMEDEV_PERF_BUDGETS="$W/budgets.json" CREATIVE_CI_LOG="$W/ci.jsonl"
# /proc-shaped GPU snapshots a/ and b/ (1 s apart) of one blender client: idle 0 %, busy 40 % (T617).
gpufix() { for s in a b; do mkdir -p "$1/$s/200/fdinfo"; printf 'Name:\tblender\nPPid:\t1\nUid:\t%s\n' "$(id -u)" >"$1/$s/200/status"; done
	printf 'drm-client-id:\t7\ndrm-engine-render:\t1000000000 ns\n' >"$1/a/200/fdinfo/3"; printf 'drm-client-id:\t7\ndrm-engine-render:\t%s ns\n' "$2" >"$1/b/200/fdinfo/3"; }
gpufix "$W/fd-busy" 1400000000
gpuidle() { rm -rf "$W/fd"; gpufix "$W/fd" 1000000000; }
gpuidle
quiet() { echo "0.50 0.40 0.30 1/900 1" >"$W/loadavg"; echo "some avg10=1.50 avg60=1.00 avg300=0.50 total=1" >"$W/psi"; }
quiet

pass=0 fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi; }
run() { STUB_RC=$1 "$BIN" --collect >"$W/out" 2>&1; echo $? >"$W/rc"; }

run 0
ok "pass -> rc 0" '[ "$(cat "$W/rc")" = 0 ]'
ok "pass appends a csv row" '[ "$(wc -l <"$W/state/perf.csv")" = 1 ]'
ok "slice copied to a per-run dir, kept as last" '[ -f "$W/state/last/scripts/main.gd" ] && [ -d "$W/state/last/assets" ]'
ok "gate gets the per-run dir and its csv copy" 'grep -Eqx "args $W/state/runs/[0-9]+/work/perf.csv $W/state/runs/[0-9]+/work" "$W/gate.log"'
run 3
ok "skip -> rc 0" '[ "$(cat "$W/rc")" = 0 ]'
ok "skip prints a skip line" 'grep -q "^skip " "$W/out"'
run 1
ok "regress -> rc 1" '[ "$(cat "$W/rc")" = 1 ]'
ok "assets fetched once over 3 runs" '[ "$(wc -l <"$W/assets.calls")" = 1 ]'
crows() { grep -c ",cpp," "$W/state/perf-cpp.csv"; }
c=$(crows)
sed -i 's/,[^,]*$//' "$W/state/perf-cpp.csv"  # a pre-T744 csv: no budget column
STUB_RC=0 "$BIN" --collect >"$W/out" 2>&1; rc=$?
ok "cpp: pass -> rc 0, one cpp row" '[ $rc = 0 ] && grep -q "^cpp perf pass gpu_ms_p50=4" "$W/out" && [ "$(crows)" = $((c + 1)) ]'
ok "T744 budget: under budget -> budget=ok on the line, trailing csv column, old rows empty, no ledger row" \
	'grep -q " budget=ok$" "$W/out" && head -1 "$W/state/perf-cpp.csv" | grep -q ",gpu_ms_p50_skin,budget$" && tail -1 "$W/state/perf-cpp.csv" | grep -q ",0.3,ok$" \
	&& [ "$(grep -c ",cpp,.*,$" "$W/state/perf-cpp.csv")" = "$c" ] && [ ! -s "$W/ci.jsonl" ]'
budgets 0.2; STUB_RC=0 "$BIN" --collect >"$W/out" 2>&1; rc=$?; budgets 1
ok "T744 budget: skin over -> rc 0, over:skin on the line and csv, earlier rows keep theirs" \
	'[ $rc = 0 ] && grep -q " budget=over:skin=0.3/0.2$" "$W/out" && tail -1 "$W/state/perf-cpp.csv" | grep -q ",over:skin=0.3/0.2$" \
	&& tail -2 "$W/state/perf-cpp.csv" | head -1 | grep -q ",ok$" && [ "$(crows)" = $((c + 2)) ]'
ok "T744 budget: over -> one red creative-ci row naming the pass" 'jq -e -s "length == 1 and .[0].tool == \"gamedev-perf\" and .[0].ok == false and .[0].failed == [\"skin\"]" "$W/ci.jsonl" >/dev/null'
ok "T744 budget: cpp-ci is seeded without the budget column (history kept)" '[ "$(tail -1 "$W/cpp.log" | cut -d"|" -f5)" = $((c + 1)) ]'
c=$((c + 1))
ok "cpp: build first, then configure build perf, on a per-run template copy" 'tail -2 "$W/cpp.log" | cut -d"|" -f1,3,4 | tr "\n" ";" | grep -Eqx "configure build\|$W/state/runs/[0-9]+/cpp\|main.cpp;configure build perf\|$W/state/runs/[0-9]+/cpp\|main.cpp;"'
ok "cpp: per-run dirs removed, cpp-ci out kept as last-cpp-ci" '[ -z "$(ls "$W/state/runs")" ] && [ -f "$W/state/last-cpp-ci/summary.json" ]'
STUB_RC=0 STUB_CPP=regress "$BIN" --collect >"$W/out" 2>&1; rc=$?
ok "cpp: regression -> rc 1" '[ $rc = 1 ]'
ok "cpp: regression names the culprit pass" 'grep -q "^cpp perf fail gpu_ms_p50=6.0 baseline=4.0 delta_pct=50.0 culprit pass=shadow delta_ms=2.0" "$W/out"'
ok "cpp: history seeded into cpp-ci, fail row kept" '[ "$(tail -1 "$W/cpp.log" | cut -d"|" -f5)" = $((c + 1)) ] && [ "$(crows)" = $((c + 2)) ]'
ok "T744 budget: regression over budget keeps rc 1, two passes named, a second red row" '[ $rc = 1 ] && grep -q "culprit pass=shadow delta_ms=2.0 budget=over:shadow=3.5/2+frame=6.0/5$" "$W/out" \
	&& [ ! -e "$W/state/perf-cpp.csv.new" ] && jq -e -s "length == 2 and .[1].failed == [\"shadow\", \"frame\"]" "$W/ci.jsonl" >/dev/null'
STUB_RC=0 STUB_CPP=skip "$BIN" --collect >"$W/out" 2>&1; rc=$?
ok "cpp: busy -> rc 0, skip line, no cpp row" '[ $rc = 0 ] && grep -q "^skip cpp perf load, no cpp row" "$W/out" && [ "$(crows)" = $((c + 2)) ]'
n=$(grep -c . "$W/cpp.log")
STUB_RC=0 STUB_CPP=buildfail "$BIN" --collect >"$W/out" 2>&1; rc=$?
ok "cpp: build fail -> rc 1, perf not run" '[ $rc = 1 ] && grep -q "^cpp build failed" "$W/out" && [ "$(grep -c . "$W/cpp.log")" = $((n + 1)) ]'
rows=$(wc -l <"$W/state/perf.csv")
STUB_RC=0 STUB_SPIKE=1 "$BIN" --collect >"$W/out" 2>&1; rc=$?; quiet
ok "mid-run load spike -> rc 0" '[ $rc = 0 ]'
ok "mid-run load spike prints a skip line" 'grep -q "^skip load1 peaked at 20.00" "$W/out"'
ok "mid-run load spike writes 0 rows" '[ "$(wc -l <"$W/state/perf.csv")" = "$rows" ] && [ "$(crows)" = $((c + 2)) ]'
STUB_RC=0 STUB_PSI=45.10 "$BIN" --collect >"$W/out" 2>&1; rc=$?; quiet
ok "mid-run cpu pressure -> rc 0" '[ $rc = 0 ]'
ok "mid-run cpu pressure prints skip cpu pressure" 'grep -q "^skip cpu pressure peaked at 45.10" "$W/out"'
ok "mid-run cpu pressure writes 0 rows" '[ "$(wc -l <"$W/state/perf.csv")" = "$rows" ]'
STUB_RC=0 STUB_PSI=19.99 "$BIN" --collect >"$W/out" 2>&1; rc=$?; quiet
ok "cpu pressure under 20 keeps the row" '[ $rc = 0 ] && [ "$(wc -l <"$W/state/perf.csv")" = $((rows + 1)) ]'
rows=$((rows + 1))
STUB_RC=0 STUB_GPU=1 "$BIN" --collect >"$W/out" 2>&1; rc=$?; gpuidle
ok "mid-run gpu busy -> rc 0" '[ $rc = 0 ]'
ok "mid-run gpu busy prints skip gpu busy" 'grep -q "^skip gpu busy, peaked at 40% > 15%" "$W/out"'
ok "mid-run gpu busy writes 0 rows" '[ "$(wc -l <"$W/state/perf.csv")" = "$rows" ]'
cp -r "$W/fd-busy/." "$W/fd/"; STUB_RC=0 "$BIN" --collect >"$W/out" 2>&1; rc=$?; gpuidle
ok "gpu busy before the run -> rc 0, skip, gate not called" '[ $rc = 0 ] && grep -q "^skip gpu busy at 40% > 15%" "$W/out" && [ "$(grep -c . "$W/gate.log")" = 12 ]'
STUB_RC=0 STUB_HOLD="$W/hold" "$BIN" --collect >"$W/outA" 2>&1 &
a=$!
for _ in $(seq 100); do [ -e "$W/hold.started" ] && break; sleep 0.1; done
STUB_RC=0 "$BIN" --collect >"$W/outB" 2>&1; rcb=$?
touch "$W/hold.release"; wait "$a"; rca=$?
ok "second concurrent run -> rc 0" '[ $rcb = 0 ]'
ok "second concurrent run prints busy with the holder pid" 'grep -qx "busy: another run (pid $a)" "$W/outB"'
ok "first concurrent run completes and writes its row" '[ $rca = 0 ] && [ "$(wc -l <"$W/state/perf.csv")" = $((rows + 1)) ]'
STUB_RC=0 "$BIN" --collect >/dev/null 2>&1
ok "quiet run after the lock is freed writes a row" '[ "$(wc -l <"$W/state/perf.csv")" = $((rows + 2)) ]'
"$BIN" --bogus >/dev/null 2>&1; ok "unknown arg -> rc 2" '[ $? = 2 ]'
"$BIN" >"$W/out" 2>&1; ok "no arg prints the csv tail" '[ $? = 0 ] && grep -q row "$W/out"'

H=date,project,gpu_ms_p50,post_ms_p50,gpu_ms_p50_shadow,gpu_ms_p50_scene,gpu_ms_p50_skin
printf '%s\nd,cpp,4.0,1.0,1.5,1.2,0.3\n' "$H" >"$W/ok.csv"
printf '%s\nd,cpp,4.0,1.0,2.5,1.2,0.3\n' "$H" >"$W/over.csv"
printf '%s\nd,cpp,4.0,1.0,1.5,1.2\n' "${H%,*}" >"$W/old.csv"
printf '%s\nd,cpp,4.0,1.0,1.5,1.2,\n' "$H" >"$W/empty.csv"
ok "T744 --budget: fixture row under budget -> ok" '[ "$("$BIN" --budget "$W/ok.csv")" = ok ]'
ok "T744 --budget: one pass over -> over:shadow=2.5/2" '[ "$("$BIN" --budget "$W/over.csv")" = over:shadow=2.5/2 ]'
ok "T744 --budget: missing or empty skin column -> not checked, ok" '[ "$("$BIN" --budget "$W/old.csv")" = ok ] && [ "$("$BIN" --budget "$W/empty.csv")" = ok ]'
budgets 0.2; ok "T744 --budget: skin over only when the column exists" '[ "$("$BIN" --budget "$W/ok.csv")" = over:skin=0.3/0.2 ] && [ "$("$BIN" --budget "$W/old.csv")" = ok ]'
"$BIN" --budget "$W/nope.csv" >/dev/null 2>&1; ok "T744 --budget: missing csv -> rc 2" '[ $? = 2 ]'
ok "T744: real perf-budgets.json has post/shadow/skin/scene/frame with col, ms, ticket" \
	'jq -e "[.post, .shadow, .skin, .scene, .frame] | all(.col and (.ms | type == \"number\") and .ticket)" "$HOME/agents/skills/gamedev/templates/cpp-vulkan/perf-budgets.json" >/dev/null'

# T786: timing-gate rows (ci_timing_skip/ci_timing_ran into a fixture GAMEDEV_PERF_DIR) and their --skips counts
K=$W/skips; GL=$HOME/agents/skills/gamedev
GAMEDEV_PERF_DIR=$K bash -c '. "$1/scripts/ci-lib.sh"; ci_timing_skip cpp-hdr post_ms_p50 "busy: load 9.1"; ci_timing_skip cpp-hdr post_ms_p50 "gpu-clock 700 of 1300 MHz"
	ci_timing_ran cpp-hdr post_ms_p50; ci_timing_ran cpp-shadow gpu_ms_p50_shadow; ci_timing_skip cpp-shadow gpu_ms_p50_shadow lavapipe' _ "$GL"
ok "T786 ci_timing_skip: one 6-column TSV row per call (ts, test, metric, why, load, gpu clock)" \
	'[ "$(awk -F"\t" "NF == 6" "$K/skips.tsv" | wc -l)" = 5 ] && head -1 "$K/skips.tsv" | cut -f2-4 | grep -qx "cpp-hdr	post_ms_p50	busy: load 9.1"'
printf '%s\tcpp-hdr\tpost_ms_p50\tbusy: old\t9\t-\n' "$(date -Is -d '-10 days')" >>"$K/skips.tsv"
GAMEDEV_PERF_DIR=$K "$BIN" --skips 7d >"$W/out" 2>&1; rc=$?
ok "T786 --skips 7d: ran/skipped per test:metric, busy and gpu-clock split, a 10-day-old row left out" \
	'[ $rc = 0 ] && grep -qx "timing gates: cpp-hdr:post_ms_p50 ran 1, skipped 2 (busy 1, gpu-clock 1)" "$W/out" && grep -qx "timing gates: cpp-shadow:gpu_ms_p50_shadow ran 1, skipped 1 (busy 0, gpu-clock 0)" "$W/out"'
ok "T786 --skips: WARN only when skipped > ran" '[ "$(grep -c ^WARN "$W/out")" = 1 ] && grep -qx "WARN cpp-hdr:post_ms_p50 skipped 2 > ran 1 in 7d" "$W/out"'
GAMEDEV_PERF_DIR=$K "$BIN" --skips 30d >"$W/out" 2>&1
ok "T786 --skips 30d: the old row counts" 'grep -qx "timing gates: cpp-hdr:post_ms_p50 ran 1, skipped 3 (busy 2, gpu-clock 1)" "$W/out"'
GAMEDEV_PERF_DIR=$W/none "$BIN" --skips >"$W/out" 2>&1; rc=$?
ok "T786 --skips: no file -> rc 0, no rows line" '[ $rc = 0 ] && grep -q "^timing gates: no rows in 7d" "$W/out"'
"$BIN" --skips 7x >/dev/null 2>&1; ok "T786 --skips: bad window -> rc 2" '[ $? = 2 ]'
ok "T786: cpp-hdr and cpp-shadow log every gate outcome (own ci_timing_* calls, or gpu_timed from gpu-gate.sh since T899)" \
	'(for t in cpp-hdr cpp-shadow; do [ "$(grep -c "^[[:space:]]*ci_timing_\(skip\|ran\) $t " "$GL/tests/$t.test.sh")" -ge 3 ] \
		|| { grep -q "gpu_timed $t " "$GL/tests/$t.test.sh" && [ "$(grep -c "ci_timing_\(skip\|ran\) \"\$test\"" "$GL/scripts/gpu-gate.sh")" -ge 3 ]; } || exit 1; done)'

# T857: --compare on fixture rows (perf-cpp.csv + a cpp-ci summary.json), budgets as the real file's shape
C=$W/cmp; mkdir -p "$C/out"
CH=date,project,frames,avg_fps,load1,gpu_ms_p50,gpu_ms_p99,cpu_ms_p50,bound,status,vram_used_mb,vram_budget_mb,draws,culled,post_ms_p50,gpu_ms_p50_shadow,gpu_ms_p50_scene,gpu_ms_p50_skin,budget
printf '%s\n' "$CH" "2026-10-19T05:17:41+02:00,cpp,600,833,2.0,1.1190,3.7844,0.43,gpu,pass,115,26289,3,2,0.4449,0.0668,0.6018,0.0701,ok" \
	"2026-10-20T05:17:41+02:00,cpp,600,800,2.2,1.2000,3.8000,0.43,gpu,pass,115,26289,3,2,0.5600,0.0670,0.6018,0.0701,ok" >"$C/perf-cpp.csv"
jq -n '{post: {col: "post_ms_p50", ms: 0.5}, shadow: {col: "gpu_ms_p50_shadow", ms: 0.1}, skin: {col: "gpu_ms_p50_skin", ms: 0.15},
	scene: {col: "gpu_ms_p50_scene", ms: 0.8}, frame: {col: "gpu_ms_p50", ms: 1.65}}' >"$C/budgets.json"
pcmp() { GAMEDEV_PERF_DIR=$C GAMEDEV_PERF_BUDGETS=$C/budgets.json "$BIN" --compare "$@"; }
pcmp -2 -1 >"$W/out" 2>&1; rc=$?
ok "T857 --compare -2 -1: post 0.4449 -> 0.5600, +0.1151 ms +25.9 %, over its 0.5 budget, rc 1" \
	'[ $rc = 1 ] && grep -Eq "^post +0\.4449 +0\.5600 +\+0\.1151 +\+25\.9 +0\.5  over$" "$W/out"'
ok "T857 --compare: shadow +0.0002 is noise, total/p99/draws rows, no WARN at load 2.0 vs 2.2" \
	'grep -Eq "^shadow .* noise$" "$W/out" && grep -q "^total " "$W/out" && grep -q "^p99 " "$W/out" && grep -Eq "^draws +3 +3 +\+0 " "$W/out" && ! grep -q WARN "$W/out"'
pcmp 2026-10-19 2026-10-19T05 >"$W/out" 2>&1; rc=$?
ok "T857 --compare by date prefix: same row -> all noise, rc 0" '[ $rc = 0 ] && [ "$(grep -c " noise$" "$W/out")" = 6 ]'
jq -n '{stages: {perf: {status: "pass", load1: 7.5, gpu_ms_p50: 1.10, gpu_ms_p99: 3.7, draws: 4, post_ms_p50: 0.40, gpu_ms_p50_shadow: 0.0668, gpu_ms_p50_scene: 0.60, gpu_ms_p50_post: 0.40}}}' >"$C/out/summary.json"
pcmp -2 "$C/out" >"$W/out" 2>&1; rc=$?
ok "T857 --compare CSV vs summary.json dir: missing skin -> n/a, no traceback, no duplicate post row, rc 0" \
	'[ $rc = 0 ] && grep -Eq "^skin +0\.0701 +n/a +n/a +n/a " "$W/out" && ! grep -q Traceback "$W/out" && [ "$(grep -c "^post " "$W/out")" = 1 ]'
ok "T857 --compare: load1 2.0 vs 7.5 -> WARN" 'grep -q "^WARN load1 mismatch: A 2 vs B 7.5" "$W/out"'
printf '%s\tcpp-hdr\tpost_ms_p50\tran\t2\t1300\n%s\tcpp-hdr\tpost_ms_p50\tran\t2\t700\n' 2026-10-19T05:20:00+02:00 2026-10-20T05:10:00+02:00 >"$C/skips.tsv"
pcmp -2 -1 >"$W/out" 2>&1
ok "T857 --compare: GPU clock 1300 vs 700 MHz from skips.tsv -> WARN" 'grep -q "^WARN GPU clock mismatch: A 1300 MHz vs B 700 MHz" "$W/out"'
pcmp -2 -1 --json >"$W/out" 2>&1; rc=$?
ok "T857 --compare --json: same rows, over count, warn list, rc 1" \
	'[ $rc = 1 ] && jq -e "(.rows | map(.pass)) == [\"post\",\"shadow\",\"skin\",\"scene\",\"total\",\"p99\",\"draws\"] and .over == 1 and .rows[0].mark == \"over\" and (.warn | length) == 1" "$W/out" >/dev/null'
pcmp -9 -1 >/dev/null 2>&1; ok "T857 --compare: unknown row -> rc 2" '[ $? = 2 ]'
pcmp -1 >"$W/out" 2>&1; ok "T857 --compare: one argument -> rc 2, usage" '[ $? = 2 ] && grep -q "wants A B" "$W/out"'

# T857 edge cases: extra fields, missing budgets, NaN, the clock WARN's source
pcmp -2 -1 >"$W/out" 2>&1
ok "T857 --compare: the clock WARN names its source" 'grep -q "^WARN GPU clock mismatch: .* (skips.tsv), the delta" "$W/out"'
cp "$C/perf-cpp.csv" "$C/good.csv"; echo "2026-10-21T05:17:41+02:00,cpp,600,800,2.2,1.2,3.8,0.43,gpu,pass,115,26289,3,2,0.56,0.067,0.60,0.07,ok,x" >>"$C/perf-cpp.csv"
pcmp -2 -1 >"$W/out" 2>&1; rc=$?
ok "T857 --compare: a row with extra fields -> rc 2, bad row 4: 1 extra fields, no traceback" '[ $rc = 2 ] && grep -q "bad row 4: 1 extra fields" "$W/out" && ! grep -q Traceback "$W/out"'
cp "$C/good.csv" "$C/perf-cpp.csv"
GAMEDEV_PERF_DIR=$C GAMEDEV_PERF_BUDGETS=$C/nope.json "$BIN" --compare -2 -1 >"$W/out" 2>&1; rc=$?
ok "T857 --compare: missing budgets -> WARN naming the path, post row kept, rc 0" '[ $rc = 0 ] && grep -qx "WARN no perf-budgets.json ($C/nope.json)" "$W/out" && grep -q "^post " "$W/out"'
sed -i '$ s/,0\.5600,/,nan,/' "$C/perf-cpp.csv"
pcmp -2 -1 --json >"$W/out" 2>&1
ok "T857 --compare --json: NaN -> null, valid JSON" '! grep -q NaN "$W/out" && jq -e ".rows[0].b_ms == null" "$W/out" >/dev/null'
cp "$C/good.csv" "$C/perf-cpp.csv"

# T949: a non-object budgets file is a WARN, not a traceback; WARN lines follow the pass lines
echo '[1, 2]' >"$C/list.json"
GAMEDEV_PERF_DIR=$C GAMEDEV_PERF_BUDGETS=$C/list.json "$BIN" --compare -2 -1 >"$W/out" 2>&1; rc=$?
ok "T949 --compare: budgets [1, 2] -> WARN budgets: not an object, default passes, rc 0, no traceback" \
	'[ $rc = 0 ] && grep -qx "WARN budgets: not an object ($C/list.json)" "$W/out" && grep -q "^post " "$W/out" && ! grep -q Traceback "$W/out"'
pcmp -2 -1 >"$W/out" 2>&1
ok "T949 --compare: WARN lines come after the last pass line" \
	'[ "$(grep -n "^WARN" "$W/out" | head -1 | cut -d: -f1)" -gt "$(grep -n "^draws " "$W/out" | cut -d: -f1)" ]'

# T902: --trend over fixture perf-cpp.csv files (steady, +20 % post, 2 rows, extra fields, missing budgets, NaN)
T=$W/trend; mkdir -p "$T"
trow() { echo "2026-10-$1T05:17:41+02:00,cpp,600,833,2.0,1.1190,3.7844,0.43,gpu,pass,115,26289,3,2,$2,0.0668,0.6018,0.0701,ok"; }
steady() { echo "$CH"; for d in 10 11 12 13 14 15 16 17 18 19; do trow "$d" 0.4449; done; }
ptr() { GAMEDEV_PERF_DIR=$T GAMEDEV_PERF_BUDGETS=${TB:-$C/budgets.json} "$BIN" --trend "$@"; }
{ steady; trow 20 0.4500; } >"$T/perf-cpp.csv"
ptr >"$W/out" 2>&1; rc=$?
ok "T902 --trend steady: trend line, 7 pass lines with sparkline/last/median/%, budget headroom, no WARN, rc 0" \
	'[ $rc = 0 ] && grep -qx "trend: 11 rows (2026-10-10T05:17:41+02:00 .. 2026-10-20T05:17:41+02:00)" "$W/out" \
	&& [ "$(grep -cE "^(post|shadow|skin|scene|frame|p99|draws) " "$W/out")" = 7 ] && grep -Eq "^post +[▁-█]{11}  last 0\.4500  median 0\.4449  \+1\.1 %  budget 0\.5 \(10 %\)$" "$W/out" \
	&& grep -Eq "^draws .* last 3  median 3  \+0\.0 %$" "$W/out" && ! grep -q WARN "$W/out"'
{ steady; trow 20 0.5339; } >"$T/perf-cpp.csv"
ptr >"$W/out" 2>&1; rc=$?
ok "T902 --trend +20 % post: WARN post, over-budget headroom negative, rc 1" \
	'[ $rc = 1 ] && grep -q "^WARN post 0.5339 ms > 1.15 x median 0.4449 (+20.0 %)" "$W/out" && grep -Eq "^post .* budget 0\.5 \(-7 %\)$" "$W/out" && [ "$(grep -c ^WARN "$W/out")" = 1 ]'
ptr 3 >"$W/out" 2>&1
ok "T902 --trend 3: only the last 3 rows" 'grep -q "^trend: 3 rows (2026-10-18" "$W/out"'
ptr --json >"$W/out" 2>&1; rc=$?
ok "T902 --trend --json: passes in order, warn flagged, rc 1" \
	'[ $rc = 1 ] && jq -e "(.passes | map(.pass)) == [\"post\",\"shadow\",\"skin\",\"scene\",\"frame\",\"p99\",\"draws\"] and .passes[0].warn and .rows == 11 and (.warn | length) == 1" "$W/out" >/dev/null'
{ echo "$CH"; trow 19 0.4449; trow 20 0.9; } >"$T/perf-cpp.csv"
ptr >"$W/out" 2>&1; rc=$?
ok "T902 --trend 2 rows: no trend yet, rc 0" '[ $rc = 0 ] && grep -q "^trend: 2 rows " "$W/out" && grep -q "^no trend yet" "$W/out"'
{ steady; echo "$(trow 20 0.45),extra,more"; } >"$T/perf-cpp.csv"
ptr >"$W/out" 2>&1; rc=$?
ok "T902 --trend extra fields: bad row 12: 2 extra fields, rc 2, no traceback" '[ $rc = 2 ] && grep -q "bad row 12: 2 extra fields" "$W/out" && ! grep -q Traceback "$W/out"'
{ steady; trow 20 0.4500; } >"$T/perf-cpp.csv"
TB=$T/none.json ptr >"$W/out" 2>&1; rc=$?
ok "T902 --trend missing budgets: WARN with the path, pass lines without budget, rc 0" \
	'[ $rc = 0 ] && grep -qx "WARN no perf-budgets.json ($T/none.json)" "$W/out" && grep -q "^post " "$W/out" && ! grep -q budget\  "$W/out"'
{ steady; trow 20 nan; } >"$T/perf-cpp.csv"
ptr --json >"$W/out" 2>&1; rc=$?
ok "T902 --trend NaN: JSON null, no NaN, rc 0" '[ $rc = 0 ] && ! grep -q NaN "$W/out" && jq -e ".passes[0].last == null and .passes[0].values[-1] == null" "$W/out" >/dev/null'
ptr >"$W/out" 2>&1
ok "T902 --trend NaN text: gap dot in the sparkline, last n/a" 'grep -Eq "^post +[▁-█]{10}·  last n/a" "$W/out"'
ptr 0 >/dev/null 2>&1; ok "T902 --trend 0 -> rc 2" '[ $? = 2 ]'
GAMEDEV_PERF_DIR=$W/none "$BIN" --trend >"$W/out" 2>&1; rc=$?
ok "T902 --trend no csv: trend: 0 rows, no trend yet, rc 0" '[ $rc = 0 ] && grep -q "^trend: 0 rows" "$W/out" && grep -q "^no trend yet" "$W/out"'

echo "gamedev-perf.test: $pass passed, $fail failed"
[ "$fail" = 0 ]
