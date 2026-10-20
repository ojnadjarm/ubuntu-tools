#!/usr/bin/env bash
# Fixtures for ~/agents/bin/fleet-ci-daily under ci-autofix: green, load noise (red then green on the serial re-run), red (one fix
# attempt, one push) and a contention re-run, on a fake HOME
# with a two-file fixture suite and stub agent-run, notify-owner and pc (AGENTS.md §5.6), proven by a selftest; plus the units and the doctor row.
set -uo pipefail
SRC="$HOME/agents/bin"; UNITS="$HOME/agents/units"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
bad=0
ok() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (want $2, got $3)"; bad=$((bad+1)); fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }

H="$WORK/home"; B="$H/agents/bin"; mkdir -p "$B/tests" "$H/agents/ci-fix" "$WORK/path"
cp "$SRC/fleet-ci-daily" "$SRC/ci-autofix" "$SRC/auditlib.py" "$SRC/ci-window" "$SRC/quiet-gate" "$SRC/wait-for" "$B/"
cp "$SRC/tests/run.sh" "$B/tests/"
cp "$SRC/../ci-fix/BRIEF.template.md" "$H/agents/ci-fix/"
unset CI_AUTOFIX_RERUN
export CI_UNITS= RUN_TESTS_LOCK="$WORK/suite.lock" RUN_TESTS_SKIP_DEPS="$WORK/dpkg" CI_LOADAVG="$WORK/loadavg" WAIT_FOR_DIR="$WORK/waits" CI_QUIET_EVERY=1 CI_QUIET_CAP=2 FIX="$WORK"
for s in agent-run notify-owner pc; do
  printf '#!/bin/sh\n# STUB\nprintf "%%s\\n" "$*" >>"%s/%s.calls"\n' "$WORK" "$s" >"$B/$s"
  cp "$B/$s" "$WORK/path/$s"
done
printf 'case "$*" in "${PC_FAIL:-@none@}"*) exit 5;; esac\n' >>"$B/pc"
# The fixer stub: the machine is quiet again once it has run; TOUCH_AFTER_FIX edits a.test.sh.
printf '[ -n "${QUIET_AFTER_FIX:-}" ] && echo "1.00 1 1 1/100 1" >"%s"\n' "$CI_LOADAVG" >>"$B/agent-run"
printf '[ -n "${TOUCH_AFTER_FIX:-}" ] && touch "%s"\nexit 0\n' "$B/tests/a.test.sh" >>"$B/agent-run"
# Fixture suite: a.test.sh always green; b.test.sh red for its first FAILS runs.
printf '#!/bin/sh\necho x >>"$FIX/a.runs"; echo a fine\n' >"$B/tests/a.test.sh"
cat >"$B/tests/b.test.sh" <<'EOF'
#!/bin/sh
n=$(cat "$FIX/b.count" 2>/dev/null || echo 0); n=$((n + 1)); echo $n >"$FIX/b.count"
[ "$n" -le "${FAILS:-0}" ] && { echo "FAIL b run $n"; exit 1; }
echo "b fine"
EOF
chmod +x "$B/"* "$B/tests/"* "$WORK/path/"*

