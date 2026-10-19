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
is 'waker unit kept' "$(jq -r '.wakers[0].unit' <<<"$J")" agent@x.service
is 'tmux-spawn scope collapsed' "$(jq -r '.wakers[4].unit' <<<"$J")" tmux-spawn

# 4. fleet RSS: only agent@*, sentinel*, dark-eye* units are counted.
is 'fleet rss in MB' "$(jq '.fleet.rss_mb' <<<"$J")" 350
is 'three fleet units' "$(jq '.fleet.units|length' <<<"$J")" 3
is 'the browser is not fleet' \
  "$(jq '[.fleet.units[]|select(test("firefox"))]|length' <<<"$J")" 0

# 4b. other_rss_mb: the two leftover browser trees of the fixture /proc (100 + 50 MB);
# the fixture's firefox (156 MB) is not one of them.
is 'browser trees in other_rss_mb' "$(jq '.other_rss_mb' <<<"$J")" 150

# 4c. other_top: the largest browser tree by cgroup leaf, from a fake /proc under mktemp -d (TSP-039).
FX2="$WORK/fix"; cp -r "$FIX" "$FX2"
case "$FX2/proc" in "$WORK"/*) ok 'selftest: the fake /proc is under mktemp -d';; *) nok 'selftest: fake /proc' "$FX2/proc";; esac
now=$(date +%s); clk=$(getconf CLK_TCK)
printf 'cpu 0 0 0 0\nbtime %s\n' "$((now - 1000))" >"$FX2/proc/stat"
mkp() {   # mkp <pid> <comm> <start s after boot> <cgroup leaf>
  printf '%s\n' "$2" >"$FX2/proc/$1/comm"
  printf '%s (%s) S 1 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 %s 0 0\n' "$1" "$2" "$(($3 * clk))" >"$FX2/proc/$1/stat"
  printf '0::/user.slice/user-%s.slice/user@%s.service/app.slice/%s\n' "$UID" "$UID" "$4" >"$FX2/proc/$1/cgroup"
}
mkdir -p "$FX2/proc/4004"
printf '/opt/chromium/headless_shell\0--headless=new\0' >"$FX2/proc/4004/cmdline"
printf '40960 20480 100 10 0 500 0\n' >"$FX2/proc/4004/statm"
mkp 4001 node 600 tmux-spawn-aaa.scope
mkp 4002 headless_shell 0 ailearning-ci-daily.service
mkp 4004 headless_shell 500 ailearning-ci-daily.service
J2=$(PC_FIXTURE="$FX2" PC_STUB_STATE="$WORK/n" PC_IDLE_INTERVAL=1 XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/l.jsonl" \
  "$BIN/pc-idle" --seconds 1 --json)
is 'other_rss_mb sums all three browser processes' "$(jq '.other_rss_mb' <<<"$J2")" 230
case "$(jq -r '.other_top' <<<"$J2")" in
  ailearning-ci-daily.service:chrome-headless:99[89]:130|ailearning-ci-daily.service:chrome-headless:100[01]:130) ok 'other_top names the larger cgroup, its family, oldest age and MB';;
  *) nok 'other_top names the larger cgroup' "$(jq -r '.other_top' <<<"$J2")";;
esac
FX3="$WORK/fix3"; cp -r "$FIX" "$FX3"; rm -rf "$FX3/proc/"*
is 'no browser tree: other_top is -' "$(PC_FIXTURE="$FX3" PC_STUB_STATE="$WORK/n" PC_IDLE_INTERVAL=1 XDG_RUNTIME_DIR="$WORK" \
  PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-idle" --seconds 1 --json | jq -r '[.other_rss_mb,.other_top]|@tsv')" "$(printf '0\t-')"

# 5. --tsv: the row pcbench-weekly appends, matching BASELINE-IDLE.tsv's header.
R=$(fx --seconds 3 --tsv)
is 'one tsv row'     "$(wc -l <<<"$R")" 1
is 'twelve columns'  "$(awk -F'\t' '{print NF}' <<<"$R")" 12
is 'tsv top waker unit in column 11' "$(cut -f11 <<<"$R")" agent@x.service
is 'tsv ends with other_top' "$(awk -F'\t' '{print $NF}' <<<"$R")" "$(jq -r .other_top <<<"$J")"
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
