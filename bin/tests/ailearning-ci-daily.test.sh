#!/usr/bin/env bash
# Fixtures for ~/agents/bin/ailearning-ci-daily: the failure push names the failed e2e jobs; declutter runs only on units changed since their
# last green run (--full: all, --mark: record); nightly runs the playthrough gate report-only. Fake HOME, a throwaway git repo, stub npm and notify-owner.
set -uo pipefail
SRC="$HOME/agents/bin/ailearning-ci-daily"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
bad=0
ok() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (want $2, got $3)"; bad=$((bad+1)); fi; }

H="$WORK/home"; mkdir -p "$H/agents/bin" "$H/agents/log" "$H/.nvm" "$WORK/repo/tests/lib" "$WORK/path"
cp "$SRC" "$HOME/agents/bin/ci-window" "$HOME/agents/bin/wait-for" "$H/agents/bin/"; : >"$H/agents/bin/env.sh"
export CI_LOADAVG="$WORK/loadavg" WAIT_FOR_DIR="$WORK/waits" CI_QUIET_EVERY=1
echo "1.00 1 1 1/100 1" >"$CI_LOADAVG"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\n' "$WORK/pushes" >"$H/agents/bin/notify-owner"
echo 'nvm() { :; }' >"$H/.nvm/nvm.sh"
echo 'const ARGS = [];' >"$WORK/repo/tests/lib/browser.mjs"
git -C "$WORK/repo" init -q
mkdir -p "$WORK/repo/content/.render" "$WORK/repo/content/u1" "$WORK/repo/out/shots" "$WORK/repo/tools/declutter" "$WORK/repo/src/kit" \
  "$WORK/repo/u/01-a" "$WORK/repo/u/02-b" "$WORK/repo/u/03-c" "$WORK/repo/units/01-a" "$WORK/repo/units/02-b"
touch "$WORK/repo/content/.render/a.wav" "$WORK/repo/content/u1/unit.md" "$WORK/repo/out/shots/a.png" "$WORK/repo/u/01-a/index.html" \
  "$WORK/repo/u/02-b/index.html" "$WORK/repo/u/03-c/index.html" "$WORK/repo/units/01-a/main.ts" "$WORK/repo/units/02-b/main.ts" "$WORK/repo/src/kit/k.ts"
