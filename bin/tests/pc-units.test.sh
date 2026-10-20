#!/usr/bin/env bash
# PT13: `pc units` — fixture list/timers/failed, then live fleet/cost/guard/restart round trip.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/units"
U="$BIN/pc-units"
. "$HOME/agents/bin/tests/lib/assert.sh"
REAL_LEDGER="$HOME/agents/log/changes.jsonl"
real_rows=$(cat "$REAL_LEDGER" 2>/dev/null | wc -l)
export PC_LEDGER; PC_LEDGER=$(mktemp); trap 'rm -f "$PC_LEDGER"' EXIT

## --- fixture: list-units/list-timers, no real systemctl call --------------
is 'list --json is an array of 5 units' \
  "$(PC_FIXTURE=$FIX "$U" list --json | jq 'length')" 5
is 'list --failed --json finds the fixture failed unit' \
  "$(PC_FIXTURE=$FIX "$U" list --failed --json | jq -r '.[0].unit')" pt13-fixture.service
is 'list tags each row with its scope' \
  "$(PC_FIXTURE=$FIX "$U" list --json | jq -r '[.[]|.scope]|unique|sort|join(",")')" system,user
is 'timers --json reads the user fixture' \
  "$(PC_FIXTURE=$FIX "$U" timers --json | jq -r '.[0].unit')" sentinel-check.timer

## --- fixture: resolve_scope (no --user/--system given) --------------------
is 'resolve_scope picks user for a user-only unit' \
  "$(PC_FIXTURE=$FIX "$U" show pt13-user-only --json | jq -r .scope)" user
is 'resolve_scope picks system for a system-only unit' \
  "$(PC_FIXTURE=$FIX "$U" show pt13-system-only --json | jq -r .scope)" system
is 'resolve_scope prefers user when loaded in both and under ~/.config/systemd/user' \
  "$(PC_FIXTURE=$FIX "$U" show pt13-both --json | jq -r .scope)" user
PC_FIXTURE=$FIX "$U" show pt13-no-such-unit --json >/dev/null 2>&1
is 'show of a unit in neither scope exits 2' "$?" 2
PC_FIXTURE=$FIX "$U" stop pt13-no-such-unit >/dev/null 2>&1
is 'stop dry run of a unit in neither scope exits 2' "$?" 2

## --- fixture: fleet verdicts (T347-10) ------------------------------------
FF=$(mktemp -d); mkdir -p "$FF/bin"
cat >"$FF/bin/systemctl" <<'S'
#!/bin/sh
case "$*" in
  *list-unit-files*) echo "dark-eye-old.service enabled enabled"; echo "dark-eye.service enabled enabled"; exit 0;;
  *list-timers*) echo '[]'; exit 0;;
  *show*) ;;
  *) exit 0;;
esac
skip=0
for a in "$@"; do
  [ $skip = 1 ] && { skip=0; continue; }
  case "$a" in -p) skip=1; continue;; -*|show) continue;; esac
  case "$a" in
    agent@maintenance.service) set -- inactive dead static oneshot exit-code;;
    agent@*) set -- inactive dead static oneshot success;;
    dark-eye-old.service) set -- inactive dead enabled simple success;;
    *.timer) set -- active waiting enabled "" success;;
    *) set -- active running enabled simple success;;
  esac
  printf 'Id=%s\nActiveState=%s\nSubState=%s\nUnitFileState=%s\nType=%s\nResult=%s\n\n' "$a" "$1" "$2" "$3" "$4" "$5"
done
S
chmod +x "$FF/bin/systemctl"
fl=$(HOME="$FF" PC_FIXTURE=$FF "$U" fleet --json)
is 'fleet judges an enabled unit off the roster (dark-eye-old FAIL)' \
  "$(jq -r '.[]|select(.unit=="dark-eye-old.service")|.state' <<<"$fl")" FAIL
is 'fleet: a oneshot whose last run failed is FAIL' \
  "$(jq -r '.[]|select(.unit=="agent@maintenance.service")|.state' <<<"$fl")" FAIL
is 'fleet: an idle oneshot with Result=success is OK' \
  "$(jq -r '.[]|select(.unit=="agent@moodle-keeper.service")|.state' <<<"$fl")" OK
is 'fleet: a running enabled service is OK' \
  "$(jq -r '.[]|select(.unit=="dark-eye.service")|.state' <<<"$fl")" OK
is 'fleet: a roster unit discovered twice is listed once' \
  "$(jq '[.[]|select(.unit=="dark-eye.service")]|length' <<<"$fl")" 1
