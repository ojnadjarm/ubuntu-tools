#!/usr/bin/env bash
# Fixtures for ~/agents/bin/ci-autofix: a fixture CI that fails once then passes, or fails twice; stub agent-run, notify-owner and pc
# under a fake HOME (AGENTS.md §5.6: no real agent launch, no real push), proven by a selftest before the first run.
set -uo pipefail
SRC="$HOME/agents/bin"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
bad=0
ok() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (want $2, got $3)"; bad=$((bad+1)); fi; }

H="$WORK/home"; B="$H/agents/bin"; mkdir -p "$B" "$H/agents/ci-fix" "$WORK/path" "$WORK/repo"
cp "$SRC/ci-autofix" "$SRC/auditlib.py" "$SRC/ci-window" "$SRC/wait-for" "$B/"
export CI_LOADAVG="$WORK/loadavg" WAIT_FOR_DIR="$WORK/waits" CI_QUIET_EVERY=1
echo "1.00 1 1 1/100 1" >"$CI_LOADAVG"
cp "$SRC/../ci-fix/BRIEF.template.md" "$SRC/../ci-fix/agent.env" "$H/agents/ci-fix/"
for s in agent-run notify-owner pc; do
  printf '#!/bin/sh\n# STUB\nprintf "%%s\\n" "$*" >>"%s/%s.calls"\n' "$WORK" "$s" >"$B/$s"
  cp "$B/$s" "$WORK/path/$s"
