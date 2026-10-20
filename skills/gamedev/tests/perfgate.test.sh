#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # ok() evals its single-quoted checks
# T539/T551/T598: godot-perfgate.sh against a stub godot-smoke.sh, fake gt0 sysfs and a sudo shim: settle warm-up, 15-column rows, p50/p99 gates on the last 10 PASS rows, NOISE re-run on hard throttle only, --pin-gpu restore, old csv, SKIP.
set -uo pipefail
SKILL=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/skill/scripts" "$W/proj" "$W/gt" "$W/bin"
cp "$SKILL/scripts/godot-perfgate.sh" "$SKILL/scripts/ci-lib.sh" "$W/skill/scripts/"
cat >"$W/skill/scripts/godot-smoke.sh" <<'EOF'
#!/bin/sh
echo "$* pin=$(cat "$PERFGATE_GT/rps_min_freq_mhz")/$(cat "$PERFGATE_GT/rps_max_freq_mhz")" >>"$STUB_LOG"
case " $* " in *" --no-export "*) a=$STUB_AVG p=$STUB_P99; sleep 0.3 ;; *)
	echo "SMOKE renderer=vulkan adapter=Stub GPU, rev 1"
	for l in ${STUB_WARM:-11}; do echo "SMOKE fps=$l t=$((i = ${i:-0} + 1)).0"; done
	[ -n "${STUB_HANG:-}" ] && { echo $$ >"$STUB_HANG"; sleep 30; }
	exit 0 ;; esac
echo "SMOKE renderer=vulkan adapter=Stub GPU, rev 1"
echo "SMOKE fps=${a%.*} t=2.0"
if [ "$p" = none ]; then echo "SMOKE done frames=600 avg_fps=$a"
else echo "SMOKE done frames=600 avg_fps=$a coins=8 won=true p50_ms=${STUB_P50:-10.00} p95_ms=12.00 p99_ms=$p low1_fps=60.0"; fi
EOF
cat >"$W/bin/sudo" <<'EOF'
#!/bin/sh
echo "$*" >>"$SUDO_LOG"
v=$(cat); f=$2
case $f in *rps_min_freq_mhz) [ "$v" -le "$(cat "${f%min_freq_mhz}max_freq_mhz")" ] || { echo "EINVAL min $v" >>"$SUDO_LOG"; exit 1; } ;;
	*rps_max_freq_mhz) [ "$v" -ge "$(cat "${f%max_freq_mhz}min_freq_mhz")" ] || { echo "EINVAL max $v" >>"$SUDO_LOG"; exit 1; } ;; esac
echo "$v" >"$f"
EOF
chmod +x "$W/skill/scripts/"* "$W/bin/sudo"
gtset() { echo "$1" >"$W/gt/rps_act_freq_mhz"; echo "$2" >"$W/gt/throttle_reason_thermal"; echo "${3:-0}" >"$W/gt/throttle_reason_pl1"; echo $(($2 | ${3:-0})) >"$W/gt/throttle_reason_status"; echo 100 >"$W/gt/rps_min_freq_mhz"; echo 1300 >"$W/gt/rps_max_freq_mhz"; }
gtset 900 0
mkdir -p "$W/fdinfo/a" "$W/fdinfo/b"
export STUB_LOG="$W/smoke.log" SUDO_LOG="$W/sudo.log" PERFGATE_GT="$W/gt" PATH="$W/bin:$PATH" QUIET_FDINFO="$W/fdinfo"
G="$W/skill/scripts/godot-perfgate.sh"

pass=0 fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); r=""; [[ $2 == *'$(rc)'* ]] && r=" (rc $(rc))"; echo "FAIL: $1$r"; tail -n 3 "$W/out" "$W/err" 2>/dev/null | sed 's/^/  | /'; fi; }
gate() { STUB_AVG=$1 STUB_P99=$2 "$G" --runs 3 --max-load 999 --csv "$3" "${@:4}" "$W/proj" >"$W/out" 2>"$W/err"; echo $? >"$W/rc"; }
rc() { cat "$W/rc"; }
H=date,project,seconds,avg_fps,frame_ms,min_fps,load1,adapter,p50_ms,p95_ms,p99_ms,low1_fps,gpu_mhz_p50,throttle_pct,verdict