HOME="$FF" PC_FIXTURE=$FF "$U" fleet | grep -q 'dark-eye-old.service *inactive *dead *FAIL'
is 'fleet text shows the verdict column' "$?" 0
rm -rf "$FF"

## --- fixture: reset-failed (TSP-044) — stubbed systemctl on PATH, never a real unit ----
RF=$(mktemp -d); mkdir -p "$RF/bin"; echo failed >"$RF/state"
cat >"$RF/bin/systemctl" <<S
#!/bin/sh
echo "\$*" >>"$RF/argv"
case "\$*" in
  "--user show run-fixture.scope -p ActiveState --value") cat "$RF/state";;
  "--user reset-failed -- run-fixture.scope") echo inactive >"$RF/state";;
  *) exit 1;;
esac
S
chmod +x "$RF/bin/systemctl"
rf=$(PATH="$RF/bin:$PATH" "$U" reset-failed run-fixture.scope --user)
is 'reset-failed dry run prints would: failed → inactive' "$rf" 'would: run-fixture.scope failed → inactive'
is 'reset-failed dry run leaves the unit failed' "$(cat "$RF/state")" failed
rf=$(PATH="$RF/bin:$PATH" "$U" reset-failed run-fixture.scope --user --apply)
grep -q '^rollback: pc undo ' <<<"$rf" && ok 'reset-failed --apply prints a rollback line' || nok 'reset-failed --apply rollback line' "$rf"
is 'reset-failed --apply resets the stub unit' "$(cat "$RF/state")" inactive
rid=$(sed -n 's/^rollback: pc undo //p' <<<"$rf")
is 'reset-failed is ledgered and verified' "$(jq -s -r --arg i "$rid" 'map(select(.id==$i and .verified==true))|length' "$PC_LEDGER")" 1
is 'reset-failed ledger row has a no-op rollback' "$(jq -s -r --arg i "$rid" 'map(select(.id==$i and .rollback))[0].rollback|startswith(":")' "$PC_LEDGER")" true
PATH="$RF/bin:$PATH" "$U" reset-failed ssh.service --system --apply >/dev/null 2>&1
is 'reset-failed ssh is refused (guard)' "$?" 3
is 'selftest: the stub saw only show/reset-failed of run-fixture.scope' \
  "$(grep -cv -e '^--user show run-fixture.scope -p ActiveState --value$' -e '^--user reset-failed -- run-fixture.scope$' "$RF/argv")" 0
rm -rf "$RF"

## --- fixture: start of a oneshot (T533) — stubbed systemctl, per-unit state files ----
OS=$(mktemp -d); mkdir -p "$OS/bin"
for x in os-ok os-bad os-slow; do printf 'inactive\nsuccess\noneshot\nno\n' >"$OS/$x"; done
printf 'inactive\nsuccess\nsimple\nno\n' >"$OS/svc-simple"
cat >"$OS/bin/systemctl" <<S
#!/bin/sh
echo "\$*" >>"$OS/argv"
u=\$3; f="$OS/\$3"
case "\$2" in
  show) case "\$5" in ActiveState) n=1;; Result) n=2;; Type) n=3;; RemainAfterExit) n=4;; *) exit 1;; esac
        if [ "\$u" = os-slow ] && [ \$n = 1 ] && [ "\$(sed -n 1p "\$f")" = activating ]; then
          c=\$(( \$(cat "$OS/slow-reads" 2>/dev/null || echo 0) + 1 )); echo \$c >"$OS/slow-reads"
          [ \$c -ge 3 ] && sed -i '1s/.*/inactive/' "\$f"
        fi
        sed -n "\${n}p" "\$f";;
  start) u=\$4; f="$OS/\$4"
         case "\$u" in
           os-ok) ;;
           os-bad) sed -i '1s/.*/failed/;2s/.*/exit-code/' "\$f"; exit 3;;
           os-slow) sed -i '1s/.*/activating/' "\$f";;
           svc-simple) sed -i '1s/.*/active/' "\$f";;
         esac;;
  *) exit 1;;