done
printf 'cp "%s/agents/ci-fix/BRIEF.md" "%s/brief.seen"\n' "$H" "$WORK" >>"$B/agent-run"
printf '[ -n "${FIXER_REPORT:-}" ] && printf "%%s\\n" "$FIXER_REPORT" >"%s/agents/ci-fix/REPORT.md"\n' "$H" >>"$B/agent-run"
printf 'echo "AGENT_RUN_NO_PUSH=${AGENT_RUN_NO_PUSH:-}" >"%s/agent-env.seen"; exit "${FIXER_RC:-0}"\n' "$WORK" >>"$B/agent-run"
# Fixture CI: FAILS=n red runs, then green; the failure line comes from FIXTURE_MSG.
cat >"$WORK/fixture-ci" <<EOF
#!/bin/sh
n=\$(cat "$WORK/count" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n >"$WORK/count"
echo "CI_AUTOFIX=\${CI_AUTOFIX:-}" >>"$WORK/env.seen"; echo "\${CI_DEADLINE:-}" >"$WORK/deadline.seen"
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
  rm -f "$WORK"/*.calls "$WORK/count" "$WORK/brief.seen" "$WORK/env.seen"
  HOME="$H" PATH="$WORK/path:$PATH" bash "$B/ci-autofix" --repo "$WORK/repo" --log "$WORK/ci.log" "fixture nightly" -- "$WORK/fixture-ci"
}
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }

# Selftest: every launcher and pusher the wrapper can reach is a stub, and the wrapper never calls them off PATH.
for s in agent-run notify-owner pc; do
  grep -q '^# STUB' "$B/$s" && grep -q '^# STUB' "$(PATH="$WORK/path:$PATH"; command -v "$s")"; ok "selftest: $s is a stub" 0 $?
done
grep -Eq '(^|[;&|(] *)(agent-run|notify-owner|pc) ' "$B/ci-autofix"; ok "selftest: no launcher called off PATH" 1 $?
[ "$bad" -eq 0 ] || { echo "selftest failed: nothing runs"; exit 1; }

FAILS=1 run; ok "fails once then passes: rc 0" 0 $?
ok "one fix attempt" 1 "$(calls agent-run)"
ok "the fixer is ci-fix" ci-fix "$(cat "$WORK/agent-run.calls")"
ok "CI ran twice" 2 "$(cat "$WORK/count")"
ok "the CI sees CI_AUTOFIX=1" "CI_AUTOFIX=1" "$(sort -u "$WORK/env.seen")"
ok "no push when the fix turns it green" 0 "$(calls notify-owner)"
ok "need resolved" yes "$(has 'need resolve fixture nightly ci failed --fixed' "$(cat "$WORK/pc.calls" 2>/dev/null)")"
ok "resolve is applied" yes "$(has -- '--apply' "$(cat "$WORK/pc.calls" 2>/dev/null)")"
NOTE="$H/agents/state/ci-fix/$(date +%F).md"
ok "failure note written" yes "$(has 'cluster: fixture-ci · exit 1 · ✖ ci failed at ci (rc 1): e2e: 3 jobs in 11 s, 1 failed: lesson:lesson' "$(cat "$NOTE")")"
ok "note keeps the log tail" yes "$(has 'fixture ci run 1' "$(cat "$NOTE")")"
ok "note records the green re-run" yes "$(has 're-run: green' "$(cat "$NOTE")")"
brief="$(cat "$WORK/brief.seen")"
ok "fixer brief names the repo" yes "$(has "Find the cause in $WORK/repo" "$brief")"
ok "fixer brief names the note with ~" yes "$(has "~/agents/state/ci-fix/$(date +%F).md" "$brief")"
ok "fixer brief holds no home path" no "$(has "$H" "$brief")"
ok "fixer brief forbids commit and push" yes "$(has 'never `git commit`/`git push`' "$brief")"
ok "fixer brief has no placeholder left" "" "$(printf '%s' "$brief" | grep -o '@[A-Z]*@')"

FAILS=2 FIXTURE_MSG="declutter 02-b: 1 FAIL" run; ok "fails twice: rc 1" 1 $?
ok "fails twice: one fix attempt" 1 "$(calls agent-run)"
ok "fails twice: one push" 1 "$(calls notify-owner)"
push="$(cat "$WORK/notify-owner.calls")"
ok "push is high with a cause key" yes "$(has '-p high -t fixture nightly -k fixture nightly ci: fixture-ci · exit  · ✖ ci failed at ci (rc ): declutter -b:  FAIL' "$push")"
ok "push says the fix was tried" yes "$(has 'fixture nightly ci failed after one auto-fix attempt' "$push")"
ok "push names the note" yes "$(has "state/ci-fix/$(date +%F).md" "$push")"
ok "fails twice: no resolve" 0 "$(calls pc)"

ok "agent-run is told not to push (the wrapper does)" "AGENT_RUN_NO_PUSH=1" "$(cat "$WORK/agent-env.seen")"
FAILS=2 FIXER_RC=3 FIXTURE_MSG="declutter 09-f: 1 FAIL" run; ok "a failed fixer: exactly one push" 1 "$(calls notify-owner)"
ok "a failed fixer: the note records its exit" yes "$(has 'attempt: agent-run ci-fix exit 3' "$(cat "$H/agents/state/ci-fix/$(date +%F).md")")"
FAILS=2 FIXTURE_MSG="declutter 02-b: 1 FAIL" run; ok "same cause in 24 h: rc 1" 1 $?
ok "same cause in 24 h: no second attempt" 0 "$(calls agent-run)"
ok "same cause in 24 h: CI ran once" 1 "$(cat "$WORK/count")"
ok "same cause in 24 h: push says already tried" yes "$(has 'auto-fix already tried in 24 h' "$(cat "$WORK/notify-owner.calls")")"

FAILS=2 FIXTURE_MSG="declutter 05-x: 1 FAIL" run; ok "another cause gets its own attempt" 1 "$(calls agent-run)"
T="$H/agents/state/ci-fix/attempts.tsv"; awk -F'\t' -v t=$(( $(date +%s) - 90000 )) 'BEGIN{OFS="\t"} {$1=t; print}' "$T" >"$T.x" && mv "$T.x" "$T"
FAILS=2 FIXTURE_MSG="declutter 02-b: 1 FAIL" run; ok "an attempt older than 24 h: tried again" 1 "$(calls agent-run)"

run; ok "green: rc 0" 0 $?
ok "green: no attempt, no push, no resolve" "0 0 0" "$(calls agent-run) $(calls notify-owner) $(calls pc)"
for r in 75 2 143; do
  FIXTURE_RC=$r run; ok "rc $r passes through" "$r" $?
  ok "rc $r: no attempt, no push" "0 0" "$(calls agent-run) $(calls notify-owner)"
done
HOME="$H" bash "$B/ci-autofix" --repo x --log y label "$WORK/fixture-ci" 2>/dev/null; ok "no -- : usage rc 2" 2 $?
HOME="$H" bash "$B/ci-autofix" --repo 2>/dev/null; ok "a flag without value: rc 2" 2 $?

# Contention (T407): the fixer's verdict or the CI's own log line waits for a quiet load, then re-runs once instead of pushing.
note() { cat "$H/agents/state/ci-fix/$(date +%F).md"; }
echo "14.02 9 9 1/100 1" >"$CI_LOADAVG"; ( sleep 1; echo "2.00 9 9 1/100 1" >"$CI_LOADAVG" ) &
FAILS=1 FIXER_REPORT="Cause: CPU contention, not a code bug." FIXTURE_MSG="e2e: 1 failed: sheet-change" run; ok "fixer says contention: rc 0" 0 $?
ok "fixer says contention: no push" 0 "$(calls notify-owner)"
ok "fixer says contention: waited for a quiet load" yes "$(has 'ci-window: 1-min load 2.00 < 4' "$(note)")"
ok "fixer says contention: need resolved" yes "$(has 'need resolve' "$(cat "$WORK/pc.calls" 2>/dev/null)")"
touch -d '1 hour ago' "$H/agents/ci-fix/REPORT.md"; : >"$H/agents/state/ci-fix/$(date +%F).md"
FAILS=2 FIXTURE_MSG="unit: 1 failed: maths" run; ok "an old contention report is not this verdict: rc 1" 1 $?
ok "an old contention report: no quiet wait" no "$(has 'contention:' "$(note)")"
FAILS=2 FIXTURE_CONTENTION=1 FIXTURE_MSG="e2e: 1 failed: home-perf" run; ok "log contention, still red when quiet: rc 1" 1 $?
ok "log contention, still red: one attempt, CI ran twice, one push" "1 2 1" "$(calls agent-run) $(cat "$WORK/count") $(calls notify-owner)"
FAILS=1 FIXTURE_CONTENTION=1 FIXTURE_MSG="e2e: 1 failed: home-perf" run; ok "log contention, cause tried in 24 h: quiet re-run green, rc 0" 0 $?
ok "log contention, tried in 24 h: no attempt, CI ran twice, no push" "0 2 0" "$(calls agent-run) $(cat "$WORK/count") $(calls notify-owner)"
ok "log contention, tried in 24 h: need resolved" yes "$(has 'green after a quiet re-run' "$(cat "$WORK/pc.calls" 2>/dev/null)")"

# Shared budget (T408): no re-run when the unit timeout would cut it; the note and the push say so.
: >"$H/agents/state/ci-fix/$(date +%F).md"
FAILS=1 CI_DEADLINE=$(( $(date +%s) + 600 )) FIXTURE_MSG="declutter 11-q: 1 FAIL" run; ok "budget short: rc 1, no re-run" "1 1" "$? $(cat "$WORK/count")"
ok "budget short: the note says why" yes "$(has 's left before the unit timeout, a re-run needs 2700 s; skipped' "$(note)")"
ok "budget short: one push that says so" "1 yes" "$(calls notify-owner) $(has 'no time left for a re-run' "$(cat "$WORK/notify-owner.calls")")"
FAILS=1 FIXTURE_MSG="declutter 12-w: 1 FAIL" run; ok "default budget: the re-run happens" "0 2" "$? $(cat "$WORK/count")"
ok "ci-autofix exports one deadline about 10500 s out" yes "$(d=$(cat "$WORK/deadline.seen"); [ $(( d - $(date +%s) )) -gt 10400 ] && [ $(( d - $(date +%s) )) -le 10500 ] && echo yes || echo "no: $d")"

exit $(( bad > 0 ))
