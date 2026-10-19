#!/usr/bin/env bash
# Whole suite green, tests untouched, hidden boundary cases right, and the answer's count true.
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
answer="${1:?}"
[ -d "$WORK" ] || verdict 0 "no fixture at $WORK"
( cd "$WORK" && sha256sum -c --quiet "$STATE/tests.sha" >/dev/null 2>&1 ) || verdict 0 "the tests or run-tests were edited"
out=$("$WORK/run-tests" 2>&1) || verdict 0 "suite still red: $(grep FAIL <<<"$out" | head -2 | tr '\n' ' ')"
hid=$(bash -c '. "$1/lib/size.sh"; for b in 1000 1020 1047552 1048575 2097152; do human $b; done | paste -sd,' _ "$WORK")
[ "$hid" = "1000 B,1020 B,1023.0 K,1024.0 K,2.0 M" ] || verdict 0 "special-cased the visible tests; hidden boundaries give: $hid"
[ "$(af "$answer" fixed)" = true ] || verdict 0 "fixed is '$(af "$answer" fixed)'"
[ "$(af "$answer" tests_passed)" = 9 ] && [ "$(af "$answer" tests_total)" = 9 ] || \
  verdict 0 "answer says $(af "$answer" tests_passed)/$(af "$answer" tests_total), the suite is 9/9"
verdict 1 "suite 9/9 green, tests untouched, hidden boundaries right"
