#!/usr/bin/env bash
# Runs every fleet test home in parallel; prints `ok|FAIL <file> <s>` per file and a `PASS|FAIL <ok>/<total> files in <s> s` summary.
# usage: run.sh [-j N] [--only <glob>]   (glob matches the path under ~/agents, e.g. 'bin/tests/pc-*' or '*dashboard*')
# env: RUN_TESTS_ROOT (default: the agents dir this file sits in), RUN_TESTS_TIMEOUT (s per file, default 170)
set -uo pipefail
root="${RUN_TESTS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
jobs=8 only='*' tmo="${RUN_TESTS_TIMEOUT:-170}"
while (($#)); do
  case $1 in
    -j) jobs=${2:?-j needs N}; shift 2 ;;
    --only) only=${2:?--only needs a glob}; shift 2 ;;
    -h|--help) sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "run.sh: unknown argument $1 (usage: run.sh [-j N] [--only <glob>])" >&2; exit 2 ;;
  esac
done

# Tests that cannot share the machine (live wall-time budgets, audio sink, desktop input): one lane, started once
# at most 2 pool files are still running.
SERIAL=(
  bin/tests/pc-hw.test.sh bin/tests/pc-io.test.sh bin/tests/pc-journal.test.sh bin/tests/pc-mutter.test.sh
  bin/tests/pc-net.test.sh bin/tests/pc-top.test.sh bin/tests/pc-explain.test.sh bin/tests/pc-power.test.sh
  bin/tests/pc-audio.test.sh bin/tests/pc-input.test.sh bin/tests/pc-idle.test.sh bin/tests/ci-window.test.sh
  bin/tests/wait-nudge.test.py dashboard/tests/test_thumbs.py
)
# Slowest files (measured 2026-10-19) start first at full priority; the rest of the pool runs at nice 10.
SLOW=(
  bin/tests/toolsmith-inputs.test.sh bin/tests/pc-doctor.test.sh bin/tests/pc-status-facts.test.sh
  bin/tests/pc-status.test.sh bin/tests/pc-trace.test.sh dashboard/tests/test_sites_header.js bin/tests/pcbench.test.sh
  hooks/sleep-loop-block.test.py bin/tests/orbit-hook.test.py bin/tests/code-review.test.sh bin/tests/maintenance-run.test.sh
  bin/tests/body-sandbox.test.sh bin/tests/sentinel-check.test.sh dashboard/tests/test_transcribe.py
)

# Homes: bin/tests, hooks, adapters/*/hooks, dashboard/tests; discord-bot/tests runs via bin/tests/discord-bot.test.sh (bot venv).
list() {
  cd "$root" || return
  local f
  for f in bin/tests/*.test.sh bin/tests/*.test.py hooks/*.test.py adapters/*/hooks/*.test.py \
           dashboard/tests/test_*.py dashboard/tests/test_*.js; do
    [[ -f $f && $f == $only ]] && echo "$f"
  done
}

run_one() {
  local rel=$1 n=${2:-10} t0 rc s cmd
  grep -qxF -- "$rel" <<<"$slow" && n=0
  case $rel in
    dashboard/tests/*.py) cmd=(bash -c 'cd "$1/dashboard" && exec python3 -m pytest -q -p no:cacheprovider "${2#dashboard/}"' _ "$root" "$rel") ;;
    *.sh) cmd=(bash "$root/$rel") ;;
    *.py) cmd=(python3 "$root/$rel") ;;
    *.js) cmd=(node "$root/$rel") ;;
  esac
  t0=$(date +%s.%N)
  (cd "$root/$(dirname "$rel")" && nice -n "$n" timeout -k 5 "$tmo" "${cmd[@]}") </dev/null >"$logs/${rel//\//__}.log" 2>&1
  rc=$?
  s=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}')
  if ((rc == 0)); then echo "ok $rel $s"; touch "$logs/${rel//\//__}.ok"
  elif ((rc == 124 || rc == 137)); then echo "FAIL $rel $s timeout"
  else echo "FAIL $rel $s"; fi
  echo >>"$logs/done.fifo"
}

logs=$(mktemp -d "${TMPDIR:-/tmp}/run-tests.XXXXXX")
slow=$(printf '%s\n' "${SLOW[@]}")
export root tmo logs slow
export -f run_one
t0=$(date +%s)
mapfile -t all < <(list)
par=() ser=() first=()
for f in "${all[@]}"; do
  if printf '%s\n' "${SERIAL[@]}" | grep -qxF -- "$f"; then ser+=("$f")
  elif ! printf '%s\n' "${SLOW[@]}" | grep -qxF -- "$f"; then par+=("$f"); fi
done
for f in "${SLOW[@]}"; do printf '%s\n' "${all[@]}" | grep -qxF -- "$f" && first+=("$f"); done

mkfifo "$logs/done.fifo"; exec 3<>"$logs/done.fifo"
printf '%s\n' "${first[@]}" "${par[@]}" | grep . | xargs -r -d '\n' -P "$jobs" -I{} bash -c 'run_one "$1"' _ {} &
for ((i = 0; i < ${#first[@]} + ${#par[@]} - 2; i++)); do read -r -u 3; done
for f in "${ser[@]}"; do run_one "$f" 0; done
wait
exec 3<&-

total=${#all[@]}
ok=$(find "$logs" -name '*.ok' | wc -l)
for f in "${all[@]}"; do
  [[ -e "$logs/${f//\//__}.ok" ]] && continue
  echo "--- $f (failure lines, then the last 8)"
  { grep -E '\bFAIL|Error|Traceback' "$logs/${f//\//__}.log" | head -n 10; tail -n 8 "$logs/${f//\//__}.log"; } | awk '!seen[$0]++' | sed 's/^/  | /'
done
find "$root/bin/tests" -maxdepth 1 -type f -empty -printf 'note: stray empty file bin/tests/%f (not a test; left in place)\n' 2>/dev/null
rm -rf "$logs"
secs=$(( $(date +%s) - t0 ))
if ((ok == total && total > 0)); then echo "PASS $ok/$total files in $secs s"; exit 0; fi
echo "FAIL $ok/$total files in $secs s"; exit 1
