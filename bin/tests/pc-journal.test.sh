#!/usr/bin/env bash
# PT13: `pc journal` — live (journalctl -o json is 0.01 s per PLAN-PCTOOLS §0, no fixture needed).
set -uo pipefail
BIN="$HOME/agents/bin"
J="$BIN/pc-journal"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

"$J" errors --since 1h --json | jq -e 'type=="array"' >/dev/null
is 'errors --since 1h --json is valid JSON' "$?" 0

out=$("$J" digest --since 1h --json)
printf '%s\n' "$out" | jq -e 'type=="array"' >/dev/null
is 'digest --json is valid JSON' "$?" 0
kcount=$(jq -r '[.[]|select(.unit=="kernel")][0].count // 0' <<<"$out")
[ "${kcount:-0}" -ge 1 ] 2>/dev/null && ok 'digest has a kernel row with count>=1' \
  || nok 'digest has a kernel row with count>=1' "$kcount"

t0=$(date +%s.%N)
n=$("$J" unit dark-eye -n 5 | wc -l)
t1=$(date +%s.%N)
is 'unit dark-eye -n 5 prints 5 lines' "$n" 5
awk -v a="$t0" -v b="$t1" 'BEGIN{exit !(b-a<=0.3)}' \
  && ok 'unit dark-eye -n 5 runs in <= 0.3 s' \
  || nok 'unit dark-eye -n 5 runs in <= 0.3 s' "$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", b-a}')"

"$J" boots --json | jq -e 'type=="array" and length>=1' >/dev/null
is 'boots --json lists at least one boot' "$?" 0

"$J" size --json | jq -e 'has("bytes") and .bytes>0' >/dev/null
is 'size --json has bytes>0' "$?" 0

"$J" grep 'UFW BLOCK' --since 1h --json | jq -e 'type=="array"' >/dev/null
is 'grep --json is valid JSON' "$?" 0

[ $bad = 0 ] && echo 'PASS pc-journal' || echo 'FAIL pc-journal'
exit $bad
