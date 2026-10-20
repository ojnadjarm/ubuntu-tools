#!/usr/bin/env bash
# Fixture for timing-lint: 4 bare wall asserts (lines 5, 9, 12, 14); never run.
T0=$EPOCHREALTIME; "$BIN/x" >/dev/null; T1=$EPOCHREALTIME
ms=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%d", (b-a)*1000}')
[ "$ms" -le 300 ] && ok fast || nok fast "$ms"
t0=$(date +%s.%N); "$BIN/x"; t1=$(date +%s.%N)
wall=$(python3 -c "print($t1-$t0)")
[ "$(wc -l <"$f")" -le 4 ] && ok 'not a timing line'
python3 -c "import sys; sys.exit(0 if $wall <= 0.8 else 1)" && ok wall
cold=$(/usr/bin/time -f '%e' "$BIN/x" 2>&1 >/dev/null | tail -1)
# a comment saying <= 0.5 s is not an assert
awk -v c="$cold" 'BEGIN{exit !(c<=1.5)}' && ok cold
d=$(col doctor_s "$R")
awk -v d="$d" 'BEGIN{exit !(d>=0.3 && d<2)}' && ok doctor
