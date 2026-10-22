#!/usr/bin/env bash
# T501/T516/T1064/T1139: moodle-cron turns "upgrade pending" (one line per hour) and "upgrade running" into rc 0 + one skip line; task failures and clean runs keep their rc; an idle site runs only on every 10th minute.
# Stub docker and date on PATH, a temp state dir and a fixture dataroot; never real docker or a real container (AGENTS.md §5.6).
# shellcheck disable=SC1091,SC2015,SC2154  # assert.sh sets bad; ok/nok never fail
set -uo pipefail
. "$HOME/agents/bin/tests/lib/assert.sh"
CRON="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/moodle-cron"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/stubs" "$TMP/state" "$TMP/data/sessions"
touch "$TMP/data/sessions/sess_fixture"
cat >"$TMP/stubs/docker" <<'EOF'
#!/bin/sh
echo "$*" >>"$FAKE_CALLS"
case "$1" in
  inspect) echo "$FAKE_ROOT"; exit 0 ;;
  logs) [ -n "$FAKE_LOG" ] && echo "$FAKE_LOG"; exit 0 ;;
esac
case "$FAKE_CRON" in
  pending) echo "Moodle upgrade pending, cron execution suspended."; exit 1 ;;
  upgraderunning) echo "!!! Site is being upgraded, please retry later. !!!"; echo "Debug info:"; echo "Error code: upgraderunning"; exit 1 ;;
  taskfail) echo "Scheduled task failed: \\core\\task\\foo (Foo)"; exit 1 ;;
  failline) echo "Execute scheduled task: Foo"; echo "Scheduled task failed: Foo"; exit 0 ;;
  clean) echo "Cron run completed correctly"; exit 0 ;;
esac
EOF
cat >"$TMP/stubs/date" <<'EOF'
#!/bin/sh
[ "$1" = +%M ] && [ -n "$FAKE_MIN" ] && { echo "$FAKE_MIN"; exit 0; }
exec /usr/bin/date "$@"
EOF
chmod +x "$TMP/stubs/docker" "$TMP/stubs/date"
run() { FAKE_CRON=$1 FAKE_CALLS="$TMP/calls" FAKE_ROOT="${FAKE_ROOT-$TMP/data}" FAKE_LOG="${FAKE_LOG-}" FAKE_MIN="${FAKE_MIN:-07}" MOODLE_CRON_STATE="$TMP/state" PATH="$TMP/stubs:/usr/bin:/bin" "$CRON" fixture-app-1; }
execs() { grep -c '^exec ' "$TMP/calls" 2>/dev/null; }

out=$(run pending); rc=$?
is "pending: rc 0" "$rc" 0
is "pending: one skip line" "$out" "moodle-cron: fixture-app-1 upgrade pending, skipped"
grep -q '^exec fixture-app-1 php .*admin/cli/cron.php' "$TMP/calls" && ok "runs cron.php in the named container" || nok "runs cron.php in the named container" "$(cat "$TMP/calls")"
out=$(run pending); rc=$?
is "pending again within the hour: rc 0" "$rc" 0
is "pending again within the hour: quiet" "$out" ""
touch -d '-61 min' "$TMP/state/moodle-cron-fixture-app-1.pending.said"
is "pending after an hour: line again" "$(run pending)" "moodle-cron: fixture-app-1 upgrade pending, skipped"
touch -d '2026-01-01 03:04' "$TMP/state/moodle-cron-fixture-app-1.pending"
run pending >/dev/null
is "pending mark keeps the first time" "$(date -r "$TMP/state/moodle-cron-fixture-app-1.pending" +%H:%M)" "03:04"

out=$(run upgraderunning); rc=$?
is "upgraderunning: rc 0" "$rc" 0
is "upgraderunning: one skip line" "$out" "skipped: upgrade running"

out=$(run taskfail); rc=$?
is "task failure: rc 1" "$rc" 1
grep -q 'Scheduled task failed' <<<"$out" && ok "task failure: output shown" || nok "task failure: output shown" "$out"
[ ! -e "$TMP/state/moodle-cron-fixture-app-1.pending" ] && ok "pending mark cleared once cron runs" || nok "pending mark cleared once cron runs" "still there"
[ ! -e "$TMP/state/moodle-cron-fixture-app-1.pending.said" ] && ok "hourly mark cleared once cron runs" || nok "hourly mark cleared once cron runs" "still there"

out=$(run failline); rc=$?
is "failure line with rc 0: rc unchanged" "$rc" 0
grep -q 'Scheduled task failed' <<<"$out" && ok "failure line with rc 0: output shown" || nok "failure line with rc 0: output shown" "$out"

out=$(run clean); rc=$?
is "clean: rc 0" "$rc" 0
is "clean: quiet" "$out" ""

touch -d '-31 min' "$TMP/data/sessions/sess_fixture"
before=$(execs); out=$(FAKE_MIN=07 run clean); rc=$?
is "idle at :07: rc 0" "$rc" 0
is "idle at :07: quiet" "$out" ""
is "idle at :07: no exec" "$(execs)" "$before"
is "idle at :07: skip counted" "$(cat "$TMP/state/moodle-cron-fixture-app-1.idle")" 1
before=$(execs); FAKE_MIN=10 run clean >/dev/null
is "idle at :10: exec" "$(execs)" $((before + 1))
[ ! -e "$TMP/state/moodle-cron-fixture-app-1.idle" ] && ok "idle at :10: counter reset" || nok "idle at :10: counter reset" "still there"
echo 9 >"$TMP/state/moodle-cron-fixture-app-1.idle"
before=$(execs); FAKE_MIN=13 run clean >/dev/null
is "idle, 10th skip (missed :10): exec" "$(execs)" $((before + 1))
before=$(execs); MOODLE_CRON_IDLE_EVERY=1 FAKE_MIN=07 run clean >/dev/null
is "MOODLE_CRON_IDLE_EVERY=1: exec every minute" "$(execs)" $((before + 1))
touch "$TMP/data/sessions/sess_fixture"
before=$(execs); FAKE_MIN=07 run clean >/dev/null
is "active session at :07: exec" "$(execs)" $((before + 1))
rm "$TMP/state/moodle-cron-fixture-app-1.dataroot"
before=$(execs); FAKE_ROOT='' FAKE_LOG='"GET / HTTP/1.1" 200' FAKE_MIN=07 run clean >/dev/null
is "no sessions dir, access-log line: exec" "$(execs)" $((before + 1))
before=$(execs); FAKE_ROOT='' FAKE_LOG='' FAKE_MIN=07 run clean >/dev/null
is "no sessions dir, no access-log line at :07: no exec" "$(execs)" "$before"

out=$(PATH="$TMP/stubs:/usr/bin:/bin" "$CRON" 2>&1); rc=$?
is "no container: rc 2" "$rc" 2
exit "$bad"
