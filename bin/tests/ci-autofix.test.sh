#!/usr/bin/env bash
# Fixtures for ~/agents/bin/ci-autofix: a fixture CI that fails once then passes, or fails twice; stub agent-run, notify-owner and pc
# under a fake HOME (AGENTS.md §5.6: no real agent launch, no real push), proven by a selftest before the first run.
set -uo pipefail
SRC="$HOME/agents/bin"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

H="$WORK/home"; B="$H/agents/bin"; mkdir -p "$B" "$H/agents/ci-fix" "$WORK/path" "$WORK/repo"
cp "$SRC/ci-autofix" "$SRC/auditlib.py" "$SRC/ci-window" "$SRC/quiet-gate" "$SRC/wait-for" "$B/"
unset CI_DEADLINE CI_BUDGET CI_RUN_NEED CI_AUTOFIX CI_AUTOFIX_RERUN   # a nightly under ci-autofix exports its own budget
export CI_UNITS= CI_LOADAVG="$WORK/loadavg" WAIT_FOR_DIR="$WORK/waits" CI_QUIET_EVERY=1
echo "1.00 1 1 1/100 1" >"$CI_LOADAVG"
cp "$SRC/../ci-fix/BRIEF.template.md" "$SRC/../ci-fix/agent.env" "$H/agents/ci-fix/"
for s in agent-run notify-owner pc; do
  printf '#!/bin/sh\n# STUB\nprintf "%%s\\n" "$*" >>"%s/%s.calls"\n' "$WORK" "$s" >"$B/$s"
  cp "$B/$s" "$WORK/path/$s"
