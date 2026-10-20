#!/usr/bin/env bash
# T465: lib/budget.sh against PC_LOADAVG/PC_NPROC fixtures — quiet keeps the base, load scales it, a 10× regression stays red.
set -uo pipefail
. "$HOME/agents/bin/tests/lib/budget.sh"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
export PC_PSI="$WORK/no-psi"
at()  { echo "$1 0.40 0.30 1/900 1234" >"$WORK/la"; PC_LOADAVG="$WORK/la" PC_NPROC=16 budget "$2"; }
psi() { printf 'some avg10=%s avg60=0.00 avg300=0.00 total=1\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n' "$1" >"$WORK/psi"; }

for base in 0.02 0.4 0.5 0.8; do is "load 0.5 keeps the old $base s" "$(at 0.50 "$base")" "$(printf '%.3f' "$base")"; done
is 'load 4/16 cpu (0.25 per cpu) still keeps the base' "$(at 4.00 0.5)" 0.500
is 'load 8/16 cpu doubles the budget' "$(at 8.00 0.5)" 1.000
is 'load 22/16 cpu scales 5.5x' "$(at 22.00 0.5)" 2.750
is 'load 64/16 cpu is capped at 8x' "$(at 64.00 0.5)" 4.000
is 'the script form prints the same budget' "$(echo '8.00 1 1 1/1 1' >"$WORK/la"; PC_LOADAVG="$WORK/la" PC_NPROC=16 "$HOME/agents/bin/tests/lib/budget.sh" 0.4)" 0.800
for base in 0.02 0.4 0.5 0.8; do
  for load in 8.00 22.00 64.00; do
    b=$(at "$load" "$base")
    awk -v t="$(awk -v x="$base" 'BEGIN{print x*10}')" -v b="$b" 'BEGIN{exit !(t>b)}' \
      && ok "10x regression of $base s fails at load $load (budget $b s)" || nok "10x regression of $base s at load $load" "budget $b s"
  done
done

# T491: lib/budget.py is the same formula, and a real 10x-slow step judged by it stays red at the 8x cap.
for load in 0.50 8.00 22.00 64.00; do
  echo "$load 1 1 1/1 1" >"$WORK/la"
  is "budget.py matches budget.sh at load $load" "$(PC_LOADAVG="$WORK/la" PC_NPROC=16 python3 "$HOME/agents/bin/tests/lib/budget.py" 0.35)" "$(at "$load" 0.35)"
done
# T616: live CPU pressure (PSI some avg10) lifts the factor while the 1-min load still lags; the 8x cap holds.
psi 60.00; is 'load 1 + psi 60 gives factor 4' "$(PC_PSI="$WORK/psi" at 1.00 1)" 4.000
psi 0.00;  is 'load 1 + psi 0 keeps factor 1' "$(PC_PSI="$WORK/psi" at 1.00 1)" 1.000
psi 100.00; is 'psi 100 alone gives factor 6' "$(PC_PSI="$WORK/psi" at 1.00 1)" 6.000
psi 100.00; is 'load 64 + psi 100 is capped at 8x' "$(PC_PSI="$WORK/psi" at 64.00 1)" 8.000
is 'a missing PSI file keeps the load-only factor' "$(at 8.00 1)" 2.000
for f in '1.00 0.00' '1.00 60.00' '8.00 10.00' '8.00 50.00' '22.00 30.00' '64.00 100.00'; do
  set -- $f; psi "$2"; echo "$1 1 1 1/1 1" >"$WORK/la"
  is "budget.py matches budget.sh at load $1 psi $2" "$(PC_PSI="$WORK/psi" PC_LOADAVG="$WORK/la" PC_NPROC=16 python3 "$HOME/agents/bin/tests/lib/budget.py" 0.35)" "$(PC_PSI="$WORK/psi" at "$1" 0.35)"
done

echo '999.00 1 1 1/1 1' >"$WORK/la"
r=$(PC_LOADAVG="$WORK/la" PC_NPROC=16 python3 "$HOME/agents/bin/tests/fixtures/timing-lint/regress.py"); rc=$?
is "10x-slow Python fixture fails at load 999/16 ($r)" "$rc" 1
[ $bad = 0 ] && echo 'PASS budget' || echo 'FAIL budget'
exit $bad