C=$W/new.csv
gate 100.0 14.00 "$C"
ok "first call sets baseline rc 0" '[ "$(rc)" = 0 ] && grep -q "^PERFGATE baseline set median_fps=100.0 " "$W/out"'
ok "header has 15 columns" '[ "$(head -1 "$C")" = "$H" ]'
ok "3 rows, warm-up row not written" '[ "$(wc -l <"$C")" = 4 ] && ! grep -q ",11.1," "$C"'
ok "rows end p99,low1,gpu,throttle,PASS" '[ "$(awk -F, "NR > 1 && NF == 15 && \$11 == \"14.00\" && \$12 == \"60.0\" && \$13 == 900 && \$14 == 0 && \$15 == \"PASS\"" "$C" | wc -l)" = 3 ]'
ok "warm-up exports once, measured runs do not" '[ "$(grep -vc -- --no-export "$STUB_LOG")" = 1 ] && [ "$(grep -c -- --no-export "$STUB_LOG")" = 3 ]'
ok "warm-up capped at 10 s, ends unsettled on 1 window" 'grep -q -- "--seconds 10 " "$STUB_LOG" && grep -q "warm-up ended unsettled" "$W/err"'

gate 99.0 14.50 "$C"
ok "steady run passes" '[ "$(rc)" = 0 ] && grep -q "^PERFGATE PASS median_fps=99.0 p50_ms=10.00 <= ceil=11.00 (p50_ms baseline 10.00 " "$W/out"'
ok "spread, p99, p50, gpu in the PERFGATE line" 'grep -q "spread_fps=99.0-99.0 median_p99_ms=14.50 median_p50_ms=10.00 gpu_mhz_p50=900 noise_reruns=0" "$W/out"'
ok "one median_fps token (game-ci parse)" '[ "$(grep "^PERFGATE" "$W/out" | grep -o "median_fps=[0-9.]*")" = "median_fps=99.0" ]'

gate 98.0 42.00 "$C"
ok "hitchy run (p99 x3, p50 in tol) fails" '[ "$(rc)" = 1 ] && grep -q "^PERFGATE FAIL median_fps=98.0 p99_ms=42.00 > ceil=" "$W/out"'
ok "failed rows marked FAIL" '[ "$(grep -c ",FAIL$" "$C")" = 3 ]'

STUB_P50=12.00 gate 100.0 14.00 "$C"
ok "slow p50 fails at the same avg fps" '[ "$(rc)" = 1 ] && grep -q "^PERFGATE FAIL median_fps=100.0 p50_ms=12.00 > ceil=11.00 " "$W/out"'

B=$W/last10.csv
{ echo "$H"; for _ in $(seq 5); do echo "d,w,6,40,25,40,1,G,25.00,,99.00,,,,PASS"; done
  for _ in $(seq 4); do echo "d,w,6,40,25,40,1,G,25.00,,99.00,,,,FAIL"; echo "d,w,6,40,25,40,1,G,25.00,,99.00,,,90,NOISE"; done
  for _ in $(seq 10); do echo "d,w,6,100,10,100,1,G,10.00,,14.00,,,,PASS"; done; } >"$B"
STUB_P50=10.50 gate 100.0 14.00 "$B"
ok "baseline = last 10 PASS rows only" '[ "$(rc)" = 0 ] && grep -q "(p50_ms baseline 10 of last 10 PASS rows" "$W/out"'

: >"$STUB_LOG"; gtset 1100 1
N2=$W/noise.csv
gate 100.0 14.00 "$N2"
ok "throttled runs: NOISE row + one re-run each" '[ "$(grep -c ",100,NOISE$" "$N2")" = 3 ] && [ "$(grep -c ",PASS$" "$N2")" = 3 ] && [ "$(grep -c -- --no-export "$STUB_LOG")" = 6 ]'
ok "noise_reruns=3 in the PERFGATE line" 'grep -q "gpu_mhz_p50=1100 noise_reruns=3" "$W/out"'
: >"$STUB_LOG"; gtset 600 0 1
N3=$W/pl1.csv
gate 100.0 14.00 "$N3"
ok "PL1-only throttle (status set): no NOISE, no re-run" '[ "$(rc)" = 0 ] && ! grep -q NOISE "$N3" && [ "$(grep -c -- --no-export "$STUB_LOG")" = 3 ] && grep -q "noise_reruns=0" "$W/out"'
gtset 900 0

