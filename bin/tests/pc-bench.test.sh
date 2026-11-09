#!/usr/bin/env bash
# pc bench argument checks: a bad --runs exits 2 before anything is measured.
set -uo pipefail
BIN="$HOME/agents/bin"
. "$BIN/tests/lib/assert.sh"
for v in abc 0 1.5; do
  out=$(timeout 5 "$BIN/pc-bench" --runs "$v" --only status 2>&1); is "--runs $v exits 2" "$?|$out" '2|pc bench: --runs takes a positive integer'
done
exit $bad