done
printf 'cp "%s/agents/ci-fix/BRIEF.md" "%s/brief.seen"\n' "$H" "$WORK" >>"$B/agent-run"
printf '[ -n "${FIXER_REPORT:-}" ] && printf "%%s\\n" "$FIXER_REPORT" >"%s/agents/ci-fix/REPORT.md"\n' "$H" >>"$B/agent-run"
printf 'echo "AGENT_RUN_NO_PUSH=${AGENT_RUN_NO_PUSH:-}" >"%s/agent-env.seen"; exit "${FIXER_RC:-0}"\n' "$WORK" >>"$B/agent-run"
printf '[ -z "${FAIL_PC:-}" ] || exit 6\n' >>"$B/pc"; printf '[ -z "${FAIL_PUSH:-}" ] || exit 7\n' >>"$B/notify-owner"
# Fixture CI: FAILS=n red runs, then green; the failure line comes from FIXTURE_MSG.
cat >"$WORK/fixture-ci" <<EOF
#!/bin/sh
n=\$(cat "$WORK/count" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n >"$WORK/count"
echo "CI_AUTOFIX=\${CI_AUTOFIX:-}" >>"$WORK/env.seen"; echo "\${CI_DEADLINE:-}" >"$WORK/deadline.seen"
echo "rerun=\${CI_AUTOFIX_RERUN:-}" >>"$WORK/rerun.seen"
exec >"$WORK/ci.log" 2>&1
echo "fixture ci run \$n"
[ -n "\${FIXTURE_RC:-}" ] && exit "\$FIXTURE_RC"
[ "\$n" -le "\${FAILS:-0}" ] || { echo "all green"; exit 0; }
[ -n "\${FIXTURE_CONTENTION:-}" ] && echo "ci-load: contention (1-min load 14.02 before, 9.10 after; only perf jobs red: sheet-change)"
echo "\${FIXTURE_MSG:-e2e: 3 jobs in 1\$n s, 1 failed: lesson:lesson}"
echo "✖ ci failed at ci (rc 1): \${FIXTURE_MSG:-e2e: 3 jobs in 1\$n s, 1 failed: lesson:lesson}"
exit 1
EOF
chmod +x "$B/"* "$WORK/path/"* "$WORK/fixture-ci"

calls() { grep -c . "$WORK/$1.calls" 2>/dev/null || echo 0; }
run() {
  rm -f "$WORK"/*.calls "$WORK/count" "$WORK/brief.seen" "$WORK/env.seen" "$WORK/rerun.seen" "$WORK/ci.first.log"
  HOME="$H" PATH="$WORK/path:$PATH" bash "$B/ci-autofix" --repo "$WORK/repo" --log "$WORK/ci.log" "fixture nightly" -- "$WORK/fixture-ci"
}
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }

# Selftest: every launcher and pusher the wrapper can reach is a stub, and the wrapper never calls them off PATH.
for s in agent-run notify-owner pc; do
  grep -q '^# STUB' "$B/$s" && grep -q '^# STUB' "$(PATH="$WORK/path:$PATH"; command -v "$s")"; eq "selftest: $s is a stub" 0 $?
done
grep -Eq '(^|[;&|(] *)(agent-run|notify-owner|pc) ' "$B/ci-autofix"; eq "selftest: no launcher called off PATH" 1 $?
[ "$bad" -eq 0 ] || { echo "selftest failed: nothing runs"; exit 1; }

FAILS=1 run; eq "fails once then passes: rc 0" 0 $?
eq "one fix attempt" 1 "$(calls agent-run)"
eq "the fixer is ci-fix" ci-fix "$(cat "$WORK/agent-run.calls")"
eq "CI ran twice" 2 "$(cat "$WORK/count")"
eq "the CI sees CI_AUTOFIX=1" "CI_AUTOFIX=1" "$(sort -u "$WORK/env.seen")"
eq "no push when the fix turns it green" 0 "$(calls notify-owner)"
eq "need resolved" yes "$(has 'need resolve fixture nightly ci failed --fixed' "$(cat "$WORK/pc.calls" 2>/dev/null)")"
eq "resolve is applied" yes "$(has -- '--apply' "$(cat "$WORK/pc.calls" 2>/dev/null)")"
NOTE="$H/agents/state/ci-fix/$(date +%F).md"
eq "failure note written" yes "$(has 'cluster: fixture-ci · exit 1 · ✖ ci failed at ci (rc 1): e2e: 3 jobs in 11 s, 1 failed: lesson:lesson' "$(cat "$NOTE")")"
eq "note keeps the log tail" yes "$(has 'fixture ci run 1' "$(cat "$NOTE")")"
eq "note records the green re-run" yes "$(has 're-run: green' "$(cat "$NOTE")")"
eq "rerun scope: only the re-run after a fix gets CI_AUTOFIX_RERUN=<first log>" "rerun= rerun=$WORK/ci.first.log" "$(paste -sd ' ' "$WORK/rerun.seen")"
eq "rerun scope: the first log is kept, the re-run writes its own" "fixture ci run 1|all green" "$(head -1 "$WORK/ci.first.log")|$(tail -1 "$WORK/ci.log")"
brief="$(cat "$WORK/brief.seen")"
eq "fixer brief names the repo" yes "$(has "Find the cause in $WORK/repo" "$brief")"
eq "fixer brief names the note with ~" yes "$(has "~/agents/state/ci-fix/$(date +%F).md" "$brief")"
eq "fixer brief holds no home path" no "$(has "$H" "$brief")"
eq "fixer brief forbids commit and push" yes "$(has 'never `git commit`/`git push`' "$brief")"
eq "fixer brief has no placeholder left" "" "$(printf '%s' "$brief" | grep -o '@[A-Z]*@')"

FAILS=2 FIXTURE_MSG="declutter 02-b: 1 FAIL" run; eq "fails twice: rc 1" 1 $?
eq "fails twice: one fix attempt" 1 "$(calls agent-run)"
eq "fails twice: one push" 1 "$(calls notify-owner)"
push="$(cat "$WORK/notify-owner.calls")"
eq "push is high with a cause key" yes "$(has '-p high -t fixture nightly -k fixture nightly ci: fixture-ci · exit  · ✖ ci failed at ci (rc ): declutter -b:  FAIL' "$push")"
eq "push says the fix was tried" yes "$(has 'fixture nightly ci failed after one auto-fix attempt' "$push")"
eq "push names the note" yes "$(has "state/ci-fix/$(date +%F).md" "$push")"
eq "fails twice: no resolve" 0 "$(calls pc)"

eq "agent-run is told not to push (the wrapper does)" "AGENT_RUN_NO_PUSH=1" "$(cat "$WORK/agent-env.seen")"
FAILS=2 FIXER_RC=3 FIXTURE_MSG="declutter 09-f: 1 FAIL" run; eq "a failed fixer: exactly one push" 1 "$(calls notify-owner)"
eq "a failed fixer: the note records its exit" yes "$(has 'attempt: agent-run ci-fix exit 3' "$(cat "$H/agents/state/ci-fix/$(date +%F).md")")"
FAILS=2 FIXTURE_MSG="declutter 02-b: 1 FAIL" run; eq "same cause in 24 h: rc 1" 1 $?
eq "same cause in 24 h: no second attempt" 0 "$(calls agent-run)"
eq "same cause in 24 h: CI ran once" 1 "$(cat "$WORK/count")"
eq "same cause in 24 h: push says already tried" yes "$(has 'auto-fix already tried in 24 h' "$(cat "$WORK/notify-owner.calls")")"

FAILS=2 FIXTURE_MSG="declutter 05-x: 1 FAIL" run; eq "another cause gets its own attempt" 1 "$(calls agent-run)"
T="$H/agents/state/ci-fix/attempts.tsv"; awk -F'\t' -v t=$(( $(date +%s) - 90000 )) 'BEGIN{OFS="\t"} {$1=t; print}' "$T" >"$T.x" && mv "$T.x" "$T"
FAILS=2 FIXTURE_MSG="declutter 02-b: 1 FAIL" run; eq "an attempt older than 24 h: tried again" 1 "$(calls agent-run)"

run; eq "green: rc 0" 0 $?
eq "green: no attempt, no push, no resolve" "0 0 0" "$(calls agent-run) $(calls notify-owner) $(calls pc)"
for r in 75 2 143; do
  FIXTURE_RC=$r run; eq "rc $r passes through" "$r" $?
  eq "rc $r: no attempt, no push" "0 0" "$(calls agent-run) $(calls notify-owner)"
done
HOME="$H" bash "$B/ci-autofix" --repo x --log y label "$WORK/fixture-ci" 2>/dev/null; eq "no -- : usage rc 2" 2 $?
HOME="$H" bash "$B/ci-autofix" --repo 2>/dev/null; eq "a flag without value: rc 2" 2 $?

# Contention (T407): the fixer's verdict or the CI's own log line waits for a quiet load, then re-runs once instead of pushing.
note() { cat "$H/agents/state/ci-fix/$(date +%F).md"; }
echo "14.02 9 9 1/100 1" >"$CI_LOADAVG"; ( sleep 1; echo "2.00 9 9 1/100 1" >"$CI_LOADAVG" ) &
FAILS=1 FIXER_REPORT="Cause: CPU contention, not a code bug." FIXTURE_MSG="e2e: 1 failed: sheet-change" run; eq "fixer says contention: rc 0" 0 $?
eq "fixer says contention: no push" 0 "$(calls notify-owner)"
eq "fixer says contention: waited for a quiet load" yes "$(has 'ci-window: 1-min load 2.00 < 4' "$(note)")"
eq "fixer says contention: need resolved" yes "$(has 'need resolve' "$(cat "$WORK/pc.calls" 2>/dev/null)")"
touch -d '1 hour ago' "$H/agents/ci-fix/REPORT.md"; : >"$H/agents/state/ci-fix/$(date +%F).md"
FAILS=2 FIXTURE_MSG="unit: 1 failed: maths" run; eq "an old contention report is not this verdict: rc 1" 1 $?
eq "an old contention report: no quiet wait" no "$(has 'contention:' "$(note)")"
FAILS=2 FIXTURE_CONTENTION=1 FIXTURE_MSG="e2e: 1 failed: home-perf" run; eq "log contention, still red when quiet: rc 1" 1 $?
eq "log contention, still red: one attempt, CI ran twice, one push" "1 2 1" "$(calls agent-run) $(cat "$WORK/count") $(calls notify-owner)"
FAILS=1 FIXTURE_CONTENTION=1 FIXTURE_MSG="e2e: 1 failed: home-perf" run; eq "log contention, cause tried in 24 h: quiet re-run green, rc 0" 0 $?
eq "log contention, tried in 24 h: no attempt, CI ran twice, no push" "0 2 0" "$(calls agent-run) $(cat "$WORK/count") $(calls notify-owner)"
eq "contention re-run unchanged: full re-run, no CI_AUTOFIX_RERUN, first log kept" "rerun= rerun= yes" "$(paste -sd ' ' "$WORK/rerun.seen") $(test -s "$WORK/ci.first.log" && echo yes)"
eq "log contention, tried in 24 h: need resolved" yes "$(has 'green after a quiet re-run' "$(cat "$WORK/pc.calls" 2>/dev/null)")"

# Shared budget (T408): no re-run when the unit timeout would cut it; the note and the push say so.
: >"$H/agents/state/ci-fix/$(date +%F).md"
FAILS=1 CI_DEADLINE=$(( $(date +%s) + 600 )) FIXTURE_MSG="declutter 11-q: 1 FAIL" run; eq "budget short: rc 1, no re-run" "1 1" "$? $(cat "$WORK/count")"
eq "budget short: the note says why" yes "$(has 's left before the unit timeout, a re-run needs 2700 s; skipped' "$(note)")"
eq "budget short: one push that says so" "1 yes" "$(calls notify-owner) $(has 'no time left for a re-run' "$(cat "$WORK/notify-owner.calls")")"
FAILS=1 FIXTURE_MSG="declutter 12-w: 1 FAIL" run; eq "default budget: the re-run happens" "0 2" "$? $(cat "$WORK/count")"
eq "ci-autofix exports one deadline about 10500 s out" yes "$(d=$(cat "$WORK/deadline.seen"); [ $(( d - $(date +%s) )) -gt 10400 ] && [ $(( d - $(date +%s) )) -le 10500 ] && echo yes || echo "no: $d")"

# A failing resolve or push (T911): the note says so, the run's rc is unchanged.
: >"$H/agents/state/ci-fix/$(date +%F).md"
FAILS=1 FAIL_PC=1 FIXTURE_MSG="declutter 21-r: 1 FAIL" run; eq "resolve fails: still rc 0" 0 $?
eq "resolve fails: the note says so" yes "$(has 'ci-autofix: need resolve failed rc 6' "$(note)")"
FAILS=2 FAIL_PUSH=1 FIXTURE_MSG="declutter 22-p: 1 FAIL" run; eq "push fails: still rc 1" 1 $?
eq "push fails: the note says so" yes "$(has 'ci-autofix: notify-owner failed rc 7' "$(note)")"

exit $bad
