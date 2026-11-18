#!/usr/bin/env bash
# run-all.sh: the night comparison (T1773): selftest, safety tier per arm, the ticket trials, RESULT.md; one notify only on failure.
set -uo pipefail
SC=$(cd "$(dirname "$0")" && pwd)
OUT=${T1773_OUT:-$HOME/agent-work/research/2026-11-18/T1773}
TICKETS=${T1773_TICKETS:-T1693 T1666 T1657 T1725 T1728}
fail() { notify-owner "T1773 night compare failed: $1 (log ~/agent-work/research/2026-11-18/T1773/night.log)"; exit 1; }
echo "start $(date -Is) tickets: $TICKETS"
plan-usage --json > "$OUT/plan-before.json" 2>&1
python3 "$SC/build_arms.py" || fail "arm build"
"$SC/selftest.sh" > "$OUT/selftest-night.txt" 2>&1 || fail "sandbox selftest"
for arm in old slim; do "$SC/safety.sh" "$arm" || echo "safety $arm exit $?"; done
for tk in $TICKETS; do
  for arm in old slim; do
    if [ -s "$OUT/runs/$tk-$arm/measures.json" ] && [ -z "${T1773_RERUN:-}" ]; then echo "keep $tk-$arm (done before)"; continue; fi
    echo "trial $tk-$arm $(date -Is)"; "$SC/trial.sh" "$tk" "$arm" > /dev/null || echo "trial $tk-$arm exit $?"
  done
done
plan-usage --json > "$OUT/plan-after.json" 2>&1
missing=0
for tk in $TICKETS; do for arm in old slim; do [ -s "$OUT/runs/$tk-$arm/measures.json" ] || missing=$((missing + 1)); done; done
python3 "$SC/result.py" > "$OUT/RESULT.md" || fail "result page"
[ "$missing" = 0 ] || fail "$missing trial(s) without measures"
echo "end $(date -Is)"
