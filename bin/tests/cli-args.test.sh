#!/usr/bin/env bash
# T347-09: a typo never runs the real job. Each CLI of the set runs in a fake HOME under `env -i`, stubs first on PATH:
# --bogus exits 2 with no stub call, --help exits 0, --dry-run writes no log, lock, streak or summary.
# Run: bash cli-args.test.sh   (CLI_ARGS_BIN / CLI_ARGS_SKILL / CLI_ARGS_TOOLS point it at other copies, e.g. backups)
set -uo pipefail
REAL_BIN="$HOME/agents/bin"
SRC_BIN="${CLI_ARGS_BIN:-$REAL_BIN}"
SRC_SKILL="${CLI_ARGS_SKILL:-$HOME/.claude/skills/make-lesson/scripts}"
SRC_TOOLS="${CLI_ARGS_TOOLS:-$HOME/projects/personal/ailearning/tools}"
NODE="$(command -v node)"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
FH="$WORK/home"; STUBS="$WORK/stubs"; CALLS="$WORK/calls"; AL="$WORK/al"
BASH_CLIS="moodle-keep ailearning-ci-daily pcbench-weekly maintenance-run sentinel-runaway guide"
mkdir -p "$FH/agents/bin" "$FH/agents/KB/guides" "$STUBS" "$WORK/proc" "$WORK/projects" "$WORK/tmp"
cp "$REAL_BIN/env.sh" "$REAL_BIN/fleetlib.sh" "$REAL_BIN/moodlelib.sh" "$FH/agents/bin/"
for c in $BASH_CLIS; do cp "$SRC_BIN/$c" "$FH/agents/bin/"; done

cat >"$STUBS/stub" <<'EOF'
#!/bin/sh
echo "${0##*/} $*" >>"$CLI_CALLS"
case "${0##*/} $1" in "pcbench away") echo '{"present":true,"reasons":["fixture"]}' ;; curl*) echo 200 ;; esac
exit 0
EOF
chmod +x "$STUBS/stub"
for s in docker notify-owner node npm sudo apt-get dpkg pcbench pc systemctl curl logrotate rsync body-sandbox git; do
  ln -s stub "$STUBS/$s"
done
cp "$STUBS/stub" "$FH/agents/bin/notify-owner"

# declutter runs from a copy whose playwright-core and vite are stubs that record the call and exit.
mkdir -p "$AL/u" "$AL/tools" "$AL/node_modules/playwright-core" "$AL/node_modules/vite"
cp -r "$SRC_TOOLS/declutter.mjs" "$SRC_TOOLS/declutter" "$AL/tools/"
for m in playwright-core vite; do
  printf '{"name":"%s","type":"module","main":"index.js"}\n' "$m" >"$AL/node_modules/$m/package.json"
  printf "import { appendFileSync } from 'node:fs';\nconst hit = () => { appendFileSync(process.env.CLI_CALLS, '%s\\\\n'); process.exit(0); };\nexport const chromium = { launch: hit };\nexport const createServer = hit;\n" "$m" >"$AL/node_modules/$m/index.js"
done

GLOBS='/tmp/claude-1000/*/*/scratchpad'
run() {
  env -i HOME="$FH" PATH="$STUBS:/usr/bin:/bin" LC_ALL=C CLI_CALLS="$CALLS" TMPDIR="$WORK/tmp" \
    AGENT_SCRATCH_GLOBS="$GLOBS" SENTINEL_RUNAWAY_PROC="$WORK/proc" SENTINEL_RUNAWAY_TMPROOT="$WORK/tmproot" \
    SENTINEL_RUNAWAY_PROJECTS="$WORK/projects" SENTINEL_RUNAWAY_ACTIONS="$WORK/actions.jsonl" "$@"
}

# --- selftest: the sandbox makes the real action impossible -----------------
st=0
for s in docker notify-owner sudo node npm systemctl rsync; do
  [ "$(run sh -c "command -v $s")" = "$STUBS/$s" ] || { echo "SELFTEST FAIL $s is not the stub"; st=1; }
done
[ "$(run sh -c 'echo $HOME')" = "$FH" ] || { echo "SELFTEST FAIL HOME is not the fake home"; st=1; }
[ -z "$(ls "$WORK/proc")" ] || { echo "SELFTEST FAIL fixture /proc is not empty"; st=1; }
: >"$CALLS"; run "$FH/agents/bin/notify-owner" probe; grep -q '^notify-owner probe' "$CALLS" || { echo "SELFTEST FAIL notify-owner stub"; st=1; }
[ "$st" = 0 ] || exit 1
echo "PASS selftest: fake HOME, stub docker/notify-owner/sudo/node/npm, empty fixture /proc"

bad=0; declare -A DEFECT=()
pass() { echo "PASS $2"; }
fail() { echo "FAIL $2${3:+ ($3)}"; bad=$((bad+1)); DEFECT[$1]=1; }
call() { : >"$CALLS"; run "$@" >"$WORK/out" 2>"$WORK/err"; rc=$?; }
calls() { tr '\n' ';' <"$CALLS"; }

bogus() {  # bogus <cli> <arg> <cmd...>
  local cli=$1 arg=$2; shift 2
  call "$@" "$arg"
  if [ "$rc" = 2 ] && [ ! -s "$CALLS" ]; then pass "$cli" "$cli $arg: exit 2, nothing run"
  else fail "$cli" "$cli $arg: exit 2, nothing run" "rc=$rc calls=$(calls)"; fi
}
help() {  # help <cli> <arg> <cmd...>
  local cli=$1 arg=$2; shift 2
  call "$@" "$arg"
  if [ "$rc" = 0 ] && [ ! -s "$CALLS" ] && [ -s "$WORK/out" ]; then pass "$cli" "$cli $arg: usage on stdout, exit 0"
  else fail "$cli" "$cli $arg: usage on stdout, exit 0" "rc=$rc calls=$(calls)"; fi
}

