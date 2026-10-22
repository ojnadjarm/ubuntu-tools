#!/usr/bin/env bash
# Runs every fleet test home in parallel; prints `ok|FAIL <file> <s>` per file and a `PASS|FAIL <ok>/<total> files in <s> s` summary.
# usage: run.sh [-j N] [--only <glob>] [--no-wait] [--portable] [--skills] [--skip-unchanged [--plan]]   (glob matches the path under ~/agents, e.g. 'bin/tests/pc-*' or '*dashboard*')
#        --portable (or FLEET_FRESH=1) prints `SKIP host-only <file>` for files listed in host-only.txt or with a `# host-only` line in their first 5 lines; they count as ok.
#        Every file gets lib/sudo-shim as `sudo` (logged, refused) unless a `# live-sudo` line sits in its first 5 lines.
#        --skills (implied by --only 'skills/...') adds <skill>/tests/*.test.* as skills/<skill>/..., docker shimmed.
#        Files listed in quiet-gated.txt run after the pool drains, one at a time (`serial tail: N quiet-gated`).
#        --skip-unchanged prints `SKIP unchanged <file> (green <date>, <cpu> CPU s)`, counted ok, for a skill test whose last history row is green with >= 20 CPU s and none of its inputs is newer:
#        the test file, the skill entries it names (scripts, templates/<x>, top-level files and dirs; named scripts are followed), fixtures
#        by path only (fixtures/<x>[/…]; `plates <name>`: fixtures/plates/<name>), the shared libs (scripts/mvlib.*, scripts/ci-lib.sh),
#        all of templates/ when it names new-cpp-game or cpp-ci, named skills/<x> dirs and agents/bin files, globs on a `# inputs: <glob> …`
#        line in its first 10 lines (relative to the skill), and the installed versions of bin/DEPS.tsv's apt packages at the skill's levels.
#        --plan (with --skip-unchanged) runs and writes nothing: per skill test `skip <file> …` or `run <file>: <blocking input> …`, then `would skip N files, <cpu> CPU s`.
# env: RUN_TESTS_ROOT (default: the agents dir this file sits in), RUN_TESTS_TIMEOUT (s per file, default 170; a file with ok history gets clamp(2 x p50 of its last 5 ok runs, this, 600)),
#      TEST_MEM_MAX (memory cap per file in its own systemd scope, default 6G; plain run when no user bus),
#      RUN_TESTS_LOCK (full-run lock, default $XDG_RUNTIME_DIR/fleet-suite.lock; --no-wait exits 75 while it is held),
#      RUN_TESTS_SKILLS (skill dirs, colon-separated, default ~/.claude/skills:<root>/skills; symlinks followed, counted once)
#      RUN_TESTS_SKIP_DEPS (--skip-unchanged inputs besides the skill, colon-separated, default ~/opt/gamedev:the vcpkg baseline)
#      Every file gets a private TMPDIR, removed when it exits (timed out or killed too), unless it mounts its own `--tmpfs /tmp`;
#      `tmp residue: N dirs` counts new tmp.* left in the base TMPDIR.
#      CREATIVE_CI_LOG is the run's own ledger for every file; rows or summary copies added to the real one (inherited CREATIVE_CI_LOG,
#      else $HARNESS_HOME/log/creative-ci.jsonl), or scratch-ledger rows tagged with this run's RUN_TESTS_ID, print
#      `run.sh: tests wrote the real creative ledger (N rows, …)` and FAIL the run; untagged scratch rows are a `note:` line.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root="${RUN_TESTS_ROOT:-$(cd "$here/../.." && pwd)}"
lock="${RUN_TESTS_LOCK:-${XDG_RUNTIME_DIR:-/tmp}/fleet-suite.lock}"
skill_dirs="${RUN_TESTS_SKILLS:-$HOME/.claude/skills:$root/skills}"
vcpkg="${VCPKG_ROOT:-$HOME/opt/gamedev/vcpkg}"
skip_deps="${RUN_TESTS_SKIP_DEPS:-$HOME/opt/gamedev:$vcpkg/versions/baseline.json}"
# A fixture run.sh inside a test must resolve its own root, never this one (T505: nested full suites, load 248).
unset RUN_TESTS_ROOT RUN_TESTS_LOCK RUN_TESTS_SKILLS RUN_TESTS_SKIP_DEPS
jobs=8 only='*' tmo="${RUN_TESTS_TIMEOUT:-170}" wait=1 portable=${FLEET_FRESH:+1} skills= skipu= plan=
while (($#)); do
  case $1 in
    -j) jobs=${2:?-j needs N}; shift 2 ;;
    --only) only=${2:?--only needs a glob}; shift 2 ;;
    --no-wait) wait=; shift ;;
    --portable) portable=1; shift ;;
    --skills) skills=1; shift ;;
    --skip-unchanged) skipu=1; shift ;;
    --plan) plan=1; shift ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "run.sh: unknown argument $1 (usage: run.sh [-j N] [--only <glob>] [--no-wait] [--portable] [--skills] [--skip-unchanged [--plan]])" >&2; exit 2 ;;
  esac