: >"$STUB_LOG"; t0=$(date +%s)
STUB_WARM="50 80 99 100 100" STUB_HANG="$W/hang.pid" gate 100.0 14.00 "$W/settle.csv"
ok "warm-up settles on 2 windows within 3 % and is killed" '[ "$(rc)" = 0 ] && grep -q "warm-up settled at t=4.0 s" "$W/err" && [ $(($(date +%s) - t0)) -lt 15 ] && ! kill -0 "$(cat "$W/hang.pid")" 2>/dev/null'

: >"$SUDO_LOG"; : >"$STUB_LOG"
gate 100.0 14.00 "$W/pin.csv" --pin-gpu 700
ok "--pin-gpu holds min=max=700 for every run" '[ "$(grep -c "pin=700/700" "$STUB_LOG")" = 4 ]'
ok "--pin-gpu restores 100/1300 via sudo" '[ "$(cat "$W/gt/rps_min_freq_mhz")/$(cat "$W/gt/rps_max_freq_mhz")" = 100/1300 ] && [ "$(grep -c "^tee " "$SUDO_LOG")" = 4 ] && ! grep -q EINVAL "$SUDO_LOG"'
STUB_P50=20.00 gate 100.0 14.00 "$W/pin.csv" --pin-gpu 1500
ok "--pin-gpu above max: ordered writes, restored after a FAIL" '[ "$(rc)" = 1 ] && grep -q "pin=1500/1500" "$STUB_LOG" && [ "$(cat "$W/gt/rps_min_freq_mhz")/$(cat "$W/gt/rps_max_freq_mhz")" = 100/1300 ] && ! grep -q EINVAL "$SUDO_LOG"'
PERFGATE_GT="$W/nogt" gate 100.0 14.00 "$W/nogt.csv" --pin-gpu 700
ok "--pin-gpu without gt0 -> rc 2" '[ "$(rc)" = 2 ]'

O=$W/old.csv
printf '%s\n' date,project,seconds,avg_fps,frame_ms,min_fps,load1,adapter "d,work,6,90.0,11.11,80,3.0,GPU" "d,work,6,92.0,10.87,80,3.0,GPU" >"$O"
gate 91.0 30.00 "$O"
ok "old csv: legacy rows are not PASS rows, baseline set" '[ "$(rc)" = 0 ] && grep -q "^PERFGATE baseline set median_fps=91.0 " "$W/out"'
ok "old csv: header upgraded, old rows kept" '[ "$(head -1 "$O")" = "$H" ] && grep -qx "d,work,6,90.0,11.11,80,3.0,GPU" "$O"'
STUB_P50=14.00 gate 70.0 30.00 "$O"
ok "old csv: slow p50 fails against the new baseline" '[ "$(rc)" = 1 ]'

N=$W/nop99.csv
gate 100.0 none "$N"; gate 100.0 none "$N"
ok "no p50/p99 in output: frame_ms gate, empty columns" '[ "$(rc)" = 0 ] && grep -q "median_p99_ms=na median_frame_ms=10.00" "$W/out" && awk -F, "NR > 1 && (\$9 != \"\" || \$11 != \"\") {exit 1}" "$N"'

STUB_AVG=1 STUB_P99=1 "$G" --max-load 0 --csv "$W/skip.csv" "$W/proj" >"$W/out" 2>&1
ok "busy machine -> rc 3 SKIP" '[ $? = 3 ] && grep -q "^PERFGATE SKIP" "$W/out"'
ok "fixture prints p50/p99" 'grep -q "p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f" "$SKILL/fixture/main.gd"'

echo "perfgate.test: $pass passed, $fail failed"
[ "$fail" = 0 ]