printf '/out\n/content/.render\n' >"$WORK/repo/.gitignore"
echo "export const CHECKED = ['01', '02'];" >"$WORK/repo/tools/declutter/rules.mjs"
NODE=$(ls -d "$HOME"/.nvm/versions/node/*/bin/node 2>/dev/null | tail -1); NODE=${NODE:-$(command -v node)}
ln -s "$NODE" "$WORK/path/node"
JOBS=$(for i in $(seq 1 15); do printf 'job-%02d 12, ' "$i"; done)
cat >"$WORK/path/npm" <<EOF
#!/bin/sh
echo "\$*" >>"$WORK/calls"
case "\$2" in
  ci:core)
    [ -n "\${CORE_SLEEP:-}" ] && sleep "\$CORE_SLEEP"
    ls -A content content/u1 .git >"$WORK/copied" 2>&1; ls -A out content/.render >>"$WORK/copied" 2>&1
    [ -n "\${CORE_FAIL:-}" ] || exit 0
    echo "e2e: 17 jobs in 419 s (${JOBS}lesson:lesson 210, sheet-cold 12), 2 failed: \${CORE_RED:-lesson:lesson, sheet-cold}"
    exit 1;;
  playthrough) printf '01-a bench k1 never-completes\n02-b bench e2 unnamed\n' >"\$5/fails.txt"; exit 1;;
  declutter) [ "\$4" = "\${DECLUTTER_FAIL:-}" ] && { echo "declutter \$4: 9 steps, 1 with faults FAIL"; exit 1; }; exit 0;;
esac
EOF
chmod +x "$H/agents/bin/"* "$WORK/path/npm"

run() { : >"$WORK/calls"; HOME="$H" PATH="$WORK/path:$PATH" AILEARNING_REPO="$WORK/repo" AILEARNING_CI_LOG="$WORK/ci.log" bash "$H/agents/bin/ailearning-ci-daily" "$@"; }
decl() { grep '^run declutter' "$WORK/calls" | awk '{print $4}' | tr '\n' ' '; }

CORE_FAIL=1 run
ok "rc is npm's" 1 $?
ok "no declutter after a core failure" "" "$(decl)"
push=$(cat "$WORK/pushes" 2>/dev/null)
ok "one push" 1 "$(grep -c . "$WORK/pushes" 2>/dev/null || echo 0)"
case "$push" in *"2 failed: lesson:lesson, sheet-cold"*) r=yes;; *) r=no;; esac
ok "push names the failed jobs" yes "$r"
case "$push" in *"e2e: 17 jobs in 419 s"*) r=yes;; *) r=no;; esac
ok "push keeps the e2e head" yes "$r"
case "$(tail -1 "$H/agents/log/ailearning-ci.jsonl")" in *'2 failed: lesson:lesson, sheet-cold'*) r=yes;; *) r=no;; esac
ok "jsonl row names the failed jobs" yes "$r"
case "$(cat "$WORK/copied")" in *HEAD*unit.md*) r=yes;; *) r=no;; esac
ok "copy keeps content and .git" yes "$r"
case "$(cat "$WORK/copied")" in *a.wav*|*shots*) r=no;; *) r=yes;; esac
ok "copy skips content/.render and out/" yes "$r"
grep -q '^run playthrough -- --out' "$WORK/calls"; ok "a core failure still runs the playthrough" 0 $?

: >"$WORK/pushes"; CI_AUTOFIX=1 CORE_FAIL=1 run; ok "under ci-autofix: rc is npm's" 1 $?
ok "under ci-autofix: the runner leaves the push to the wrapper" 0 "$(grep -c . "$WORK/pushes")"
grep -q '^✖ ci failed at ci (rc 1): e2e: 17 jobs in 419 s, 2 failed: lesson:lesson' "$WORK/ci.log"; ok "the log ends with the failure line" 0 $?
grep -q '^ci-window: 1-min load 1.00 < 4 after 0 s' "$WORK/ci.log"; ok "the log records the load before ci:core" 0 $?
grep -q '^ci-load: contention' "$WORK/ci.log"; ok "a quiet machine: no contention line" 1 $?
CI_AUTOFIX=1 CORE_FAIL=1 CORE_RED="home-perf, sheet-change" run
grep -q '^ci-load: contention' "$WORK/ci.log"; ok "only perf jobs red at load 1: no contention line" 1 $?
echo "14.02 9 9 1/100 1" >"$CI_LOADAVG"
CI_QUIET_CAP=1 CI_AUTOFIX=1 CORE_FAIL=1 CORE_RED="home-perf, sheet-change" run
grep -q '^ci-window: 1-min load 14.02, still ≥ 4 after' "$WORK/ci.log"; ok "a busy machine past the cap: the load is logged, the run goes on" 0 $?
grep -q '^ci-load: contention (1-min load 14.02 before, 14.02 after; only perf jobs red: home-perf, sheet-change)' "$WORK/ci.log"; ok "only perf jobs red at load 14: contention line" 0 $?
CI_QUIET_CAP=1 CI_AUTOFIX=1 CORE_FAIL=1 run
grep -q '^ci-load: contention' "$WORK/ci.log"; ok "a non-perf job red at load 14: no contention line" 1 $?
t=$(date +%s); CI_DEADLINE=$(( t + 100 )) CI_AUTOFIX=1 CORE_FAIL=1 run
grep -q '^ci-window: no wait budget left (.* s to the deadline, a run needs 2700 s); going on' "$WORK/ci.log"; ok "shared budget spent: no load wait, the log says so" 0 $?
ok "  and ci:core starts at once" yes "$( [ $(( $(date +%s) - t )) -lt 5 ] && echo yes || echo no)"
echo "1.00 1 1 1/100 1" >"$CI_LOADAVG"

run; ok "first nightly: rc 0" 0 $?
ok "first nightly declutters every CHECKED unit at 1366" "01-a 02-b " "$(decl)"
grep -q -- '--size 1366x768' "$WORK/calls"; ok "declutter at 1366" 0 $?
ok "a failing playthrough leaves the run green (rc above) and writes its fail list" 2 "$(grep -c . "$H/agents/log/ailearning-playthrough/fails.txt")"
grep -q '^playthrough (report only): rc 1, 2 failing cases' "$WORK/ci.log"; ok "the log says the playthrough's count" 0 $?
run; ok "unchanged: nothing declutters" "" "$(decl)"
grep -q 'ci:core' "$WORK/calls"; ok "nightly still runs ci:core" 0 $?
echo x >>"$WORK/repo/units/02-b/main.ts"
run; ok "a changed unit: only it declutters" "02-b " "$(decl)"
echo x >>"$WORK/repo/src/kit/k.ts"
run; ok "a shared kit change: every unit" "01-a 02-b " "$(decl)"
echo y >>"$WORK/repo/units/02-b/main.ts"; : >"$WORK/pushes"
DECLUTTER_FAIL=02-b run; ok "a failing unit: rc 1" 1 $?
case "$(cat "$WORK/pushes")" in *"declutter failed: 02-b"*) r=yes;; *) r=no;; esac
ok "push names the failed unit" yes "$r"
run; ok "a failed unit is not marked green" "02-b " "$(decl)"
run --full; ok "--full: rc 0" 0 $?
ok "--full declutters every unit" "01-a 02-b " "$(decl)"
grep -q 'ci:core' "$WORK/calls"; ok "--full skips ci:core" 1 $?
grep -q 'playthrough' "$WORK/calls"; ok "--full skips the playthrough" 1 $?
case "$(tail -1 "$H/agents/log/ailearning-ci.jsonl")" in *'"mode":"full"'*) r=yes;; *) r=no;; esac
ok "jsonl row carries the mode" yes "$r"
echo z >>"$WORK/repo/units/01-a/main.ts"
run --mark 01-a >/dev/null; run; ok "--mark records the current files as green" "" "$(decl)"
M="$H/agents/state/ailearning-declutter"
echo stale >"$M/02-b"; echo stale >"$M/01-a"; touch -d '2 days ago' "$M/02-b"; touch -d '1 day ago' "$M/01-a"
run; ok "nightly runs the oldest marker first, so a deferred unit goes first next night" "02-b 01-a " "$(decl)"
echo stale >"$M/01-a"; rm "$M/02-b"
run; ok "nightly runs a unit without a marker first" "02-b 01-a " "$(decl)"

L="$H/agents/log"; echo green >"$L/ailearning-ci.log"; : >"$WORK/pushes"
run --bogus 2>/dev/null; ok "an unknown flag: rc 2" 2 $?
grep -q 'ci:core' "$WORK/calls"; ok "an unknown flag runs nothing" 1 $?
mkdir -p "$H/agents/state"
( flock 9; : >"$WORK/calls"; HOME="$H" PATH="$WORK/path:$PATH" AILEARNING_REPO="$WORK/repo" bash "$H/agents/bin/ailearning-ci-daily" 2>/dev/null; echo $? >"$WORK/rc" ) 9>"$H/agents/state/ailearning-ci.lock"
ok "a run already going: rc 75" 75 "$(cat "$WORK/rc")"
grep -q 'ci:core' "$WORK/calls"; ok "a run already going: nothing runs" 1 $?
# Kill a run mid ci:core with TERM; $1 is the cgroup line the run sees.
killed() {
  echo "$1" >"$WORK/cgroup"; : >"$WORK/calls"
  CORE_SLEEP=1 HOME="$H" PATH="$WORK/path:$PATH" AILEARNING_REPO="$WORK/repo" AILEARNING_CI_CGROUP="$WORK/cgroup" bash "$H/agents/bin/ailearning-ci-daily" & pid=$!
  for _ in $(seq 50); do grep -q 'ci:core' "$WORK/calls" && break; sleep 0.1; done
  kill -TERM "$pid"; wait "$pid"
}
killed "0::/user.slice/app.slice/agent@x.service"; ok "a hand run killed: rc 143" 143 $?
ok "a hand run killed: no push" 0 "$(grep -c . "$WORK/pushes")"
ok "a hand run keeps the nightly log" green "$(cat "$L/ailearning-ci.log")"
grep -q 'ailearning-ci-daily nightly' "$L/ailearning-ci-manual.log"; ok "a hand run logs to ailearning-ci-manual.log" 0 $?
killed "0::/user.slice/app.slice/ailearning-ci-daily.service"; ok "the timer run killed: rc 143" 143 $?
case "$(cat "$WORK/pushes")" in *"failed at ci (rc 143)"*) r=yes;; *) r=no;; esac
ok "the timer run killed: pushes" yes "$r"
grep -q 'ailearning-ci-daily nightly' "$L/ailearning-ci.log"; ok "the timer run logs to ailearning-ci.log" 0 $?

exit $(( bad > 0 ))