done
[[ $only == skills/* ]] && skills=1

# One full run at a time; --only runs and runs nested under the holder (fixture suites inside tests) skip the lock.
if [[ $only == '*' && -z ${FLEET_SUITE_HOLDER:-} && -z $plan ]]; then
  exec 8>>"$lock"
  if ! flock -n 8; then
    [[ -z $wait ]] && { echo "run.sh: suite lock held by $(<"$lock"); --no-wait" >&2; exit 75; }
    echo "waiting for the suite lock held by $(<"$lock")" >&2
    flock 8
  fi
  echo "pid $$${AGENT_NAME:+ $AGENT_NAME}" >"$lock"
  export FLEET_SUITE_HOLDER=$$
fi

# Tests that cannot share the machine (live wall-time budgets, audio sink, desktop input): one lane, started once
# at most 2 pool files are still running.
SERIAL=(
  bin/tests/pc-hw.test.sh bin/tests/pc-io.test.sh bin/tests/pc-journal.test.sh bin/tests/pc-mutter.test.sh
  bin/tests/pc-net.test.sh bin/tests/pc-top.test.sh bin/tests/pc-explain.test.sh bin/tests/pc-power.test.sh
  bin/tests/pc-audio.test.sh bin/tests/pc-input.test.sh bin/tests/pc-idle.test.sh bin/tests/ci-window.test.sh
  bin/tests/wait-nudge.test.py dashboard/tests/test_thumbs.py
)
# The pool starts longest-first by last duration (state/test-timings.tsv: file, seconds, rc, cpu_s; rewritten each run); files of
# at least SLOW_S s run at full priority, the rest at nice 10. Files with no row yet fall back to this hand list (2026-10-19).
SLOW_S=20
SLOW=(
  bin/tests/toolsmith-inputs.test.sh bin/tests/pc-doctor.test.sh bin/tests/pc-status-facts.test.sh
  bin/tests/pc-status.test.sh bin/tests/pc-trace.test.sh dashboard/tests/test_sites_header.js bin/tests/pcbench.test.sh
  hooks/sleep-loop-block.test.py bin/tests/orbit-hook.test.py bin/tests/code-review.test.sh bin/tests/maintenance-run.test.sh
  bin/tests/body-sandbox.test.sh bin/tests/sentinel-check.test.sh dashboard/tests/test_transcribe.py
)
# Skill tests left out, printed as `skip <file> (<why>)` (T530, 2026-10-19).
SKILL_SKIP=(
  $'skills/make-lesson/*\tailearning is off limits'
  $'skills/moodle-ai-setup/tests/setup.test.sh\tits live half drives the real moodle53 container'
)
# Paused skills (T1103): each `<skill><TAB><why>` row of paused-skills.txt skips all of skills/<skill>/; unpausing = delete the row.
while IFS=$'\t' read -r s why; do
  [[ -n $s && $s != \#* ]] && SKILL_SKIP+=("skills/$s/*"$'\t'"$why")
done < <(cat "$root/bin/tests/paused-skills.txt" 2>/dev/null)

# A file is host-only when listed in host-only.txt (`<path under the root>[  # <reason>]`) or tagged in its first 5 lines.
host_only() { awk -v f="$1" '$1 == f { x = 1 } END { exit !x }' "$root/bin/tests/host-only.txt" 2>/dev/null || head -n 5 "$2" | grep -qE '^(#|//) host-only'; }
# quiet-gate waiters (quiet-gated.txt, same shape) never see a quiet machine beside the pool, so they run in a serial tail (T776).
quiet_gated() { awk -v f="$1" '$1 == f { x = 1 } END { exit !x }' "$root/bin/tests/quiet-gated.txt" 2>/dev/null; }

# Homes: bin/tests, hooks, adapters/*/hooks, dashboard/tests; discord-bot/tests runs via bin/tests/discord-bot.test.sh (bot venv).
# With --skills, <dir>/<skill>/tests/*.test.* of each skill dir; their label -> path map goes to $logs/skills.tsv.
list() {
  cd "$root" || return
  local f d rel rp s seen=$'\n' dirs
  for f in bin/tests/*.test.sh bin/tests/*.test.py hooks/*.test.py adapters/*/hooks/*.test.py \
           dashboard/tests/test_*.py dashboard/tests/test_*.js; do
    [[ -f $f && $f == $only ]] || continue
    [[ -n $portable ]] && host_only "$f" "$f" && echo "$f" >>"$logs/hostonly"
    echo "$f"
  done
  [[ -n $skills ]] || return 0
  IFS=: read -ra dirs <<<"$skill_dirs"
  for d in "${dirs[@]}"; do
    for f in "$d"/*/tests/*.test.sh "$d"/*/tests/*.test.py "$d"/*/tests/*.test.js; do
      [[ -f $f ]] || continue
      rel=skills/${f#"$d"/} rp=$(realpath "$f")
      [[ $seen == *$'\n'"$rel"$'\n'* || $seen == *$'\n'"$rp"$'\n'* ]] && continue
      seen+=$rel$'\n'$rp$'\n'
      [[ $rel == $only ]] || continue
      [[ -n $portable ]] && host_only "$rel" "$f" && echo "$rel" >>"$logs/hostonly"
      for s in "${SKILL_SKIP[@]}"; do
        [[ $rel == ${s%%$'\t'*} ]] && { echo "skip $rel (${s#*$'\t'})" >>"$logs/skips"; continue 2; }
      done
      printf '%s\t%s\n' "$rel" "$f" >>"$logs/skills.tsv"
      echo "$rel"
    done
  done
}

# --skip-unchanged (T717, T849): the inputs of skill test $1 in skill dir $2 (realpath), one path per line. Tokens of the
# test (full-line # comments left out) name skill entries; named scripts are scanned in turn (shared libs and non-scripts are inputs, not scanned);
# `skills/<x>/<path>` names that file when it exists, else the whole skill <x>; `../../<x>/<path>` (shared libs too) names that file.
SKIP_CPU_S=20
test_inputs() {
  local sd=$2 f p x d cand q=("$1") seen=$'\n' g libs=()
  cand=$(cd "$sd" && find . scripts tests templates -mindepth 1 -maxdepth 1 ! -name '*.test.*' ! -name __pycache__ \
    ! -name tests ! -name scripts ! -name templates ! -name fixtures -printf '%f\t%p\n' 2>/dev/null
    find tests/fixtures -mindepth 1 -maxdepth 1 ! -name __pycache__ -printf 'fixtures/%f\t%p\n' 2>/dev/null)
  for f in "$sd"/scripts/mvlib.* "$sd"/scripts/ci-lib.sh; do [[ -f $f ]] && libs+=("$f"); done
  printf '%s\n' "$1" "${libs[@]}"; q+=("${libs[@]}")
  while ((${#q[@]})); do
    f=${q[0]} q=("${q[@]:1}")
    while IFS=$'\t' read -r x p y; do
      [[ $x == T ]] && { echo "$sd/templates"; continue; }
      [[ $x == D && ! -e $sd/${p#./} ]] && p=$y
      p=$sd/${p#./}
      [[ $seen == *$'\n'"$p"$'\n'* ]] && continue
      seen+=$p$'\n'; echo "$p"
      [[ $p == "$sd"/scripts/* && -f $p && $p != */mvlib.* && $p != */ci-lib.sh ]] && q+=("$p")
    done < <([[ $f == */mvlib.* || $f == */ci-lib.sh ]] || grep -v '^[[:space:]]*#' "$f" | grep -oE '[A-Za-z0-9_.-]+|fixtures(/[A-Za-z0-9_.-]+)+|^[[:space:]]*plates [A-Za-z0-9_.-]+' |
      sort -u | awk -F'\t' 'NR == FNR { c[$1] = c[$1] $0 "\n"; next }
      $0 == "new-cpp-game" || $0 == "cpp-ci" { print "T" } $0 in c { printf "%s", c[$0] }
      /^fixtures\/.*\// { split($0, s, "/"); k = s[1] "/" s[2]; if (k in c) print "D\t./tests/" $0 "\t./tests/" k }
      sub(/^[[:space:]]*plates /, "") { print "P\t./tests/fixtures/plates/" $0 }' <(printf '%s\n' "$cand") -)
    while read -r x; do
      case $x in
        skills/*) x=${x#skills/} p=${x%%/*}; [[ $sd == */"$p" ]] && continue
          for d in "${sdirs[@]}"; do [[ -d $d/$p ]] || continue; [[ -e $d/$x ]] && realpath "$d/$x" || realpath "$d/$p"; break; done ;;
        agents/bin/*) [[ -f $root/${x#agents/} ]] && echo "$root/${x#agents/}" ;;
        ../../*) [[ -f ${f%/*}/$x ]] && realpath "${f%/*}/$x" ;;
      esac
    done < <(grep -hoIE 'skills/[a-z0-9-]+(/[A-Za-z0-9._/-]+)?|agents/bin/[A-Za-z0-9._/-]+|\.\./\.\./[a-z0-9-]+/[A-Za-z0-9._/-]+' "$f" | sort -u)
  done
  while read -ra x; do
    for g in "${x[@]}"; do g=${g/#\~/$HOME}; [[ $g == /* ]] || g=$sd/$g; compgen -G "$g"; done
  done < <(head -n 10 "$1" | sed -nE 's,^(#|//) inputs: ,,p')
}
# Apt input of skill $1 (T895, T944): sha16 of the `dpkg-query` versions of bin/DEPS.tsv's apt packages at levels required + test (+ optional:media
# for motion-video, optional:gamedev for gamedev), a package not installed as `<pkg> absent`, stamped as state/skip-deps/<sha16>. A new stamp
# takes the newest dpkg info/<pkg>.list mtime (now when one is absent); a set seen before that comes back after another one
# (state/skip-deps.cur/<levels> holds the last) is re-stamped now. --plan prints the same times and writes nothing.
apt_query() {
  pkgl=$(awk -F'\t' '!/^#/ && $2 != "-" && $4 ~ /^(required|test|optional:(media|gamedev))$/ { n = split($2, a, " "); for (i = 1; i <= n; i++) print a[i] "\t" $4 }' \
    "$root/bin/DEPS.tsv" 2>/dev/null | sort -u)
  vers=$( (( ${#pkgl} )) && dpkg-query -W -f '${Package} ${Version} ${db:Status-Status}\n' $(cut -f1 <<<"$pkgl" | sort -u) 2>/dev/null)
  aptq=1
}
apt_dep() {
  local lv='required|test' set sha st cur t= k pk
  [[ $1 == motion-video ]] && lv+='|optional:media'
  [[ $1 == gamedev ]] && lv+='|optional:gamedev'
  pk=$(awk -F'\t' -v lv="^($lv)$" '$2 ~ lv { print $1 }' <<<"$pkgl" | sort -u)
  set=$(awk 'NR == FNR { if (NF) k[$1]; next } ($1 in k) && $2 != "" && ($3 == "" || $3 == "installed") { print $1, $2; got[$1] }
    END { for (p in k) if (!(p in got)) print p, "absent" }' <(printf '%s\n' "$pk") <(printf '%s\n' "$vers") | sort)
  sha=$(printf '%s' "${set:+$set$'\n'}" | sha256sum | cut -c1-16)
  st=$root/state/skip-deps/$sha cur=$root/state/skip-deps.cur/${lv//[|:]/-}
  if [[ ! -e $st ]]; then
    grep -q ' absent$' <<<"$set" || t=$(for k in $pk; do stat -c %Y /var/lib/dpkg/info/"$k".list /var/lib/dpkg/info/"$k":*.list; done 2>/dev/null | sort -n | tail -n 1)
    t=${t:-$(date +%s.%N)}
  elif [[ -s $cur && $(<"$cur") != "$sha" ]]; then t=$(date +%s.%N)
  fi
  if [[ -z $plan ]] && mkdir -p "${st%/*}" "${cur%/*}"; then
    [[ -n $t ]] && touch -d "@$t" "$st"
    [[ -s $cur && $(<"$cur") == "$sha" ]] || { echo "$sha" >"$cur.$$" && mv "$cur.$$" "$cur"; }
  fi
  if [[ -n $t ]]; then printf '%s\t%s\n' "$t" "$st"; else newest_of "$st"; fi
}
# Newest mtime over paths: "<epoch>\t<path>"; __pycache__ and the vcpkg tree (only its baseline counts) left out.
newest_of() {
  find "$@" \( -name __pycache__ -o -path "$vcpkg" \) -prune -o -printf '%T@\t%p\n' 2>/dev/null | awk -F'\t' '$1 > m { m = $1; p = $2 } END { printf "%.3f\t%s\n", m, p }'
}

run_one() {
  local rel=$1 n=${2:-10} t0 rc s cmd path=$root/$1 p=$PATH tmp file_timeout rlog
  grep -qxF -- "$rel" <<<"$slow" && n=0
  file_timeout=$(awk -F'\t' -v r="$rel" '$1 == r { print $2; exit }' "$logs/caps" 2>/dev/null)
  # Skill tests run from where they were found, with the docker shim first on PATH: no real Moodle container.
  [[ $rel == skills/* ]] && path=$(awk -F'\t' -v r="$rel" '$1 == r { print $2; exit }' "$logs/skills.tsv") p=$logs/shim:$p
  # The sudo shim comes first on PATH unless the file has a `# live-sudo` line in its first 5 lines (T538); a live-sudo
  # file logs its pc_root calls to state/test-root-calls.tsv (T1136).
  head -n 5 "$path" | grep -qE '^(#|//) live-sudo' && rlog=$root/state/test-root-calls.tsv || p=$logs/sudo:$p
  case $rel in
    dashboard/tests/*.py) cmd=(bash -c 'cd "$1/dashboard" && exec python3 -m pytest -q -p no:cacheprovider "${2#dashboard/}"' _ "$root" "$rel") ;;
    *.sh) cmd=(bash "$path") ;;
    *.py) cmd=(python3 "$path") ;;
    *.js) cmd=(node "$path") ;;
  esac
  # The slug is the file stem without punctuation: test greps for words like `push` must not match the TMPDIR path.
  s=${rel##*/} s=${s%%.*}
  grep -qF -- '--tmpfs /tmp' "$path" || tmp=$(mktemp -d "$runroot/${s//[^[:alnum:]]/}.XXXX")
  # Empty CI_UNITS: ci-window inside a test never sees the live CI units (its own scope sits outside the CI's cgroup).
  cmd=(env "PATH=$p" "SUDO_SHIM_TEST=$rel" CI_UNITS= ${tmp:+"TMPDIR=$tmp"} ${rlog:+"PC_TEST_ROOT_LOG=$rlog"} "${cmd[@]}")
  # Own scope per file: the cgroup OOM killer hits only this file; the wrapper marks an oom_kill for the report.
  [[ -n $scoped ]] && cmd=(systemd-run --user --scope -q --slice=agents.slice --expand-environment=no -p "MemoryMax=$mem" -p MemorySwapMax=0 -p OOMPolicy=continue
    bash -c '"${@:3}"; rc=$?; c=/sys/fs/cgroup$(sed -n "s/^0:://p" /proc/self/cgroup); [ -e "$c/memory.events" ] && grep -qE "^oom_kill [1-9]" "$c/memory.events" && : >"$1"; awk "/^usage_usec/ { print \$2 / 1e6 }" "$c/cpu.stat" >"$2" 2>/dev/null; exit $rc'
    _ "$logs/${rel//\//__}.oom" "$logs/${rel//\//__}.cpu" "${cmd[@]}")
  t0=$(date +%s.%N)
  (cd "$(dirname "$path")" && nice -n "$n" timeout -k 5 "${file_timeout:-$tmo}" "${cmd[@]}"; rc=$?; times >"$logs/${rel//\//__}.times"; exit $rc) \
    </dev/null >"$logs/${rel//\//__}.log" 2>&1
  rc=$?
  [[ -n $tmp ]] && rm -rf "$tmp"
  s=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}')
  # cpu_s: user+sys of the file's scope (cgroup cpu.stat), else of the waited children (`times`; a timed-out scope lands here).
  cpu=$(cat "$logs/${rel//\//__}.cpu" 2>/dev/null)
  [[ $cpu =~ ^[0-9.e+-]+$ ]] || cpu=$(awk 'NR == 2 { gsub(",", "."); split($1, u, "m"); split($2, y, "m"); print u[1] * 60 + u[2] + y[1] * 60 + y[2] }' \
    "$logs/${rel//\//__}.times" 2>/dev/null)
  cpu=$(awk -v c="${cpu:-0}" 'BEGIN{printf "%.1f", c}')
  if [[ -e $logs/${rel//\//__}.oom ]]; then echo "FAIL $rel $s oom"
  elif ((rc == 0)); then echo "ok $rel $s"; touch "$logs/${rel//\//__}.ok"
  elif ((rc == 124 || rc == 137)); then echo "FAIL $rel $s timeout"
  else echo "FAIL $rel $s"; fi
  printf '%s\t%s\t%s\t%s\n' "$rel" "$s" "$rc" "$cpu" >>"$logs/timings"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%FT%T)" "$rel" "$s" "$rc" "$(cut -d' ' -f1 /proc/loadavg)" "$cpu" >>"$logs/history"
  echo >>"$logs/done.fifo"
}

# Stubs that tests write under `mktemp -d` must run: keep an exec-capable TMPDIR, else export a per-run dir under
# $XDG_RUNTIME_DIR or ~/.cache, removed at exit (T523: docker's --tmpfs /tmp and hardened hosts are noexec).
exec_ok() {
  local f rc
  f=$(mktemp "$1/exec-probe.XXXXXX" 2>/dev/null) || return 1
  printf '#!/bin/sh\n' >"$f" && chmod +x "$f" && "$f" 2>/dev/null; rc=$?
  rm -f "$f"; return $rc
}
own_tmp= runroot= logs=
tmp_base=${TMPDIR:-/tmp}
residue() { find "$tmp_base" -maxdepth 1 -name 'tmp.*' -user "$(id -u)" 2>/dev/null | wc -l; }
tmp_before=$(residue)
trap 'rm -rf ${logs:+"$logs"} ${runroot:+"$runroot"} ${own_tmp:+"$own_tmp"}' EXIT
trap 'exit 143' INT TERM HUP
if ! exec_ok "${TMPDIR:-/tmp}"; then
  for base in ${XDG_RUNTIME_DIR:+"$XDG_RUNTIME_DIR"} "$HOME/.cache"; do
    own_tmp=$(mkdir -p "$base/fleet-tests" 2>/dev/null && mktemp -d "$base/fleet-tests/run.XXXXXX" 2>/dev/null) || continue
    exec_ok "$own_tmp" && break
    rm -rf "$own_tmp"; own_tmp=
  done
  if [[ -n $own_tmp ]]; then export TMPDIR=$own_tmp
  else echo "run.sh: no exec-capable TMPDIR (${TMPDIR:-/tmp} is noexec); test stubs will not run" >&2; fi
fi

logs=$(mktemp -d "${TMPDIR:-/tmp}/run-tests.XXXXXX")
runroot=$(mktemp -d "${TMPDIR:-/tmp}/fleet-tmp.XXXXXX")
mkdir "$logs/shim" && printf '#!/bin/sh\necho "run.sh: skill tests never reach the real docker (docker $*)" >&2\nexit 125\n' >"$logs/shim/docker" &&
  chmod +x "$logs/shim/docker"
mkdir "$logs/sudo" && { cp "$here/lib/sudo-shim" "$logs/sudo/sudo" 2>/dev/null ||
  printf '#!/bin/sh\necho "run.sh: no lib/sudo-shim; sudo refused" >&2\nexit 1\n' >"$logs/sudo/sudo"; } && chmod +x "$logs/sudo/sudo"
export SUDO_SHIM_LOG=$logs/sudo.log
# Creative ledger (T861): every file writes ci_log rows to the run's own ledger unless it sets one; growth of the real one FAILs the run.
# creative-ci-scratch.jsonl counts only rows ci_log tagged with this run's RUN_TESTS_ID (T944): other agents' scratch runs are a note.
real_led=${CREATIVE_CI_LOG:-${HARNESS_HOME:-$HOME/agents}/log/creative-ci.jsonl}
scr_led=${real_led%/*}/creative-ci-scratch.jsonl
led_rows() { cat "$1" 2>/dev/null | wc -l; }
led_copies() { find "${real_led%/*}/creative-ci" -path '*/creative-ci/scratch' -prune -o -name '*.json' -newer "$logs/led.t0" -print 2>/dev/null | wc -l; }
rows0=$(led_rows "$real_led") scr0=$(led_rows "$scr_led"); touch "$logs/led.t0"
export CREATIVE_CI_LOG=$runroot/creative-ci.jsonl RUN_TESTS_ID=${runroot##*/}
timings="$root/state/test-timings.tsv"
history="$root/state/test-timings-history.tsv"
mem=${TEST_MEM_MAX:-6G} scoped=
# scope_ok — a user-bus scope can start; a positive probe is cached per boot in $XDG_RUNTIME_DIR/pc-status/scope-ok (T1138).
scope_ok() {
  local f=${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/pc-status/scope-ok} b
  b=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
  [ -n "$f" ] && [ -n "$b" ] && [ "$(cat "$f" 2>/dev/null)" = "$b" ] && return 0
  systemd-run --user --scope -q true >/dev/null 2>&1 || return 1
  [ -n "$f" ] && [ -n "$b" ] && mkdir -p "${f%/*}" 2>/dev/null && printf '%s\n' "$b" >"$f" 2>/dev/null
  return 0
}
scope_ok && scoped=1
export root tmo logs slow mem scoped runroot
export -f run_one
t0=$(date +%s)
mapfile -t all < <(list)
[[ -f $logs/skips ]] && cat "$logs/skips"
# Skill tests whose last history row is rc 0 with cpu_s >= SKIP_CPU_S: label -> "<date>T<time>\t<cpu_s>".
declare -A green
IFS=: read -ra sdirs <<<"$skill_dirs"
IFS=: read -ra deps <<<"$skip_deps"
[[ -n $skipu && -f $history ]] && while IFS=$'\t' read -r f ts cpu; do green[$f]=$ts$'\t'$cpu; done < <(awk -F'\t' -v m="$SKIP_CPU_S" '
  $2 ~ /^skills\// { r[$2] = $1 "\t" $4 "\t" $6 }
  END { for (f in r) { split(r[f], a, "\t"); if (a[2] == "0" && a[3] != "" && a[3] + 0 >= m) print f "\t" a[1] "\t" a[3] } }' "$history")
skipped=0 saved=0 lines= depn= aptq=
pool=() ser=() qtail=()
for f in "${all[@]}"; do
  if [[ -f $logs/hostonly ]] && grep -qxF -- "$f" "$logs/hostonly"; then
    r=$(awk -v f="$f" '$1 == f && /#/ { sub(/^[^#]*# */, ""); print; exit }' "$root/bin/tests/host-only.txt" 2>/dev/null)
    echo "SKIP host-only $f${r:+ ($r)}"; touch "$logs/${f//\//__}.ok"; continue
  fi
  if [[ -n ${green[$f]:-} ]]; then
    ts=${green[$f]%%$'\t'*} cpu=${green[$f]#*$'\t'}
    tf=$(awk -F'\t' -v r="$f" '$1 == r { print $2; exit }' "$logs/skills.tsv"); tf=$(realpath "$tf") sd=${tf%/tests/*}
    [[ -n $depn ]] || depn=$(newest_of "${deps[@]}")
    [[ -n $aptq ]] || apt_query
    n=$( { echo "$depn"; apt_dep "${sd##*/}"; mapfile -t ins < <(test_inputs "$tf" "$sd"); newest_of "${ins[@]}"; } | sort -t$'\t' -k1,1gr | head -n 1)
    if awk -v n="${n%%$'\t'*}" -v t="$(date -d "$ts" +%s)" 'BEGIN { exit !(n <= t) }'; then
      [[ -n $plan ]] && lines+="skip $f (green ${ts%%T*}, $cpu CPU s)"$'\n' || echo "SKIP unchanged $f (green ${ts%%T*}, $cpu CPU s)"
      touch "$logs/${f//\//__}.ok"
      skipped=$((skipped + 1)) saved=$(awk -v a="$saved" -v b="$cpu" 'BEGIN { printf "%.1f", a + b }'); continue
    fi
    p=${n#*$'\t'}; p=${p#"$sd"/}
    [[ $p == "$root"/state/skip-deps/* ]] && p="apt deps $(cut -c1-8 <<<"${p##*/}") since $(date -d "@${n%%$'\t'*}" '+%F %T')"
    lines+="run $f: ${p/#$HOME/\~} newer than green ${ts/T/ }"$'\n'
  elif [[ $f == skills/* ]]; then lines+="run $f: no green row >= $SKIP_CPU_S CPU s"$'\n'
  fi
  if quiet_gated "$f"; then qtail+=("$f")
  elif printf '%s\n' "${SERIAL[@]}" | grep -qxF -- "$f"; then ser+=("$f"); else pool+=("$f"); fi
done
if [[ -n $plan ]]; then
  printf '%s' "$lines"; echo "would skip $skipped files, $saved CPU s"; rm -rf "$logs"; exit 0
fi
[[ -f $timings ]] && src=$timings || src=/dev/null
mapfile -t ranked < <(printf '%s\n' "${pool[@]}" | grep . | awk -F'\t' -v src="$src" -v hand="$(printf '%s\n' "${SLOW[@]}")" '
  BEGIN { n = split(hand, h, "\n"); for (i = 1; i <= n; i++) r[h[i]] = i }
  FILENAME == src { t[$1] = $2; next }
  { print (($0 in t) ? t[$0] : ($0 in r) ? 1e6 - r[$0] : 0) "\t" $0 }' "$src" - | sort -t$'\t' -k1,1gr -s)
first=("${ranked[@]#*$'\t'}")
# Per-file timeout (T725): clamp(2 x p50 wall of the file's last 5 ok history rows, $tmo, 600); $logs/caps holds raised ones.
[[ -f $history ]] && printf '%s\n' "${all[@]}" | awk -F'\t' -v lo="$tmo" -v hi=600 '
  FILENAME != "-" { if ($4 == "0") w[$2, ++c[$2]] = $3; next }
  c[$0] {
    k = 0; for (i = (c[$0] > 5 ? c[$0] - 4 : 1); i <= c[$0]; i++) {
      x = w[$0, i] + 0; for (j = ++k; j > 1 && v[j - 1] > x; j--) v[j] = v[j - 1]; v[j] = x }
    p = k % 2 ? v[(k + 1) / 2] : (v[k / 2] + v[k / 2 + 1]) / 2
    t = int(2 * p + 0.5); t = t > hi ? hi : t; if (t > lo) printf "%s\t%d\t%.1f\n", $0, t, p }' "$history" - >"$logs/caps"
slow=$(printf '%s\n' "${ranked[@]}" | awk -F'\t' -v c="$SLOW_S" '$1 >= c { print $2 }')

mkfifo "$logs/done.fifo"; exec 3<>"$logs/done.fifo"
printf '%s\n' "${first[@]}" | grep . | xargs -r -d '\n' -P "$jobs" -I{} bash -c 'run_one "$1"' _ {} 8>&- &
for ((i = 0; i < ${#first[@]} - 2; i++)); do read -r -u 3; done
for f in "${ser[@]}"; do run_one "$f" 0 8>&-; done
wait
((${#qtail[@]})) && echo "serial tail: ${#qtail[@]} quiet-gated"
for f in "${qtail[@]}"; do run_one "$f" 0 8>&-; done
exec 3<&-

# Red file -> one record in state/test-fails/<file, / as __>.txt (`## ts rc load wall`, then its excerpt as `  | ` lines); 30 days, 20 records kept.
save_fail() {
  local out=$root/state/test-fails/${1//\//__}.txt
  mkdir -p "${out%/*}" || return
  { [[ -f $out ]] && cat "$out"
    awk -F'\t' -v r="$1" '$2 == r { printf "## %s rc %s load %s wall %s\n", $1, $4, $5, $3 }' "$logs/history" | tail -n 1
    [[ -n $2 ]] && sed 's/^/  | /' <<<"$2"; } | awk -v c="$(date -d '30 days ago' +%FT%T)" '
    /^## / { n++; keep[n] = $2 >= c } { rec[n] = rec[n] $0 "\n" }
    END { k = 0; for (i = n; i >= 1 && k < 20; i--) if (keep[i]) { k++; o[k] = i } for (i = k; i >= 1; i--) printf "%s", rec[o[i]] }' >"$out.tmp" &&
    mv "$out.tmp" "$out"
}
total=${#all[@]}
ok=$(find "$logs" -name '*.ok' | wc -l)
for f in "${all[@]}"; do
  [[ -e "$logs/${f//\//__}.ok" ]] && continue
  echo "--- $f (failure lines, then the last 8)"
  ex=$({ grep -E '\bFAIL|Error|Traceback' "$logs/${f//\//__}.log" | head -n 10; tail -n 8 "$logs/${f//\//__}.log"; } | awk '!seen[$0]++' | head -n 40)
  [[ -n $ex ]] && sed 's/^/  | /' <<<"$ex"
  [[ -f $logs/${f//\//__}.log ]] && save_fail "$f" "$ex"
done
find "$root/state/test-fails" -maxdepth 1 -name '*.txt' -mmin +43200 -delete 2>/dev/null
if [[ -s $logs/timings ]] && mkdir -p "$root/state"; then
  { [[ -f $timings ]] && awk -F'\t' 'NR == FNR { ran[$1]; next } !($1 in ran)' "$logs/timings" "$timings"
    cat "$logs/timings"; } | sort >"$timings.tmp" && mv "$timings.tmp" "$timings"
fi
# Every run also lands in state/test-timings-history.tsv (date, file, seconds, rc, load1, cpu_s), last 30 days kept; fleet-survey reads p50s from it.
if [[ -s $logs/history ]]; then
  { [[ -f $history ]] && awk -F'\t' -v c="$(date -d '30 days ago' +%FT%T)" '$1 >= c' "$history"
    cat "$logs/history"; } >"$history.tmp" && mv "$history.tmp" "$history"
fi
find "$root/bin/tests" -maxdepth 1 -type f -empty -printf 'note: stray empty file bin/tests/%f (not a test; left in place)\n' 2>/dev/null
[[ -s $logs/timings ]] && cpu_line=$(sort -t$'\t' -k4,4gr "$logs/timings" | awk -F'\t' '
  { t += $4; if (NR <= 3) top = top (NR > 1 ? ", " : "") $4 " " $1 } END { printf "cpu: %.1f s total, top 3: %s", t, top }')
scr_in=$(grep -cF "\"run\":\"$RUN_TESTS_ID\"" "$scr_led" 2>/dev/null) scr_out=$(( $(led_rows "$scr_led") - scr0 ))
scr_out=$(( scr_out - ${scr_in:-0} ))
((scr_out > 0)) && echo "note: $scr_out scratch rows from outside the suite"
led_n=$(( $(led_rows "$real_led") - rows0 + ${scr_in:-0} )) led_c=$(led_copies)
((led_n > 0 || led_c > 0)) && echo "run.sh: tests wrote the real creative ledger ($led_n rows, $led_c summary copies in ${real_led/#$HOME/\~})"
[[ -s $logs/caps ]] && awk -F'\t' '{ s = s (NR > 1 ? ", " : "") $2 " s " $1 " (p50 " $3 ")" } END { print "timeouts raised: " s }' "$logs/caps"
rm -rf "$logs"
n=$(( $(residue) - tmp_before )); echo "tmp residue: $(( n > 0 ? n : 0 )) dirs"
[[ -n ${cpu_line:-} ]] && echo "$cpu_line"
secs=$(( $(date +%s) - t0 ))
skip_note=; ((skipped)) && skip_note=", skipped $skipped, saved ~$saved CPU s"
if ((ok == total && total > 0 && led_n <= 0 && led_c == 0)); then echo "PASS $ok/$total files in $secs s$skip_note"; exit 0; fi
echo "FAIL $ok/$total files in $secs s$skip_note"; exit 1
