#!/usr/bin/env bash
# PT13: `pc units` — fixture list/timers/failed, then live fleet/cost/guard/restart round trip.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/units"
U="$BIN/pc-units"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

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

[ $bad = 0 ] && echo 'PASS pc-units' || echo 'FAIL pc-units'
exit $bad
