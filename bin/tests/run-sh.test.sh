#!/usr/bin/env bash
# run.sh on a throwaway root with 3 fixture tests (pass, fail, hang → timeout); the real test homes are never run.
set -uo pipefail
RUN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run.sh"
W=$(mktemp -d); trap 'pkill -f "sleep 301.25" 2>/dev/null; rm -rf "$W"' EXIT
mkdir -p "$W/bin/tests"
printf 'echo fine\n' >"$W/bin/tests/pass.test.sh"
printf 'echo "FAIL broken thing"; exit 1\n' >"$W/bin/tests/fail.test.sh"
printf 'sleep 301.25\n' >"$W/bin/tests/hang.test.sh"
: >"$W/bin/tests/15"
fail=0
is() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$3', got '$2'"; fail=1; fi; }
has() { if grep -qE -- "$3" <<<"$2"; then echo "ok   $1"; else echo "FAIL $1: no /$3/ in: $(tr '\n' '|' <<<"$2")"; fail=1; fi; }

t0=$(date +%s)
out=$(RUN_TESTS_ROOT="$W" RUN_TESTS_TIMEOUT=2 bash "$RUN" -j 3 2>&1); rc=$?
dt=$(( $(date +%s) - t0 ))
is  'mixed run exits 1' "$rc" 1
has 'pass gets an ok line with seconds' "$out" '^ok bin/tests/pass\.test\.sh [0-9]+\.[0-9]$'
has 'fail gets a FAIL line with seconds' "$out" '^FAIL bin/tests/fail\.test\.sh [0-9]+\.[0-9]$'
has 'hang is cut by the timeout' "$out" '^FAIL bin/tests/hang\.test\.sh [0-9.]+ timeout$'
has 'failing output tail is shown' "$out" '^  \| FAIL broken thing$'
has 'stray empty file is reported' "$out" '^note: stray empty file bin/tests/15'
is  'stray empty file is left in place' "$(test -e "$W/bin/tests/15" && echo kept)" kept
has 'last line is the summary' "$(tail -1 <<<"$out")" '^FAIL 1/3 files in [0-9]+ s$'
is  'hang does not hold the run (< 10 s)' "$([ "$dt" -lt 10 ] && echo yes || echo "$dt s")" yes
is  'no hung child survives' "$(pgrep -f 'sleep 301.25' | wc -l)" 0

out=$(RUN_TESTS_ROOT="$W" bash "$RUN" --only '*pass*' 2>&1); rc=$?
is  '--only pass exits 0' "$rc" 0
is  '--only pass runs one file' "$(tail -1 <<<"$out" | grep -oE '^PASS 1/1 files in [0-9]+ s$' | wc -l)" 1

RUN_TESTS_ROOT="$W" bash "$RUN" --bogus >/dev/null 2>&1; is 'unknown argument exits 2' "$?" 2
bash "$RUN" -h | grep -q 'run.sh \[-j N\]'; is '-h prints usage' "$?" 0

[ $fail = 0 ] && echo "run-sh.test.sh: all green" || echo "run-sh.test.sh: FAILURES"
exit $fail
