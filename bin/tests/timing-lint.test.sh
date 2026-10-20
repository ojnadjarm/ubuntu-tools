#!/usr/bin/env bash
# T483: no shell test asserts a wall time against a bare literal; live timings go through lib/budget.sh.
# T491: the same for Python tests (bin/tests, hooks): a time.time/monotonic/perf_counter difference, or a name
# assigned from one, capped with a literal (`< 0.35`, `<= 100`); live timings go through lib/budget.py.
# A line is flagged when it reads a timing (EPOCHREALTIME, date +%s.%N, /usr/bin/time, a *_s value or a variable
# assigned from one) and caps it with a literal (`-le 300`, `<= 0.8`, `<2`). Fixtures in fixtures/timing-lint.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$DIR/fixtures/timing-lint"
# pc-doctor keeps its own load gate (unjudged over 0.5 load per CPU, T432).
EXEMPT='pc-doctor.test.sh'
. "$HOME/agents/bin/tests/lib/assert.sh"

# lint <file>... — prints `file:line: text` for every bare wall assert.
lint() {
  awk '
    FNR == 1 { delete tv }
    /^[[:space:]]*#/ { next }
    {
      src = ($0 ~ /EPOCHREALTIME|date \+%s\.%N|\/usr\/bin\/time|[a-z]_m?s([^A-Za-z0-9_]|$)/)
      for (v in tv) if ($0 ~ ("\\$\\{?" v "([^A-Za-z0-9_]|$)")) src = 1
      if (src && $0 ~ /(^|[^<])(<=?|-l[et])[[:space:]]*[0-9]+(\.[0-9]+)?([^A-Za-z0-9_.]|$)/)
        printf "%s:%d: %s\n", FILENAME, FNR, $0
      n = split($0, seg, ";")
      for (i = 1; i <= n; i++) {
        s = seg[i]; sub(/^[[:space:]]*(local[[:space:]]+)?/, "", s)
        if (!match(s, /^[A-Za-z_][A-Za-z0-9_]*=/)) continue
        name = substr(s, 1, RLENGTH - 1); seen = (s ~ /EPOCHREALTIME|date \+%s\.%N|\/usr\/bin\/time|[a-z]_m?s([^A-Za-z0-9_]|$)/)
        for (v in tv) if (s ~ ("\\$\\{?" v "([^A-Za-z0-9_]|$)")) seen = 1
        if (seen) tv[name] = 1
      }
    }' "$@"
}

# lint_py <file>... — the same for Python: a clock call minus a start is a timing, so is a name assigned from one.
lint_py() {
  awk '
    FNR == 1 { delete tv }
    /^[[:space:]]*#/ { next }
    {
      src = ($0 ~ /time\.(time|monotonic|perf_counter)(_ns)?\(\)[[:space:]]*-/)
      for (v in tv) if ($0 ~ ("(^|[^A-Za-z0-9_.])" v "([^A-Za-z0-9_]|$)")) src = 1
      if ($0 ~ /strftime|localtime|gmtime|utime/) src = 0
      if (src && $0 ~ /(^|[^<])<=?[[:space:]]*[0-9]+(\.[0-9]+)?([^A-Za-z0-9_.]|$)/)
        printf "%s:%d: %s\n", FILENAME, FNR, $0
      if (src && match($0, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[^=]/)) {
        name = substr($0, 1, RLENGTH - 1); gsub(/[[:space:]=]/, "", name); tv[name] = 1
      }
    }' "$@"
}

# 1. the fixture with bare asserts: exactly its 4 wall lines, not the wc -l line or the comment.
is 'bad fixture: the 4 bare wall asserts' "$(lint "$FIX/bad.sh" | cut -d: -f2 | tr '\n' ' ')" '5 9 12 14 '
# 2. the same measurements through budget(): nothing.
is 'budgeted fixture: 0 findings' "$(lint "$FIX/good.sh")" ''
is 'bad Python fixture: the 4 bare wall asserts' "$(lint_py "$FIX/bad.py" | cut -d: -f2 | tr '\n' ' ')" '5 7 9 11 '
is 'budgeted Python fixture: 0 findings' "$(lint_py "$FIX/good.py")" ''
# 3. the live tree.
live=()
for f in "$DIR"/*.test.sh; do [[ " $EXEMPT " == *" ${f##*/} "* ]] || live+=("$f"); done
found=$(lint "${live[@]}")
is "live tree: 0 bare wall asserts in ${#live[@]} files" "$found" ''
py=("$DIR"/*.test.py "$DIR"/../../hooks/*.test.py)
is "live Python tree: 0 bare wall asserts in ${#py[@]} files" "$(lint_py "${py[@]}")" ''

[ $bad = 0 ] && echo 'PASS timing-lint' || echo 'FAIL timing-lint'
exit $bad
