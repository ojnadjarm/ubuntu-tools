#!/usr/bin/env bash
# Fixtures for ~/agents/bin/fleet-ci-daily under ci-autofix: green, red (one fix attempt, one push) and a contention re-run, on a fake HOME
# with a two-file fixture suite and stub agent-run, notify-owner and pc (AGENTS.md §5.6), proven by a selftest; plus the units and the doctor row.
set -uo pipefail
SRC="$HOME/agents/bin"; UNITS="$HOME/agents/units"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
bad=0
ok() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (want $2, got $3)"; bad=$((bad+1)); fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }

H="$WORK/home"; B="$H/agents/bin"; mkdir -p "$B/tests" "$H/agents/ci-fix" "$WORK/path"
cp "$SRC/fleet-ci-daily" "$SRC/ci-autofix" "$SRC/auditlib.py" "$SRC/ci-window" "$SRC/wait-for" "$B/"
cp "$SRC/tests/run.sh" "$B/tests/"
cp "$SRC/../ci-fix/BRIEF.template.md" "$H/agents/ci-fix/"
export CI_LOADAVG="$WORK/loadavg" WAIT_FOR_DIR="$WORK/waits" CI_QUIET_EVERY=1 CI_QUIET_CAP=2 FIX="$WORK"
for s in agent-run notify-owner pc; do
  printf '#!/bin/sh\n# STUB\nprintf "%%s\\n" "$*" >>"%s/%s.calls"\n' "$WORK" "$s" >"$B/$s"
  cp "$B/$s" "$WORK/path/$s"
done
# The fixer stub: the machine is quiet again once it has run.
printf '[ -n "${QUIET_AFTER_FIX:-}" ] && echo "1.00 1 1 1/100 1" >"%s"\nexit 0\n' "$CI_LOADAVG" >>"$B/agent-run"
# Fixture suite: a.test.sh always green; b.test.sh red for its first FAILS runs.
printf '#!/bin/sh\necho a fine\n' >"$B/tests/a.test.sh"
cat >"$B/tests/b.test.sh" <<'EOF'
#!/bin/sh
n=$(cat "$FIX/b.count" 2>/dev/null || echo 0); n=$((n + 1)); echo $n >"$FIX/b.count"
[ "$n" -le "${FAILS:-0}" ] && { echo "FAIL b run $n"; exit 1; }
echo "b fine"
EOF
chmod +x "$B/"* "$B/tests/"* "$WORK/path/"*

LOG="$H/agents/log/fleet-ci/$(date +%F).txt"; NOTE="$H/agents/state/ci-fix/$(date +%F).md"
calls() { grep -c . "$WORK/$1.calls" 2>/dev/null || echo 0; }
run() {
  rm -rf "$WORK"/*.calls "$WORK/b.count" "$H/agents/state/ci-fix"
  echo "${LOAD:-1.00} 1 1 1/100 1" >"$CI_LOADAVG"
  HOME="$H" PATH="$WORK/path:$PATH" bash "$B/ci-autofix" --repo "$H/agents" --log "$LOG" "fleet nightly" -- "$B/fleet-ci-daily"
}

# Selftest: every launcher and pusher is a stub, the runner reaches verbs only under $HOME/agents/bin, and run.sh sees only the fixture suite.
for s in agent-run notify-owner pc; do
  grep -q '^# STUB' "$B/$s" && grep -q '^# STUB' "$(PATH="$WORK/path:$PATH"; command -v "$s")"; ok "selftest: $s is a stub" 0 $?
done
grep -Eq '(^|[;&|(] *)(agent-run|notify-owner|pc|ci-window|run\.sh) ' "$B/fleet-ci-daily"; ok "selftest: no verb called off \$B" 1 $?
ok "selftest: fixture suite is 2 files" 2 "$(ls "$B/tests"/*.test.sh | wc -l)"
[ "$bad" -eq 0 ] || { echo "selftest failed: nothing runs"; exit 1; }

FAILS=0 run; ok "green: rc 0" 0 $?
ok "green: summary in the dated log" yes "$(has 'PASS 2/2 files' "$(cat "$LOG")")"
ok "green: the quiet gate ran first" yes "$(has 'ci-window: 1-min load 1.00 < 4' "$(cat "$LOG")")"
ok "green: no fix attempt" 0 "$(calls agent-run)"
ok "green: no push" 0 "$(calls notify-owner)"

FAILS=2 run; ok "red: rc 1" 1 $?
ok "red: one fix attempt" 1 "$(calls agent-run)"
ok "red: suite ran twice" 2 "$(cat "$WORK/b.count")"
ok "red: one push" 1 "$(calls notify-owner)"
push="$(cat "$WORK/notify-owner.calls")"
ok "red: push is high" yes "$(has '-p high -t fleet nightly' "$push")"
ok "red: cause names the failing file" yes "$(has '✖ fleet ci red: bin/tests/b.test.sh' "$push")"
ok "red: summary in the dated log" yes "$(has 'FAIL 1/2 files' "$(cat "$LOG")")"
ok "red: no contention at load 1" no "$(has 'ci-load: contention' "$(cat "$LOG")")"
ok "red: fixer brief names ~/agents" yes "$(has 'Find the cause in ~/agents' "$(cat "$H/agents/ci-fix/BRIEF.md")")"

FAILS=1 LOAD=9.00 QUIET_AFTER_FIX=1 run; ok "contention: rc 0 after the quiet re-run" 0 $?
ok "contention: one fix attempt" 1 "$(calls agent-run)"
ok "contention: no push" 0 "$(calls notify-owner)"
ok "contention: note waits for quiet" yes "$(has 'contention: re-run once the machine is quiet' "$(cat "$NOTE")")"
ok "contention: note keeps the load line" yes "$(has 'ci-load: contention (1-min load 9.00 before' "$(cat "$NOTE")")"
ok "contention: green resolves the need" yes "$(has 'need resolve fleet nightly ci failed' "$(cat "$WORK/pc.calls" 2>/dev/null)")"

exec 9>"$H/agents/state/fleet-ci.lock"; flock -n 9
HOME="$H" bash "$B/fleet-ci-daily" 2>/dev/null; ok "second run while locked: rc 75" 75 $?
exec 9>&-
HOME="$H" bash "$B/fleet-ci-daily" --nope 2>/dev/null; ok "unknown argument: rc 2" 2 $?

ok "timer at 02:10" yes "$(has 'OnCalendar=*-*-* 02:10' "$(cat "$UNITS/fleet-ci-daily.timer")")"
ok "service wraps the runner in ci-autofix" yes "$(has 'ci-autofix --repo %h/agents --log %h/agents/log/fleet-ci/$$(date +%%F).txt "fleet nightly" -- %h/agents/bin/fleet-ci-daily' "$(cat "$UNITS/fleet-ci-daily.service")")"

D="$WORK/doctor"; mkdir -p "$D"; cp "$LOG" "$D/2026-10-18.txt"
row() { PC_FLEET_CI_DIR="$D" "$SRC/pc" doctor --quick --json 2>/dev/null | jq -r '.[] | select(.name == "fleet-ci") | .status + " " + .detail'; }
ok "doctor: last green run is OK" yes "$(has 'OK 2026-10-18.txt: PASS 2/2 files' "$(row)")"
printf 'FAIL 1/2 files in 3 s\n' >"$D/2026-10-19.txt"
ok "doctor: newest red run is a WARN" yes "$(has 'WARN 2026-10-19.txt: FAIL 1/2 files' "$(row)")"

echo "fleet-ci-daily.test: $bad failed"
[ "$bad" -eq 0 ]