# --- unknown options and help ------------------------------------------------
for c in $BASH_CLIS; do
  bogus "$c" --bogus bash "$FH/agents/bin/$c"
  help "$c" --help bash "$FH/agents/bin/$c"
done
for c in moodle-keep ailearning-ci-daily sentinel-runaway; do bogus "$c" bogus bash "$FH/agents/bin/$c"; done
for c in moodle-keep ailearning-ci-daily; do
  call bash "$FH/agents/bin/$c" --bogus
  grep -q usage "$WORK/err" && pass "$c" "$c --bogus: usage on stderr" || fail "$c" "$c --bogus: usage on stderr"
done
for c in lesson-board new-lesson; do
  bogus "$c" --bogus "$NODE" "$SRC_SKILL/$c.mjs"
  help "$c" --help "$NODE" "$SRC_SKILL/$c.mjs"
  help "$c" -h "$NODE" "$SRC_SKILL/$c.mjs"
done
call "$NODE" "$SRC_SKILL/new-lesson.mjs" --help
for f in --lint --narrate --site --spec-only; do
  grep -q -- "$f" "$WORK/out" || fail new-lesson "new-lesson --help describes $f"
done
bogus declutter --bogus "$NODE" "$AL/tools/declutter.mjs"
help declutter --help "$NODE" "$AL/tools/declutter.mjs"
help declutter -h "$NODE" "$AL/tools/declutter.mjs"
call "$NODE" "$AL/tools/declutter.mjs" --bogus
grep -q -i usage "$WORK/err" && pass declutter "declutter --bogus: usage on stderr" || fail declutter "declutter --bogus: usage on stderr"

# --- dry runs write nothing ----------------------------------------------------
mkdir -p "$FH/moodle-envs/v1/www"
printf 'name: v1\nservices:\n  app:\n    volumes:\n      - ./www:/var/www/html\n' >"$FH/moodle-envs/v1/docker-compose.yml"
echo '<?php' >"$FH/moodle-envs/v1/www/config.php"
call bash "$FH/agents/bin/moodle-keep" --dry-run
if [ "$rc" = 0 ] && [ ! -s "$CALLS" ] && grep -q '^would: v1 ' "$WORK/out" && [ ! -e "$FH/agents/backups" ]; then
  pass moodle-keep "moodle-keep --dry-run: would: lines per env, no docker, no dump"
else fail moodle-keep "moodle-keep --dry-run: would: lines per env, no docker, no dump" "rc=$rc calls=$(calls)"; fi

for _ in 1 2 3; do call bash "$FH/agents/bin/pcbench-weekly" --dry-run; done
left=$(find "$FH/agents/bench" "$FH/agents/log" -type f 2>/dev/null | wc -l)
if [ "$rc" = 0 ] && [ "$left" = 0 ] && ! grep -q notify-owner "$CALLS"; then
  pass pcbench-weekly "pcbench-weekly --dry-run x3: no streak, no log, no push"
else fail pcbench-weekly "pcbench-weekly --dry-run x3: no streak, no log, no push" "rc=$rc files=$left calls=$(calls)"; fi

call bash "$FH/agents/bin/maintenance-run" --dry-run
if { [ "$rc" = 0 ] || [ "$rc" = 3 ]; } && grep -q '^maintenance-run .*(dry-run)' "$WORK/out" \
   && [ ! -e "$FH/agents/maintenance/state/last-summary.txt" ] && [ ! -e "$FH/agents/maintenance/state/.lock" ] \
   && ! grep -q notify-owner "$CALLS"; then
  pass maintenance-run "maintenance-run --dry-run: prints, no summary, no lock, no push"
else fail maintenance-run "maintenance-run --dry-run: prints, no summary, no lock, no push" "rc=$rc calls=$(calls)"; fi

dead="$WORK/tmproot/claude-1000/-home-x/uuid-dead/scratchpad"
mkdir -p "$dead"; touch -d "@$(( $(date +%s) - 90000 ))" "$dead"
echo "500000.00 0.00" >"$WORK/proc/uptime"
call bash "$FH/agents/bin/sentinel-runaway" --dry-run
if grep -q "would rm -rf $dead" "$WORK/out" && [ -d "$dead" ] && [ ! -e "$FH/agents/sentinel/state/sentinel.log" ]; then
  pass sentinel-runaway "sentinel-runaway --dry-run: would lines on stdout, sentinel.log untouched"
else fail sentinel-runaway "sentinel-runaway --dry-run: would lines on stdout, sentinel.log untouched" "rc=$rc"; fi

G="$FH/agents/KB/guides"
printf '# Guides\n\n- make-lesson — lessons · triggers: new lesson · verified 2026-10-15\n' >"$G/INDEX.md"
printf '# T\n' >"$G/TEMPLATE.md"
call bash "$FH/agents/bin/guide" new lesson
[ ! -e "$G/lesson.md" ] && grep -q make-lesson "$WORK/out" && pass guide "guide new lesson: a search, no stub" \
  || fail guide "guide new lesson: a search, no stub" "rc=$rc"
call bash "$FH/agents/bin/guide" --new my-thing
[ "$rc" = 0 ] && [ "$(cat "$G/my-thing.md" 2>/dev/null)" = "# T" ] && pass guide "guide --new my-thing: copies the template" \
  || fail guide "guide --new my-thing: copies the template" "rc=$rc"

echo
echo "defects: ${#DEFECT[@]}/9${DEFECT[*]:+ (${!DEFECT[*]})}"
[ "$bad" = 0 ] && echo "all cli-args fixtures pass" || echo "$bad FAILURES"
[ "$bad" = 0 ]
