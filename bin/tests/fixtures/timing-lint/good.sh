#!/usr/bin/env bash
# Fixture for timing-lint: the same measurements against load-aware budgets; 0 findings.
. "$BIN/tests/lib/budget.sh"
T0=$EPOCHREALTIME; "$BIN/x" >/dev/null; T1=$EPOCHREALTIME
ms=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%d", (b-a)*1000}')
bms=$(awk -v b="$(budget 0.3)" 'BEGIN{printf "%d", b*1000}')
[ "$ms" -le "$bms" ] && ok fast || nok fast "$ms"
t0=$(date +%s.%N); "$BIN/x"; t1=$(date +%s.%N)
wall=$(python3 -c "print($t1-$t0)"); b=$(budget 0.8)
python3 -c "import sys; sys.exit(0 if $wall <= $b else 1)" && ok wall
d=$(col doctor_s "$R")
awk -v d="$d" -v b="$(budget 2)" 'BEGIN{exit !(d>=0.3 && d<b)}' && ok doctor
