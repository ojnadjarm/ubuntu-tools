#!/usr/bin/env bash
# TSP-007: pc idle against tests/fixtures/idle — a stubbed `pc power rapl` / `pc top`, the
# median/stddev roll-up, the TSV row pcbench-weekly appends. Nothing real is read or written.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$BIN/tests/fixtures/idle"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
fx() {
  : >"$WORK/n"
  PC_FIXTURE="$FIX" PC_STUB_STATE="$WORK/n" PC_IDLE_INTERVAL=1 \
  XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-idle" "$@"
}

J=$(fx --seconds 3 --json)

# 1. the window: one rapl sample per interval, seconds echoed back.
is 'sample count'    "$(jq .samples <<<"$J")" 3
is 'seconds echoed'  "$(jq .seconds <<<"$J")" 3
is 'a timestamp'     "$(jq -r '.t|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' <<<"$J")" true
is 'never fewer than one sample' "$(fx --seconds 1 --json | jq .samples)" 1
is 'a non-numeric window falls back to 60 s' "$(fx --seconds x --json | jq .seconds)" 60

# 2. watts: median of 4/9/5 package and 6/8/7 psys, population stddev of psys.
is 'package median' "$(jq .package_w <<<"$J")" 5
is 'psys median'    "$(jq .psys_w <<<"$J")" 7
is 'psys stddev'    "$(jq .psys_sd <<<"$J")" 0.82

# 3. wakers: the five busiest, in order, from `pc top --sort wake`.
is 'five wakers'     "$(jq '.wakers|length' <<<"$J")" 5
is 'busiest first'   "$(jq -r '.wakers[0].comm' <<<"$J")" claude
is 'wake rate kept'  "$(jq '.wakers[0].wake' <<<"$J")" 140.0

# 4. fleet RSS: only agent@*, sentinel*, dark-eye* units are counted.
is 'fleet rss in MB' "$(jq '.fleet.rss_mb' <<<"$J")" 350
is 'three fleet units' "$(jq '.fleet.units|length' <<<"$J")" 3
is 'the browser is not fleet' \
  "$(jq '[.fleet.units[]|select(test("firefox"))]|length' <<<"$J")" 0

# 4b. other_rss_mb: the two leftover browser trees of the fixture /proc (100 + 50 MB);
# the fixture's firefox (156 MB) is not one of them.
is 'browser trees in other_rss_mb' "$(jq '.other_rss_mb' <<<"$J")" 150

# 5. --tsv: the row pcbench-weekly appends, matching BASELINE-IDLE.tsv's header.
R=$(fx --seconds 3 --tsv)
is 'one tsv row'     "$(wc -l <<<"$R")" 1
is 'ten columns'     "$(awk -F'\t' '{print NF}' <<<"$R")" 10
is 'tsv other_rss_mb' "$(cut -f10 <<<"$R")" 150
is 'columns match the baseline header' \
  "$(awk -F'\t' '{print NF}' <<<"$R")" \
  "$(sed -n '2s/^#//p' "$BIN/../bench/BASELINE-IDLE.tsv" | awk -F'\t' '{print NF}')"
is 'tsv watts'       "$(cut -f4,5,6 <<<"$R")" "$(printf '5\t7\t0.82')"
is 'tsv top waker'   "$(cut -f7 <<<"$R")" claude

# 6. text, the CLI contract, and read-only.
is 'four text lines' "$(fx --seconds 3 | wc -l)" 4
fx --seconds 3 | grep -q '^power   package 5 W median  psys 7 W ±0.82$' \
  && ok 'text power line' || nok 'text power line' "$(fx --seconds 3 | sed -n 2p)"
fx --nosuchflag >/dev/null 2>&1; is 'unknown option exits 2' "$?" 2
fx -h >/dev/null 2>&1;           is '-h exits 0' "$?" 0
grep -q '^  pc idle ' <<<"$("$BIN/pc" help)" && ok 'pc help lists pc idle' \
  || nok 'pc help lists pc idle' 'missing'
[ -e "$WORK/l.jsonl" ] && nok 'pc idle writes no ledger entry' 'ledger exists' \
                       || ok 'pc idle writes no ledger entry'

[ $bad = 0 ] && echo 'PASS pc-idle' || echo 'FAIL pc-idle'
exit $bad
