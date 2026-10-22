#!/usr/bin/env bash
# pc-snap against stub sudo/snap, a fixture snaps dir and a temp ledger: window set, refusals, undo, prune list and apply, nothing; mutants go red.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

real_sum() { md5sum "$HOME/agents/log/changes.jsonl" 2>/dev/null; }
before=$(real_sum)
mkdir -p "$W/path" "$W/snaps"
cat >"$W/path/sudo" <<'EOF'
#!/bin/sh
[ "$1" = -n ] && shift
exec "$@"
EOF
cat >"$W/path/snap" <<EOF
#!/usr/bin/env bash
echo "snap \$*" >>$W/calls
T=$W/timer L=$W/list
case "\$1 \$2" in
  'get system') [ -e \$T ] && cat \$T || { echo 'error: snap "core" has no "refresh.timer" configuration option' >&2; exit 1; };;
  'set system') echo "\${3#refresh.timer=}" >\$T;;
  'unset system') rm -f \$T;;
  'refresh --time') echo "timer: \$([ -e \$T ] && cat \$T || echo '00:00~24:00/4')"; echo 'last: today at 04:02 CEST';;
  'list --all') cat \$L;;
  remove*) r=\${3#--revision=}; [ "\$2" = stuck ] && exit 1; awk -v n="\$2" -v r="\$r" '!(\$1 == n && \$3 == r)' \$L >\$L.n && mv \$L.n \$L;;
  *) exit 64;;
esac
EOF
chmod +x "$W/path/"*
export PATH="$W/path:$PATH" PC_LEDGER="$W/changes.jsonl" PC_SNAP_DIR="$W/snaps" CI_WINDOW=00:50-01:50 XDG_RUNTIME_DIR="$W"
[ "$(command -v sudo)" = "$W/path/sudo" ] && [ "$(command -v snap)" = "$W/path/snap" ] \
  && ok 'sandbox: sudo and snap are stubs' || nok sandbox 'real sudo or snap on PATH'

cat >"$W/list" <<'EOF'
Name     Version  Rev    Tracking       Publisher   Notes
core24   20260410 1643   latest/stable  canonical** base,disabled
core24   20260901 2124   latest/stable  canonical** base
firefox  154.0-1  8763   latest/stable  mozilla**   disabled
firefox  155.0-1  9036   latest/stable  mozilla**   -
snapd    2.76.3   27738  latest/stable  canonical** snapd,disabled
EOF
truncate -s 70M "$W/snaps/core24_1643.snap"; truncate -s 260M "$W/snaps/firefox_8763.snap"; truncate -s 50M "$W/snaps/snapd_27738.snap"
echo 04:00-05:00 >"$W/timer"
sn() { "$BIN/pc-snap" "$@"; }

ev 'line 2 is the pc help signature' '[[ "$(sed -n 2p "$BIN/pc-snap")" == "# pc snap "* ]]'
is 'status names the overlap and the disabled set' "$(sn)" 'timer: 04:00-05:00 · ∩ 00:50-01:50 0 min · ∩ 04:00-05:00 60 min · disabled 3 (380 MB)'
is 'timer reads the stored value' "$(sn timer)" '04:00-05:00'
is 'window dry run' "$(sn window 05:30-06:00)" 'would: snap refresh.timer 04:00-05:00 → 05:30-06:00'
for w in 04:30-05:30 05:00-05:30 03:00-04:00 01:00-02:00 23:30-01:00 00:00-23:59; do
  sn window "$w" >/dev/null 2>&1; is "window $w is refused (exit 3)" "$?" 3
done
for w in 5:30-06:00 05:30 05:30-05:30 'mon,05:30-06:00' ''; do
  sn window "$w" >/dev/null 2>&1; is "window '$w' is not a window (exit 2)" "$?" 2
done
ev 'refusals and dry runs never set' '! grep -q "snap set" "$W/calls"'
[ ! -e "$PC_LEDGER" ] && ok 'dry runs write no ledger' || nok 'dry run ledger' 'written'