LOG="$H/agents/log/fleet-ci/$(date +%F).txt"; FIRST="${LOG%.txt}.first.txt"; NOTE="$H/agents/state/ci-fix/$(date +%F).md"
calls() { grep -c . "$WORK/$1.calls" 2>/dev/null || echo 0; }
run() {
  rm -rf "$WORK"/*.calls "$WORK/b.count" "$WORK/a.runs" "$H/agents/state/ci-fix"
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
ok "green: one quiet wait, no re-run" "1 no" "$(grep -c '^ci-window:' "$LOG") $(has 're-run |' "$(cat "$LOG")")"

# A live ailearning nightly (stub systemctl says active) inside a fake fleet-ci-daily.service cgroup: the empty CI_UNITS keeps the gate on load alone.
mkdir -p "$WORK/busy"; printf '#!/bin/sh\n[ "$3" = ailearning-ci-daily.service ] && echo active || echo inactive\n' >"$WORK/busy/systemctl"; chmod +x "$WORK/busy/systemctl"
echo "0::/user.slice/user@$(id -u).service/app.slice/fleet-ci-daily.service" >"$WORK/cgroup"
ok "selftest: stub reports ailearning active" active "$("$WORK/busy/systemctl" --user is-active ailearning-ci-daily.service)"
PATH="$WORK/busy:$PATH" CI_CGROUP="$WORK/cgroup" FAILS=0 run; ok "live ailearning nightly: rc 0" 0 $?
ok "live ailearning nightly: the quiet gate passes on load alone" "yes no" "$(has 'ci-window: 1-min load 1.00 < 4' "$(cat "$LOG")") $(has 'still active' "$(cat "$LOG")")"

FAILS=1 run; ok "noise: rc 0" 0 $?
ok "noise: b ran twice" 2 "$(cat "$WORK/b.count")"
ok "noise: listed as load noise" yes "$(has 'load-noise: bin/tests/b.test.sh' "$(cat "$LOG")")"
ok "noise: no red line" no "$(has '✖ fleet ci red' "$(cat "$LOG")")"
ok "noise: summary after the re-run is the doctor's PASS" "PASS 2/2 files after a serial re-run of 1+0" "$(grep -E '^(PASS|FAIL) [0-9]+/[0-9]+ files' "$LOG" | tail -1)"
ok "noise: no fix attempt, no push" "0 0" "$(calls agent-run) $(calls notify-owner)"

FAILS=4 run; ok "red: rc 1" 1 $?
ok "red: one fix attempt" 1 "$(calls agent-run)"
ok "red: b ran 3 times (first pass, its serial re-run, the scoped re-run)" 3 "$(cat "$WORK/b.count")"
ok "rerun scope red-only: a ran once" 1 "$(grep -c . "$WORK/a.runs")"
ok "rerun scope red-only: the scope line" yes "$(has "rerun scope: 1 red + 0 touched (first pass: ~/agents/log/fleet-ci/$(date +%F).first.txt)" "$(cat "$LOG")")"
ok "rerun scope red-only: PASS/FAIL over the scope" "FAIL 0/1 files in the rerun scope" "$(grep -E '^(PASS|FAIL) [0-9]+/[0-9]+ files' "$LOG" | tail -1)"
ok "red: one push" 1 "$(calls notify-owner)"
push="$(cat "$WORK/notify-owner.calls")"
ok "red: push is high" yes "$(has '-p high -t fleet nightly' "$push")"
ok "red: cause names the failing file" yes "$(has '✖ fleet ci red: bin/tests/b.test.sh' "$push")"
ok "red: first pass summary kept in <date>.first.txt" yes "$(has 'FAIL 1/2 files' "$(cat "$FIRST")")"
ok "red: red twice is no load noise" no "$(has 'load-noise' "$(cat "$LOG")")"
ok "red: red line is the log's last" "✖ fleet ci red: bin/tests/b.test.sh" "$(tail -1 "$LOG")"
ok "red: no contention at load 1" no "$(has 'ci-load: contention' "$(cat "$LOG")")"
ok "red: fixer brief names ~/agents" yes "$(has 'Find the cause in ~/agents' "$(cat "$H/agents/ci-fix/BRIEF.md")")"

FAILS=4 TOUCH_AFTER_FIX=1 run; ok "rerun scope touched: rc 1" 1 $?
ok "rerun scope touched: a test the fixer edited joins the scope" "yes 2" "$(has 'rerun scope: 1 red + 1 touched' "$(cat "$LOG")") $(grep -c . "$WORK/a.runs")"
ok "rerun scope touched: PASS/FAIL over the scope" "FAIL 1/2 files in the rerun scope" "$(grep -E '^(PASS|FAIL) [0-9]+/[0-9]+ files' "$LOG" | tail -1)"

FAILS=2 LOAD=9.00 QUIET_AFTER_FIX=1 run; ok "contention: rc 0 after the quiet re-run" 0 $?
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
ok "doctor: last green run (a rerun scope) is OK" yes "$(has 'OK 2026-10-18.txt: PASS 1/1 files in the rerun scope' "$(row)")"
printf 'FAIL 1/2 files in 3 s\n' >"$D/2026-10-19.txt"
ok "doctor: newest red run is a WARN" yes "$(has 'WARN 2026-10-19.txt: FAIL 1/2 files' "$(row)")"

# Skip-unchanged (T717): Mon–Sat a heavy green skill test nothing touched is skipped; Sunday and FLEET_CI_FULL=1 run it.
S="$H/agents/skills/heavy/tests"; mkdir -p "$S"; printf 'touch "$FIX/heavy.ran"\n' >"$S/h.test.sh"; : >"$WORK/dpkg"
mkdir -p "$H/agents/state/skip-deps"
day() {
  find "$H/agents/skills" "$WORK/dpkg" "$H/agents/state/skip-deps" -exec touch -h -d '1 hour ago' {} +; rm -f "$WORK/heavy.ran"
  printf '%s\tskills/heavy/tests/h.test.sh\t30.0\t0\t1.0\t25.0\n' "$(date +%FT%T)" >>"$H/agents/state/test-timings-history.tsv"
  echo "1.00 1 1 1/100 1" >"$CI_LOADAVG"; HOME="$H" "$@" bash "$B/fleet-ci-daily" >/dev/null 2>&1
  test -e "$WORK/heavy.ran" && echo ran || echo skipped
}
# The first run stamps the apt inputs (run.sh apt_dep); later runs see that stamp an hour old.
day env FLEET_CI_DOW=3 >/dev/null
ok "skip-unchanged: Wednesday skips the untouched heavy skill test" skipped "$(day env FLEET_CI_DOW=3)"
ok "skip-unchanged: the log says so" yes "$(has 'SKIP unchanged skills/heavy/tests/h.test.sh (green' "$(cat "$LOG")")"
ok "skip-unchanged: summary counts the skip" yes "$(has 'skipped 1, saved ~25.0 CPU s' "$(cat "$LOG")")"
ok "skip-unchanged: Sunday runs everything" ran "$(day env FLEET_CI_DOW=7)"
ok "skip-unchanged: FLEET_CI_FULL=1 runs everything" ran "$(day env FLEET_CI_DOW=3 FLEET_CI_FULL=1)"

# Rerun scope called directly (T733): an empty scope exits with the first pass's rc; an edited skill dir adds its tests.
first="$WORK/first.txt"; printf '✖ fleet ci red: run.sh rc 3\n' >"$first"; rm -f "$WORK/heavy.ran" "$WORK/a.runs"
HOME="$H" CI_AUTOFIX_RERUN="$first" bash "$B/fleet-ci-daily" >/dev/null 2>&1; ok "rerun scope empty: rc of the first pass" 3 $?
ok "rerun scope empty: nothing ran" "yes no no" "$(has 'rerun scope: 0 red + 0 touched' "$(cat "$LOG")") $(test -e "$WORK/heavy.ran" && echo yes || echo no) $(test -e "$WORK/a.runs" && echo yes || echo no)"
echo edit >>"$H/agents/skills/heavy/notes.md"
HOME="$H" CI_AUTOFIX_RERUN="$first" bash "$B/fleet-ci-daily" >/dev/null 2>&1; ok "rerun scope skill touched: rc 0" 0 $?
ok "rerun scope skill touched: its test ran" "yes ran" "$(has 'rerun scope: 0 red + 1 touched' "$(cat "$LOG")") $(test -e "$WORK/heavy.ran" && echo ran || echo skipped)"
ok "rerun scope skill touched: PASS over the scope" "PASS 1/1 files in the rerun scope" "$(grep -E '^(PASS|FAIL) [0-9]+/[0-9]+ files' "$LOG" | tail -1)"

# A failing agent-verify --recheck (T911): logged in the nightly log, the run goes on.
printf '#!/bin/sh\nexit 4\n' >"$B/agent-verify"; chmod +x "$B/agent-verify"
FAILS=0 run; ok "agent-verify fails: nightly still rc 0" 0 $?
ok "agent-verify fails: the log says so" yes "$(has 'fleet-ci-daily: agent-verify --recheck failed rc 4' "$(cat "$LOG")")"
rm -f "$B/agent-verify"
# Recheck (T853): the newest log's red files re-run alone; all green → reset-failed + need resolve via pc (stub); any red → nothing cleared.
grep -q 'systemctl' "$B/fleet-ci-daily"; ok "selftest: recheck reaches systemd only through pc" 1 $?
L="${LOG%/*}"; recheck() { rm -f "$WORK/pc.calls" "$WORK/b.count"; echo "1.00 1 1 1/100 1" >"$CI_LOADAVG"; HOME="$H" bash "$B/fleet-ci-daily" --recheck; }
rm -f "$L"/*.txt; printf 'FAIL 1/2 files\n✖ fleet ci red: bin/tests/a.test.sh\n' >"$L/2026-10-18.txt"
printf 'FAIL 0/2 files\n✖ fleet ci red: bin/tests/a.test.sh bin/tests/b.test.sh\n' >"$L/2026-10-19.txt"; : >"$L/2026-10-19.first.txt"
out="$(FAILS=0 recheck)"; ok "recheck green: rc 0" 0 $?
ok "recheck green: newest log gets the line" yes "$(has '2/2 green (bin/tests/a.test.sh bin/tests/b.test.sh)' "$(tail -1 "$L/2026-10-19.txt")")"
ok "recheck green: unit reset" yes "$(has 'units reset-failed fleet-ci-daily.service --user --apply' "$(cat "$WORK/pc.calls")")"
ok "recheck green: need resolved" yes "$(has 'need resolve fleet nightly --fixed recheck green: bin/tests/a.test.sh bin/tests/b.test.sh --apply' "$(cat "$WORK/pc.calls")")"
ok "recheck green: the quiet gate ran" yes "$(has 'ci-window: 1-min load' "$out")"
out="$(FAILS=0 PC_FAIL='need resolve' recheck)"; ok "recheck green, resolve fails: rc 3" 3 $?
ok "recheck green, resolve fails: the log says so" yes "$(has 'fleet-ci-daily: need resolve failed rc 5' "$(tail -1 "$L/2026-10-19.txt")")"
out="$(FAILS=0 PC_FAIL='units reset-failed' recheck)"; ok "recheck green, reset-failed fails: rc 3" 3 $?
ok "recheck green, reset-failed fails: the log says so" yes "$(has 'fleet-ci-daily: reset-failed failed rc 5' "$(tail -1 "$L/2026-10-19.txt")")"
ok "recheck green, reset-failed fails: need left open" no "$(has 'need resolve' "$(cat "$WORK/pc.calls")")"
printf '✖ fleet ci red: bin/tests/b.test.sh\n' >"$LOG"
out="$(FAILS=5 recheck)"; ok "recheck red: rc 1" 1 $?
ok "recheck red: today's log first, b alone" "yes 1" "$(has 'recheck ' "$(tail -1 "$LOG")") $(cat "$WORK/b.count")"
ok "recheck red: the line counts it" yes "$(has '0/1 green (bin/tests/b.test.sh)' "$(tail -1 "$LOG")")"
ok "recheck red: nothing cleared" 0 "$(calls pc)"
printf 'PASS 2/2 files\n' >"$LOG"
out="$(recheck)"; rc=$?; ok "recheck green log: nothing red, rc 0" "yes 0" "$(has 'recheck: nothing red' "$out") $rc"
rm -f "$L"/*.txt; out="$(recheck)"; ok "recheck no log: rc 0" 0 $?
ok "recheck no log: nothing red, nothing cleared" "yes 0" "$(has 'recheck: nothing red' "$out") $(calls pc)"

echo "fleet-ci-daily.test: $bad failed"
[ "$bad" -eq 0 ]
