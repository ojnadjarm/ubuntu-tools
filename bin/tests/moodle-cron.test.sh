#!/usr/bin/env bash
# T501/T516: moodle-cron turns "upgrade pending" and "upgrade running" into rc 0 + one skip line; task failures and clean runs keep their rc.
# Stub docker on PATH and a temp state dir; never real docker or a real container (AGENTS.md §5.6).
# shellcheck disable=SC1091,SC2015,SC2154  # assert.sh sets bad; ok/nok never fail
set -uo pipefail
. "$HOME/agents/bin/tests/lib/assert.sh"
CRON="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/moodle-cron"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/stubs" "$TMP/state"
cat >"$TMP/stubs/docker" <<'EOF'
#!/bin/sh
echo "$*" >>"$FAKE_CALLS"
case "$FAKE_CRON" in
  pending) echo "Moodle upgrade pending, cron execution suspended."; exit 1 ;;
  upgraderunning) echo "!!! Site is being upgraded, please retry later. !!!"; echo "Debug info:"; echo "Error code: upgraderunning"; exit 1 ;;
  taskfail) echo "Scheduled task failed: \\core\\task\\foo (Foo)"; exit 1 ;;
  failline) echo "Execute scheduled task: Foo"; echo "Scheduled task failed: Foo"; exit 0 ;;
  clean) echo "Cron run completed correctly"; exit 0 ;;
esac
EOF
chmod +x "$TMP/stubs/docker"
run() { FAKE_CRON=$1 FAKE_CALLS="$TMP/calls" MOODLE_CRON_STATE="$TMP/state" PATH="$TMP/stubs:/usr/bin:/bin" "$CRON" fixture-app-1; }

out=$(run pending); rc=$?
is "pending: rc 0" "$rc" 0
is "pending: one line" "$(printf '%s\n' "$out" | wc -l)" 1
[[ $out =~ ^skipped:\ upgrade\ pending\ since\ [0-9]{2}:[0-9]{2}$ ]] && ok "pending: skip line" || nok "pending: skip line" "$out"
grep -q '^exec fixture-app-1 php .*admin/cli/cron.php' "$TMP/calls" && ok "runs cron.php in the named container" || nok "runs cron.php in the named container" "$(cat "$TMP/calls")"
touch -d '2026-01-01 03:04' "$TMP/state/moodle-cron-fixture-app-1.pending"
is "pending again: since keeps the first time" "$(run pending)" "skipped: upgrade pending since 03:04"

out=$(run upgraderunning); rc=$?
is "upgraderunning: rc 0" "$rc" 0
is "upgraderunning: one skip line" "$out" "skipped: upgrade running"

out=$(run taskfail); rc=$?
is "task failure: rc 1" "$rc" 1
grep -q 'Scheduled task failed' <<<"$out" && ok "task failure: output shown" || nok "task failure: output shown" "$out"
[ ! -e "$TMP/state/moodle-cron-fixture-app-1.pending" ] && ok "pending mark cleared once cron runs" || nok "pending mark cleared once cron runs" "still there"

out=$(run failline); rc=$?
is "failure line with rc 0: rc unchanged" "$rc" 0
grep -q 'Scheduled task failed' <<<"$out" && ok "failure line with rc 0: output shown" || nok "failure line with rc 0: output shown" "$out"

out=$(run clean); rc=$?
is "clean: rc 0" "$rc" 0
is "clean: quiet" "$out" ""

out=$(PATH="$TMP/stubs:/usr/bin:/bin" "$CRON" 2>&1); rc=$?
is "no container: rc 2" "$rc" 2
exit "$bad"
