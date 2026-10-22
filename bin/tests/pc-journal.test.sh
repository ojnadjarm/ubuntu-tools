#!/usr/bin/env bash
# host-only: live kernel journal of this box
# PT13: `pc journal` — live (journalctl -o json is 0.01 s per PLAN-PCTOOLS §0, no fixture needed).
set -uo pipefail
BIN="$HOME/agents/bin"
J="$BIN/pc-journal"
. "$BIN/tests/lib/budget.sh"
. "$HOME/agents/bin/tests/lib/assert.sh"

"$J" errors --since 1h --json | jq -e 'type=="array"' >/dev/null
is 'errors --since 1h --json is valid JSON' "$?" 0

out=$("$J" digest --since 1h --json)
printf '%s\n' "$out" | jq -e 'type=="array"' >/dev/null
is 'digest --json is valid JSON' "$?" 0
kcount=$(jq -r '[.[]|select(.unit=="kernel")][0].count // 0' <<<"$out")
[ "${kcount:-0}" -ge 1 ] 2>/dev/null && ok 'digest has a kernel row with count>=1' \
  || nok 'digest has a kernel row with count>=1' "$kcount"

# The busiest user service in the newest 200 lines, so the unit always has 5 entries.
u=$(journalctl --user -n 200 -o json -q | jq -r '._SYSTEMD_USER_UNIT // empty' | grep '\.service$' | sort | uniq -c | sort -rn | awk 'NR==1{print $2}')
u=${u%.service}
t0=$(date +%s.%N)
n=$("$J" unit "$u" -n 5 | wc -l)
t1=$(date +%s.%N)
is "unit $u -n 5 prints 5 lines" "$n" 5
bud=$(budget 0.3)
awk -v a="$t0" -v b="$t1" -v m="$bud" 'BEGIN{exit !(b-a<=m)}' \
  && ok "unit $u -n 5 runs in <= $bud s budget" \
  || nok "unit $u -n 5 runs in <= $bud s budget" "$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", b-a}')"

"$J" boots --json | jq -e 'type=="array" and length>=1' >/dev/null
is 'boots --json lists at least one boot' "$?" 0

"$J" size --json | jq -e 'has("bytes") and .bytes>0' >/dev/null
is 'size --json has bytes>0' "$?" 0
want=$(systemd-analyze cat-config systemd/journald.conf 2>/dev/null | sed -n 's/^SystemMaxUse=//p' | tail -1)
"$J" size | grep -qF "cap SystemMaxUse=${want:-default}"
is 'size shows the journald SystemMaxUse cap' "$?" 0

"$J" grep 'UFW BLOCK' --since 1h --json | jq -e 'type=="array"' >/dev/null
is 'grep --json is valid JSON' "$?" 0

[ $bad = 0 ] && echo 'PASS pc-journal' || echo 'FAIL pc-journal'
exit $bad