out=$(sn window 05:30-06:00 --apply 2>&1); rc=$?
id=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
is 'apply exits 0 and ends with the undo id' "$rc|$(tail -1 <<<"$out")" "0|rollback: pc undo $id"
is 'timer set' "$(cat "$W/timer")" 05:30-06:00
is 'ledger row verified' "$(jq -rs --arg id "$id" 'map(select(.id == $id)) | "\(.[0].before)|\(.[0].after)|\(.[1].verified)"' "$PC_LEDGER")" '04:00-05:00|05:30-06:00|true'
is 'the same window again is nothing' "$(sn window 05:30-06:00 --apply)" 'nothing: refresh.timer is already 05:30-06:00'
"$BIN/pc-undo" "$id" --apply >"$W/undo" 2>&1; rc=$?
is 'pc undo restores the old window, verified' "$rc|$(cat "$W/timer")|$(jq -rs 'map(select(has("verified"))) | last | .verified' "$PC_LEDGER")" '0|04:00-05:00|true'

rm -f "$W/timer"
is 'an unset timer reads unset' "$(sn timer)" unset
out=$(sn window 22:00-23:00 --apply 2>&1); id=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
"$BIN/pc-undo" "$id" --apply >/dev/null 2>&1
ev 'undo of a window set on an unset timer unsets it' '[ ! -e "$W/timer" ]'

is 'prune dry run lists NAME REV MB' "$(sn prune | tr -s ' ')" $'NAME REV MB\ncore24 1643 70\nfirefox 8763 260\nsnapd 27738 50\nwould: remove 3 disabled revisions, 380 MB (--apply)'
ev 'prune dry run removes nothing' '! grep -q "snap remove" "$W/calls"'
out=$(sn prune --apply 2>&1); rc=$?
is 'prune apply exits 0, last line the rollback note' "$rc|$(tail -1 <<<"$out")" '0|rollback: none, revisions re-download on demand'
is 'one remove per disabled revision' "$(grep '^snap remove' "$W/calls" | tr '\n' ';')" 'snap remove core24 --revision=1643;snap remove firefox --revision=8763;snap remove snapd --revision=27738;'
is 'active revisions kept' "$(awk 'NR > 1 {print $1 "_" $3}' "$W/list" | tr '\n' ' ')" 'core24_2124 firefox_9036 '
is 'prune ledger row' "$(jq -r 'select(.target == "snap disabled revisions") | "\(.before)|\(.after)|\(.verified)"' "$PC_LEDGER")" '3 disabled revisions, 380 MB|0 disabled left|true'
is 'no disabled revisions is nothing' "$(sn prune --apply)" 'nothing: no disabled revisions'

echo 'stuck    1.0      7      latest/stable  x           disabled' >>"$W/list"
out=$(sn prune --apply 2>"$W/err"); rc=$?
is 'a failed remove exits 1 and is named' "$rc|$(cat "$W/err")" '1|pc snap: snap remove failed: stuck/7'
is 'its ledger row is unverified' "$(tail -1 "$PC_LEDGER" | jq -r '"\(.after)|\(.verified)"')" '1 disabled left, failed: stuck/7|false'

M="$W/mut"; mkdir -p "$M"; ln -s "$BIN/pclib.sh" "$M/pclib.sh"; [ -e "$BIN/env.sh" ] && ln -s "$BIN/env.sh" "$M/env.sh"
sed 's/ 04:00-05:00"$/"/' "$BIN/pc-snap" >"$M/pc-snap"; chmod +x "$M/pc-snap"
"$M/pc-snap" window 04:30-05:30 >/dev/null 2>&1; [ $? != 3 ] && ok 'mutant without the reboot fence is red' || nok mutant 'still refused'
sed 's/touch=1$/touch=0/' "$BIN/pc-snap" >"$M/pc-snap"
"$M/pc-snap" window 05:00-05:30 >/dev/null 2>&1; [ $? != 3 ] && ok 'mutant without the edge check is red' || nok mutant 'still refused'
sed 's/(^|,)disabled(,|\$)/disabledX/' "$BIN/pc-snap" >"$M/pc-snap"
[ "$("$M/pc-snap" prune)" != "$(sn prune)" ] && ok 'mutant without the disabled filter is red' || nok mutant 'same list'

is 'real ledger untouched' "$(real_sum)" "$before"
exit $bad