esac
S
chmod +x "$OS/bin/systemctl"
row() { jq -s -c --arg i "$1" 'map(select(.id==$i)) | add' "$PC_LEDGER"; }
o=$(PATH="$OS/bin:$PATH" "$U" start os-ok --user)
is 'oneshot start dry run expects inactive success' "$o" 'would: os-ok inactive → inactive success'
o=$(PATH="$OS/bin:$PATH" "$U" start os-ok --user --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'oneshot ok: ledger row verified' "$(jq -r '.verified' <<<"$r")" true
is 'oneshot ok: observed inactive success' "$(jq -r '.observed' <<<"$r")" 'inactive success'
o=$(PATH="$OS/bin:$PATH" "$U" start os-bad --user --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'oneshot failed: ledger row unverified' "$(jq -r '.verified' <<<"$r")" false
is 'oneshot failed: observed starts with failed' "$(jq -r '.observed|startswith("failed")' <<<"$r")" true
o=$(PATH="$OS/bin:$PATH" "$U" start os-slow --user --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'oneshot still activating: polled until inactive, verified' "$(jq -r '.verified' <<<"$r")" true
o=$(PATH="$OS/bin:$PATH" "$U" start svc-simple --user --apply); r=$(row "$(sed -n 's/^rollback: pc undo //p' <<<"$o")")
is 'simple service: after stays active' "$(jq -r '.after' <<<"$r")" active
is 'simple service: verified on ActiveState alone' "$(jq -r '"\(.verified) \(.observed)"' <<<"$r")" 'true active'
is 'selftest: the oneshot stub saw only show/start of fixture units' \
  "$(grep -cvE '^--user (show (os-ok|os-bad|os-slow|svc-simple) -p [A-Za-z]+ --value|start -- (os-ok|os-bad|os-slow|svc-simple))$' "$OS/argv")" 0
rm -rf "$OS"

## --- live: fleet, cost, guard --------------------------------------------
"$U" fleet --json | jq -e 'map(.unit)|index("sentinel-check.timer")' >/dev/null
is 'fleet --json lists the roster (sentinel-check.timer present)' "$?" 0
"$U" cost dark-eye --user --json | jq -e '.mem_mb>0 and has("psi")' >/dev/null
is 'cost dark-eye --user --json has mem_mb>0 and psi' "$?" 0

"$U" restart ssh --apply >/dev/null 2>&1
is 'restart ssh --apply is refused (guard)' "$?" 3
"$U" restart ufw --apply >/dev/null 2>&1
is 'restart ufw --apply is refused (guard)' "$?" 3
"$U" restart claude-orchestrator --apply >/dev/null 2>&1
is 'restart claude-orchestrator --apply is refused (guard)' "$?" 3
"$U" restart dark-eye --apply >/dev/null 2>&1
is 'restart dark-eye --apply is refused without PC_ORCHESTRATOR' "$?" 3
before_pid=$(systemctl --user show dark-eye -p MainPID --value 2>/dev/null)
after_pid=$(systemctl --user show dark-eye -p MainPID --value 2>/dev/null)
is 'the guarded dark-eye call touched nothing (MainPID unchanged)' "$after_pid" "$before_pid"

## --- live: transient unit round trip (never a real unit) -----------------
systemctl --user reset-failed pt13-test >/dev/null 2>&1
systemd-run --user --unit pt13-test sleep 300 >/dev/null 2>&1
before_ts=$(systemctl --user show pt13-test -p ExecMainStartTimestampMonotonic --value 2>/dev/null)
out=$("$U" restart pt13-test --user --apply)
rid=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
[ -n "$rid" ] && ok 'restart pt13-test --apply prints a rollback line' \
  || nok 'restart pt13-test --apply prints a rollback line' "$out"
sleep 0.3
after_ts=$(systemctl --user show pt13-test -p ExecMainStartTimestampMonotonic --value 2>/dev/null)
[ -n "$before_ts" ] && [ "$after_ts" != "$before_ts" ] && ok 'restart gives pt13-test a new ExecMainStartTimestamp' \
  || nok 'restart gives pt13-test a new ExecMainStartTimestamp' "before=$before_ts after=$after_ts"
"$U" stop pt13-test --user --apply >/dev/null 2>&1
sleep 0.3
left=$(systemctl --user list-units 'pt13*' --no-legend 2>/dev/null | wc -l)
is 'pt13-test is gone after stop' "$left" 0
systemctl --user reset-failed pt13-test >/dev/null 2>&1
grep -q "\"id\":\"$rid\"" "${PC_LEDGER:-/dev/null}" && ok 'the rollback id is in the temp ledger' \
  || nok 'the rollback id is in the temp ledger' "${PC_LEDGER:-unset}"
is 'the real change ledger is untouched' "$(cat "$REAL_LEDGER" 2>/dev/null | wc -l)" "$real_rows"

[ $bad = 0 ] && echo 'PASS pc-units' || echo 'FAIL pc-units'
exit $bad
