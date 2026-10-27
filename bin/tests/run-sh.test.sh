#!/usr/bin/env bash
# run.sh on a throwaway root with fixture tests (pass, fail, hang → timeout, over-cap → oom, timings order); the real test homes are never run.
set -uo pipefail
RUN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run.sh"
# Hang fixtures sleep on a per-run token, so a concurrent run of this file never counts or kills ours (T944).
hang="sleep 301.$$"
W=$(mktemp -d "${TMPDIR:-/tmp}/run-sh.\${HOME}.XXXXXX"); trap 'pkill -fx "$hang" 2>/dev/null; rm -rf "$W"' EXIT
mkdir -p "$W/bin/tests"
export RUN_TESTS_LOCK="$W/suite.lock" HARNESS_HOME="$W/hh"; unset FLEET_SUITE_HOLDER CREATIVE_CI_LOG
printf 'echo fine\n' >"$W/bin/tests/pass.test.sh"
printf 'echo "FAIL broken thing"; exit 1\n' >"$W/bin/tests/fail.test.sh"
echo "$hang" >"$W/bin/tests/hang.test.sh"
: >"$W/bin/tests/15"
fail=0
is() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$3', got '$2'"; fail=1; fi; }
has() { if grep -qE -- "$3" <<<"$2"; then echo "ok   $1"; else echo "FAIL $1: no /$3/ in: $(tr '\n' '|' <<<"$2")"; fail=1; fi; }

t0=$(date +%s)
out=$(RUN_TESTS_ROOT="$W" RUN_TESTS_TIMEOUT=2 bash "$RUN" -j 3 2>&1); rc=$?
dt=$(( $(date +%s) - t0 ))
is  'mixed run exits 1' "$rc" 1
has 'pass gets an ok line with seconds' "$out" '^ok bin/tests/pass\.test\.sh [0-9]+\.[0-9]$'
has 'fail gets a FAIL line with seconds' "$out" '^FAIL bin/tests/fail\.test\.sh [0-9]+\.[0-9]$'
has 'hang is cut by the timeout' "$out" '^FAIL bin/tests/hang\.test\.sh [0-9.]+ timeout$'
has 'failing output tail is shown' "$out" '^  \| FAIL broken thing$'
has 'stray empty file is reported' "$out" '^note: stray empty file bin/tests/15'
is  'stray empty file is left in place' "$(test -e "$W/bin/tests/15" && echo kept)" kept
has 'last line is the summary' "$(tail -1 <<<"$out")" '^FAIL 1/3 files in [0-9]+ s$'
is  'hang does not hold the run (< 10 s)' "$([ "$dt" -lt 10 ] && echo yes || echo "$dt s")" yes
is  'no hung child survives' "$(pgrep -fx "$hang" | wc -l)" 0

T="$W/state/test-timings.tsv"
has 'timings row per file: file, seconds, rc, cpu_s' "$(cat "$T" 2>/dev/null)" '^bin/tests/fail\.test\.sh	[0-9.]+	1	[0-9]+\.[0-9]$'
has 'timed-out file keeps its rc' "$(cat "$T" 2>/dev/null)" '^bin/tests/hang\.test\.sh	[0-9.]+	124	[0-9]+\.[0-9]$'
is  'timings has one row per file' "$(wc -l <"$T" 2>/dev/null)" 3
H="$W/state/test-timings-history.tsv"
has 'history row: date, file, seconds, rc, load1, cpu_s' "$(cat "$H" 2>/dev/null)" '^20[0-9-]{8}T[0-9:]{8}	bin/tests/fail\.test\.sh	[0-9.]+	1	[0-9.]+	[0-9]+\.[0-9]$'
has 'summary has a cpu line before the verdict' "$(tail -2 <<<"$out" | head -1)" '^cpu: [0-9]+\.[0-9] s total, top 3: [0-9.]+ bin/tests/[a-z]+\.test\.sh, [0-9.]+ bin/tests/'
is  'history has one row per file run' "$(wc -l <"$H" 2>/dev/null)" 3
{ printf '%s\tbin/tests/old.test.sh\t1.0\t0\t0.5\n' "$(date -d '31 days ago' +%FT%T)"
  printf '%s\tbin/tests/recent.test.sh\t2.0\t0\t0.5\n' "$(date -d '29 days ago' +%FT%T)"; } >>"$H"
out=$(RUN_TESTS_ROOT="$W" bash "$RUN" --only '*pass*' 2>&1)
has 'old 5-column history rows still parse: run passes' "$(tail -1 <<<"$out")" '^PASS 1/1 files'
is  'history drops rows older than 30 days' "$(grep -c old.test.sh "$H")" 0
is  'history keeps rows inside 30 days' "$(grep -c recent.test.sh "$H")" 1
is  'history appends every run of a file' "$(grep -c 'pass\.test\.sh' "$H")" 2
is  'timings still one row per file' "$(grep -c 'pass\.test\.sh' "$T")" 1

printf 'echo a\n' >"$W/bin/tests/aa-x.test.sh"; printf 'echo d\n' >"$W/bin/tests/pc-doctor.test.sh"
order() { RUN_TESTS_ROOT="$W" bash "$RUN" -j 1 --only 'bin/tests/[ap][a-z]-*' 2>&1 | awk '/^ok /{printf "%s ", $2}'; }
is  'no timings row: hand list first' "$(order)" 'bin/tests/pc-doctor.test.sh bin/tests/aa-x.test.sh '
printf 'bin/tests/aa-x.test.sh\t9.0\t0\nbin/tests/pc-doctor.test.sh\t1.0\t0\n' >"$T"
is  'timings row: longest last run first' "$(order)" 'bin/tests/aa-x.test.sh bin/tests/pc-doctor.test.sh '
printf 'bin/tests/aa-x.test.sh\t1.0\t0\nbin/tests/pc-doctor.test.sh\t9.0\t0\npass-gone.test.sh\t5.0\t0\n' >"$T"
is  'order follows the timings file' "$(order)" 'bin/tests/pc-doctor.test.sh bin/tests/aa-x.test.sh '
has '--only keeps rows of files it did not run' "$(cat "$T")" '^pass-gone\.test\.sh	5\.0	0$'
rm "$W/bin/tests/aa-x.test.sh" "$W/bin/tests/pc-doctor.test.sh"

out=$(RUN_TESTS_ROOT="$W" bash "$RUN" --only '*pass*' 2>&1); rc=$?
is  '--only pass exits 0' "$rc" 0
is  '--only pass runs one file' "$(tail -1 <<<"$out" | grep -oE '^PASS 1/1 files in [0-9]+ s$' | wc -l)" 1

out=$(env -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR=/nonexistent RUN_TESTS_ROOT="$W" bash "$RUN" --only '*pass*' 2>&1)
is  'no user bus: plain run still passes' "$(tail -1 <<<"$out" | grep -cE '^PASS 1/1 files')" 1

printf 'exit 1\n' >"$W/bin/tests/hostx.test.sh"; printf '#!/bin/sh\n# host-only: fixture\nexit 1\n' >"$W/bin/tests/hosty.test.sh"
echo bin/tests/hostx.test.sh >"$W/bin/tests/host-only.txt"
out=$(FLEET_FRESH=1 RUN_TESTS_ROOT="$W" bash "$RUN" --only '*host[xy]*' 2>&1)
has 'FLEET_FRESH: listed file skipped' "$out" '^SKIP host-only bin/tests/hostx\.test\.sh$'
has 'FLEET_FRESH: tagged file skipped' "$out" '^SKIP host-only bin/tests/hosty\.test\.sh$'
has 'host-only skips count as ok' "$(tail -1 <<<"$out")" '^PASS 2/2 files in [0-9]+ s$'
out=$(RUN_TESTS_ROOT="$W" bash "$RUN" --portable --only '*hostx*' 2>&1)
has '--portable skips a listed file' "$out" '^SKIP host-only bin/tests/hostx\.test\.sh$'
echo 'bin/tests/hostx.test.sh  # needs the GPU' >"$W/bin/tests/host-only.txt"
out=$(RUN_TESTS_ROOT="$W" bash "$RUN" --portable --only '*hostx*' 2>&1)
has 'a listed reason is printed' "$out" '^SKIP host-only bin/tests/hostx\.test\.sh \(needs the GPU\)$'
out=$(env -u FLEET_FRESH RUN_TESTS_ROOT="$W" bash "$RUN" --only '*host[xy]*' 2>&1)
has 'without --portable host-only files run' "$(tail -1 <<<"$out")" '^FAIL 0/2 files in [0-9]+ s$'
rm "$W/bin/tests/hostx.test.sh" "$W/bin/tests/hosty.test.sh" "$W/bin/tests/host-only.txt"

if systemd-run --user --scope -q bash -c 'test -e "/sys/fs/cgroup$(sed -n "s/^0:://p" /proc/self/cgroup)/memory.max"' 2>/dev/null; then
  printf 'python3 -c "x=b\\"1\\"*(64<<20)"\necho survived\n' >"$W/bin/tests/oom.test.sh"
  out=$(TEST_MEM_MAX=48M RUN_TESTS_ROOT="$W" bash "$RUN" --only '*oom*' 2>&1); rc=$?
  is  'over-cap run exits 1' "$rc" 1
  has 'over-cap file is reported oom' "$out" '^FAIL bin/tests/oom\.test\.sh [0-9.]+ oom$'
  has 'only the allocating child is killed' "$out" '^  \| survived$'
  has 'runner survives to its summary' "$(tail -1 <<<"$out")" '^FAIL 0/1 files in [0-9]+ s$'
  # T1407: a child that ignores SIGTERM (a spinning ffmpeg) dies with its timed-out file's scope.
  deaf="sleep 302.$$"
  printf "bash -c 'trap \"\" TERM; exec %s' &\n%s\n" "$deaf" "$hang" >"$W/bin/tests/deaf.test.sh"
  out=$(RUN_TESTS_ROOT="$W" RUN_TESTS_TIMEOUT=2 bash "$RUN" --only '*deaf*' 2>&1)
  has 'deaf child: its file is cut by the timeout' "$out" '^FAIL bin/tests/deaf\.test\.sh [0-9.]+ timeout$'
  is  'deaf child: no TERM-ignoring child outlives its file' "$(pgrep -fx "$deaf" | wc -l)" 0
  pkill -KILL -fx "$deaf" 2>/dev/null; rm -f "$W/bin/tests/deaf.test.sh"
else
  echo 'SKIP needs a memory controller in user scopes: 6 over-cap oom and deaf-child cases (fresh container)'
fi

# cpu_s (T648): a stub burning ~1 CPU s reads 0.7-1.5, a sleep 1 stub < 0.2; scoped (cgroup cpu.stat) and no-bus (`times`) paths.
printf 'python3 -c "import time\nt = time.process_time()\nwhile time.process_time() - t < 1: pass"\n' >"$W/bin/tests/burn.test.sh"
printf 'sleep 1\n' >"$W/bin/tests/nap.test.sh"
cpu_of() { awk -F'\t' -v f="bin/tests/$1.test.sh" '$2 == f { c = $6 } END { print c }' "$H"; }
in_range() { awk -v c="$1" -v lo="$2" -v hi="$3" 'BEGIN { print (c != "" && c + 0 >= lo && c + 0 <= hi) ? "yes" : "no " c }'; }
out=$(RUN_TESTS_ROOT="$W" bash "$RUN" -j 2 --only '*/[bn][ua][rp]*' 2>&1)
is  'selftest: cpu runs pass' "$(tail -1 <<<"$out" | grep -cE '^PASS 2/2 files')" 1
is  'cpu: scoped burn reads 0.7-1.5 s' "$(in_range "$(cpu_of burn)" 0.7 1.5)" yes
is  'cpu: scoped sleep 1 reads < 0.2 s' "$(in_range "$(cpu_of nap)" 0 0.19)" yes
has 'cpu: summary names the burner first' "$out" '^cpu: [0-9.]+ s total, top 3: [0-9.]+ bin/tests/burn\.test\.sh, '
env -u DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR=/nonexistent RUN_TESTS_ROOT="$W" bash "$RUN" -j 2 --only '*/[bn][ua][rp]*' >/dev/null 2>&1
is  'cpu: no-bus burn reads 0.7-1.5 s' "$(in_range "$(cpu_of burn)" 0.7 1.5)" yes
is  'cpu: no-bus sleep 1 reads < 0.2 s' "$(in_range "$(cpu_of nap)" 0 0.19)" yes
rm "$W/bin/tests/burn.test.sh" "$W/bin/tests/nap.test.sh"

RUN_TESTS_ROOT="$W" bash "$RUN" --bogus >/dev/null 2>&1; is 'unknown argument exits 2' "$?" 2
bash "$RUN" -h | grep -q 'run.sh \[-j N\]'; is '-h prints usage' "$?" 0

# A nested run.sh (a fixture suite inside a test) sees only its own root, even when the outer run had RUN_TESTS_ROOT set.
N="$W/nest"; mkdir -p "$N/outer/bin/tests" "$N/inner/bin/tests"
cp "$RUN" "$N/inner/bin/tests/run.sh"; printf 'echo inner fine\n' >"$N/inner/bin/tests/own.test.sh"
printf '[ -n "${NESTED:-}" ] && { echo "LEAK nested run reached the outer root"; exit 0; }\nNESTED=1 bash %q -j 1 >%q 2>&1\n' "$N/inner/bin/tests/run.sh" "$N/inner.out" >"$N/outer/bin/tests/nest.test.sh"
out=$(RUN_TESTS_ROOT="$N/outer" RUN_TESTS_TIMEOUT=20 bash "$RUN" -j 1 2>&1)
is  'nested full run under the holder is not blocked' "$(tail -1 <<<"$out" | grep -cE '^PASS 1/1 files')" 1
has 'nested run.sh runs only its own root' "$(cat "$N/inner.out" 2>/dev/null)" '^PASS 1/1 files'
is  'nested run.sh never reaches the outer root' "$(grep -c 'nest.test.sh' "$N/inner.out" 2>/dev/null)" 0

# One full run at a time: a second full run waits on the lock, --only runs and --no-wait do not.
S="$W/lock"; mkdir -p "$S/bin/tests"
printf 'echo "s $(date +%%s.%%N)" >>%q; sleep 1.5; echo "e $(date +%%s.%%N)" >>%q\n' "$S/spans" "$S/spans" >"$S/bin/tests/slow.test.sh"
RUN_TESTS_ROOT="$S" bash "$RUN" -j 1 >"$S/a.out" 2>&1 & a=$!
sleep 0.5
RUN_TESTS_ROOT="$S" bash "$RUN" -j 1 >"$S/b.out" 2>&1 & b=$!
wait $a $b
is  'two full runs are serialised' "$(awk '{print $1}' "$S/spans" | paste -sd ' ')" 's e s e'
has 'the second run says who holds the lock' "$(cat "$S/b.out")" '^waiting for the suite lock held by pid [0-9]+'
exec 9>>"$RUN_TESTS_LOCK"; flock -n 9; echo "pid $$ T505-test" >"$RUN_TESTS_LOCK"
out=$(RUN_TESTS_ROOT="$S" timeout 10 bash "$RUN" --only '*slow*' 2>&1)
is  '--only run is not blocked by the lock' "$(tail -1 <<<"$out" | grep -cE '^PASS 1/1 files')" 1
out=$(RUN_TESTS_ROOT="$S" timeout 10 bash "$RUN" --no-wait 2>&1); rc=$?
is  '--no-wait full run exits 75 while held' "$rc" 75
has '--no-wait names the holder' "$out" 'T505-test'
exec 9>&-

# Noexec TMPDIR (T523): a stub written under `mktemp -d` still runs. Fixture: docker's --tmpfs /tmp (noexec) with only
# a throwaway dir bound; bwrap has no noexec flag and AppArmor's unpriv_bwrap denies mounting one. No docker/image: skip.
img=ubuntu:24.04
if docker image inspect "$img" >/dev/null 2>&1; then
  X="$W/noexec"; mkdir -p "$X/root/bin/tests" "$X/home"
  cp "$RUN" "$X/root/bin/tests/run.sh"
  printf 'd=$(mktemp -d) && printf "#!/bin/sh\\necho stub ran\\n" >"$d/stub" && chmod +x "$d/stub" && "$d/stub"\n' >"$X/root/bin/tests/stub.test.sh"
  out=$(timeout 60 docker run --rm --network none -u "$(id -u):$(id -g)" --tmpfs /tmp -e HOME="$X/home" -e TMPDIR=/tmp \
    -v "$X:$X" "$img" bash -c 'printf "#!/bin/sh\n" >/tmp/probe && chmod +x /tmp/probe; /tmp/probe 2>/dev/null; echo "selftest rc=$?"
      bash "$1/root/bin/tests/run.sh" --only "*stub*" 2>&1; [ -d "$HOME/.cache/fleet-tests" ] && echo "left=$(ls -A "$HOME/.cache/fleet-tests" | wc -l)"' _ "$X" 2>&1)
  has 'selftest: the inherited TMPDIR is noexec' "$out" '^selftest rc=126$'
  has 'noexec TMPDIR: a mktemp -d stub runs' "$out" '^ok bin/tests/stub\.test\.sh '
  has 'noexec TMPDIR: run passes' "$out" '^PASS 1/1 files'
  has 'noexec TMPDIR: the per-run dir is removed at exit' "$out" '^left=0$'
else
  echo "skip noexec TMPDIR: no docker or no local $img"
fi

# Skill tests (T530): only with --skills or --only 'skills/...'; a symlinked skill dir counts once and runs from the first
# dir that lists it; make-lesson is skipped; `docker` resolves to the run's shim, never the real one.
K="$W/sk"; R="$K/root"; mkdir -p "$R/bin/tests" "$R/skills/foo/tests" "$K/claude/make-lesson/tests"
ln -s "$R/skills/foo" "$K/claude/foo"
printf 'echo plain\n' >"$R/bin/tests/plain.test.sh"
printf 'echo "$(command -v docker) rc=$(docker ps >/dev/null 2>&1; echo $?) cwd=$PWD" >%q\n' "$K/dock.out" >"$R/skills/foo/tests/dock.test.sh"
printf 'touch %q\n' "$K/lesson.ran" >"$K/claude/make-lesson/tests/x.test.sh"
mkdir -p "$R/skills/held/tests"; printf 'held\tfixture pause\n# comment\n' >"$R/bin/tests/paused-skills.txt"
printf 'touch %q\n' "$K/held.ran" >"$R/skills/held/tests/h.test.sh"
sk() { RUN_TESTS_ROOT="$R" RUN_TESTS_SKILLS="$K/claude:$R/skills" bash "$RUN" -j 2 "$@" 2>&1; }
out=$(sk)
is  'skills: a full run without --skills leaves them out' "$(tail -1 <<<"$out" | grep -cE '^PASS 1/1 files')" 1
is  'skills: no skill test ran without --skills' "$(test -e "$K/dock.out" && echo ran || echo none)" none
out=$(sk --skills)
is  'skills: --skills adds the symlinked skill once' "$(tail -1 <<<"$out" | grep -cE '^PASS 2/2 files')" 1
has 'skills: listed under a skills/ label' "$out" '^ok skills/foo/tests/dock\.test\.sh [0-9.]+$'
has 'skills: make-lesson is listed as skipped' "$out" '^skip skills/make-lesson/tests/x\.test\.sh \(ailearning is off limits\)$'
is  'skills: make-lesson never runs' "$(test -e "$K/lesson.ran" && echo ran || echo none)" none
has 'skills: a paused-skills.txt row is listed as skipped' "$out" '^skip skills/held/tests/h\.test\.sh \(fixture pause\)$'
is  'skills: a paused skill never runs' "$(test -e "$K/held.ran" && echo ran || echo none)" none
has 'selftest: docker in a skill test is the run shim' "$(cat "$K/dock.out" 2>/dev/null)" '/run-tests\.[A-Za-z0-9]+/shim/docker rc=125 '
is  'skills: runs from the first dir that lists it' "$(sed -n 's/.* cwd=//p' "$K/dock.out" 2>/dev/null)" "$K/claude/foo/tests"
rm -f "$K/dock.out"
out=$(sk --only 'skills/*')
is  "skills: --only 'skills/*' runs only skill tests" "$(tail -1 <<<"$out" | grep -cE '^PASS 1/1 files')" 1
has 'skills: timings row for the skill test' "$(cat "$R/state/test-timings.tsv" 2>/dev/null)" '^skills/foo/tests/dock\.test\.sh	[0-9.]+	0	[0-9]+\.[0-9]$'

# Sudo shim (T538): every file sees lib/sudo-shim as `sudo` (argv logged, `-n true` by SUDO_SHIM_MODE, the rest rc 1);
# a `# live-sudo` header keeps the real one. The fixture tests only resolve `sudo`; nothing calls the real sudo.
U="$W/su"; mkdir -p "$U/bin/tests/lib"; cp "$(dirname "$RUN")/lib/sudo-shim" "$U/bin/tests/lib/"; cp "$RUN" "$U/bin/tests/run.sh"
printf 'echo "path=$(command -v sudo)" >%q\nsudo -n true; echo "deny=$?" >>%q\nSUDO_SHIM_MODE=allow sudo -n true; echo "allow=$?" >>%q\nsudo -n ufw status; echo "rest=$?" >>%q\ncat "$SUDO_SHIM_LOG" >>%q\necho "rootlog=${PC_TEST_ROOT_LOG:-}" >>%q\n' \
  "$U/shim.out" "$U/shim.out" "$U/shim.out" "$U/shim.out" "$U/shim.out" "$U/shim.out" >"$U/bin/tests/shim.test.sh"
printf '#!/usr/bin/env bash\n# live-sudo: fixture\necho "path=$(command -v sudo)" >%q\necho "rootlog=${PC_TEST_ROOT_LOG:-}" >>%q\n' "$U/live.out" "$U/live.out" >"$U/bin/tests/live.test.sh"
out=$(bash "$U/bin/tests/run.sh" -j 2 2>&1)
is  'sudo: both files pass' "$(tail -1 <<<"$out" | grep -cE '^PASS 2/2 files')" 1
has 'selftest: sudo in a test is the run shim' "$(cat "$U/shim.out" 2>/dev/null)" '^path=.*/run-tests\.[A-Za-z0-9]+/sudo/sudo$'
has 'sudo shim: -n true is denied by default' "$(cat "$U/shim.out" 2>/dev/null)" '^deny=1$'
has 'sudo shim: SUDO_SHIM_MODE=allow answers -n true' "$(cat "$U/shim.out" 2>/dev/null)" '^allow=0$'
has 'sudo shim: any other command is refused rc 1' "$(cat "$U/shim.out" 2>/dev/null)" '^rest=1$'
has 'sudo shim: argv is logged with the test file' "$(cat "$U/shim.out" 2>/dev/null)" '^bin/tests/shim\.test\.sh	-n ufw status$'
is  'live-sudo header keeps the real sudo' "$(sed -n 's/^path=//p' "$U/live.out" 2>/dev/null)" "$(command -v sudo)"
is  'live-sudo file logs pc_root calls to state (T1136)' "$(sed -n 's/^rootlog=//p' "$U/live.out" 2>/dev/null)" "$U/state/test-root-calls.tsv"
has 'a shimmed file gets no root log' "$(cat "$U/shim.out" 2>/dev/null)" '^rootlog=$'

# Private TMPDIR per file (T632): a test's mktemp lands in the run root, removed when it exits or is killed by the
# timeout; `tmp residue` counts new tmp.* in the base TMPDIR (a test that writes there by hand is the control).
P="$W/tmpres"; mkdir -p "$P/root/bin/tests" "$P/base"
printf 'd=$(mktemp -d) && touch "$d/x" && echo "$d" >%q\n' "$P/leave.out" >"$P/root/bin/tests/leave-it.test.sh"
printf 'd=$(mktemp -d) && touch "$d/x" && echo "$d" >%q && %s\n' "$P/killed.out" "$hang" >"$P/root/bin/tests/killed.test.sh"
out=$(TMPDIR="$P/base" RUN_TESTS_ROOT="$P/root" RUN_TESTS_TIMEOUT=2 bash "$RUN" -j 2 2>&1)
has 'tmpdir: the killed test is cut by the timeout' "$out" '^FAIL bin/tests/killed\.test\.sh [0-9.]+ timeout$'
has 'tmpdir: mktemp lands in a per-file dir under the run root' "$(cat "$P/leave.out" 2>/dev/null)" '/tmpres/base/fleet-tmp\.[A-Za-z0-9]{6}/t\.[A-Za-z0-9]{4}/tmp\.'
is  'tmpdir: each file gets its own dir' "$([ "$(dirname "$(cat "$P/killed.out")")" != "$(dirname "$(cat "$P/leave.out")")" ] && echo own || echo shared)" own
has 'tmpdir: residue line reads 0' "$out" '^tmp residue: 0 dirs$'
is  'tmpdir: left and killed dirs are removed' "$(test -e "$(cat "$P/leave.out")" || test -e "$(cat "$P/killed.out")" && echo left || echo gone)" gone
is  'tmpdir: nothing left in the base TMPDIR' "$(ls -A "$P/base" | wc -l)" 0
printf 'mkdir %q\n' "$P/base/tmp.leak" >"$P/root/bin/tests/leak.test.sh"
out=$(TMPDIR="$P/base" RUN_TESTS_ROOT="$P/root" bash "$RUN" --only '*leak*' 2>&1)
has 'tmpdir: a dir left in the base is counted' "$out" '^tmp residue: 1 dirs$'
printf '# bwrap --tmpfs /tmp\necho "$TMPDIR" >%q\n' "$P/own.out" >"$P/root/bin/tests/own.test.sh"
TMPDIR="$P/base" RUN_TESTS_ROOT="$P/root" bash "$RUN" --only '*own*' >/dev/null 2>&1
is  'tmpdir: a file that mounts its own /tmp keeps the base TMPDIR' "$(cat "$P/own.out" 2>/dev/null)" "$P/base"

# --skip-unchanged (T717, T849): a heavy green skill test is skipped while none of its own inputs is newer than its last history row.
Q="$W/skipu"; R2="$Q/root"; H2=$R2/skills/heavy
mkdir -p "$R2/bin" "$R2/state" "$H2/tests/fixtures" "$H2/scripts/__pycache__" "$H2/templates/cpp-vulkan" "$H2/data" "$R2/skills/other/scripts"
printf 'bash "$(dirname "$0")/../scripts/run.sh" fixtures/in.json\n# unused.sh is only named in a comment\ntouch %q\n' "$Q/heavy.ran" >"$H2/tests/h.test.sh"
printf 'echo heavy\n' >"$H2/tests/fixtures/in.json"
printf '~/agents/skills/other/scripts/o.sh; ~/agents/bin/tool; helper.sh\n' >"$H2/scripts/run.sh"
for f in helper.sh unused.sh lone.sh mvlib.sh new-cpp-game; do printf 'echo %s\n' "$f" >"$H2/scripts/$f"; done
printf 'source "$(dirname "${BASH_SOURCE[0]}")/../../other/scripts/ci-lib.sh"\n' >"$H2/scripts/mvlib.sh"
printf 'set(x)\n' >"$H2/templates/cpp-vulkan/CMakeLists.txt"; printf 'd\n' >"$H2/data/extra.txt"
printf '# inputs: data/*.txt\nnew-cpp-game; touch %q\n' "$Q/cpp.ran" >"$H2/tests/cpp-x.test.sh"
printf 'echo o\n' >"$R2/skills/other/scripts/o.sh"; printf 'ci_log() { :; }\n' >"$R2/skills/other/scripts/ci-lib.sh"; printf 'echo t\n' >"$R2/bin/tool"; : >"$H2/scripts/__pycache__/x.pyc"; : >"$Q/dpkg"
printf 'fxtool\tfx-pkg-a\tx\ttest\nfxmedia\tfx-pkg-m\tx\toptional:media\nfxadv\tfx-pkg-v\tx\tadvisory\n' >"$R2/bin/DEPS.tsv"
printf 'fx-pkg-a 1.0\nfx-pkg-m 1.0\nfx-pkg-v 1.0\n' >"$Q/versions"; mkdir "$Q/stub"
printf '#!/bin/sh\nshift 3\nfor p; do grep "^$p " %q; done\nexit 0\n' "$Q/versions" >"$Q/stub/dpkg-query"; chmod +x "$Q/stub/dpkg-query"
old() { find "$Q" -exec touch -h -d '1 hour ago' {} +; }
seed() { for t in h cpp-x ${extra:-}; do printf '%s\tskills/heavy/tests/%s.test.sh\t30.0\t%s\t1.0\t%s\n' "$(date +%FT%T)" "$t" "${1:-0}" "${2:-25.0}"; done >>"$R2/state/test-timings-history.tsv"; }
sku() { rm -f "$Q"/*.ran; PATH="$Q/stub:$PATH" RUN_TESTS_ROOT="$R2" RUN_TESTS_SKILLS="$R2/skills" RUN_TESTS_SKIP_DEPS="$Q/dpkg" bash "$RUN" --only 'skills/*' "$@" 2>&1; }
ran() { test -e "$Q/${1:-heavy}.ran" && echo ran || echo skipped; }
touched() { old; seed; touch "$@"; sku --skip-unchanged >/dev/null; }
seed; sku --skip-unchanged --plan >/dev/null
is  'plan: writes no apt deps stamp or pointer' "$(ls "$R2/state" | grep -c skip-deps)" 0
sku --skip-unchanged >/dev/null
is  'skip-unchanged: the apt deps stamp is written once per version set' "$(ls "$R2/state/skip-deps" | wc -l)" 1
old; seed; out=$(sku --skip-unchanged)
is  'skip-unchanged: untouched heavy green test is skipped' "$(ran)" skipped
has 'skip-unchanged: SKIP line names date and CPU s' "$out" '^SKIP unchanged skills/heavy/tests/h\.test\.sh \(green 20[0-9-]{8}, 25\.0 CPU s\)$'
has 'skip-unchanged: counted ok, summary adds skipped and saved' "$(tail -1 <<<"$out")" '^PASS 2/2 files in [0-9]+ s, skipped 2, saved ~50\.0 CPU s$'
old; seed; sku >/dev/null; is 'skip-unchanged: without the flag it runs' "$(ran)" ran
touched "$H2/scripts/__pycache__/x.pyc"; is 'skip-unchanged: __pycache__ is ignored' "$(ran)" skipped
touched "$H2/tests/h.test.sh"; is 'skip-unchanged: touched test file runs' "$(ran)" ran
touched "$H2/scripts/run.sh"; is 'skip-unchanged: touched named script runs' "$(ran)" ran
touched "$H2/scripts/helper.sh"; is 'skip-unchanged: a script named by a named script runs' "$(ran)" ran
touched "$H2/tests/fixtures/in.json"; is 'skip-unchanged: touched named fixture runs' "$(ran)" ran
touched "$H2/scripts/lone.sh"; is 'skip-unchanged: unrelated script in the same skill keeps the skip' "$(ran)" skipped
touched "$H2/scripts/unused.sh"; is  'skip-unchanged: a name in a comment is not an input' "$(ran)" skipped
touched "$H2/scripts/mvlib.sh"; is 'skip-unchanged: touched shared lib runs' "$(ran)" ran
touched "$R2/skills/other/scripts/ci-lib.sh"; is 'skip-unchanged: a ../../<skill>/ file a shared lib sources runs' "$(ran)" ran
touched "$H2/templates/cpp-vulkan/CMakeLists.txt"; is 'skip-unchanged: template change re-runs a new-cpp-game test' "$(ran cpp)" ran
is  'skip-unchanged: template change keeps the skip of a test that names no template' "$(ran)" skipped
touched "$H2/data/extra.txt"; is 'skip-unchanged: an `# inputs:` glob match runs' "$(ran cpp)" ran
touched "$R2/skills/other/scripts/o.sh"; is 'skip-unchanged: touched named file of another skill runs' "$(ran)" ran
touched "$R2/bin/tool"; is 'skip-unchanged: touched named bin file runs' "$(ran)" ran
touched "$Q/dpkg"; is 'skip-unchanged: a newer RUN_TESTS_SKIP_DEPS path runs' "$(ran)" ran
old; seed 1; sku --skip-unchanged >/dev/null; is 'skip-unchanged: red last row runs' "$(ran)" ran
old; seed 0 5.0; sku --skip-unchanged >/dev/null; is 'skip-unchanged: light test (< 20 CPU s) runs' "$(ran)" ran
old; seed; touch "$H2/scripts/helper.sh"; out=$(sku --skip-unchanged --plan); rc=$?
is  'plan: exits 0' "$rc" 0
is  'plan: runs nothing' "$(ran)$(ran cpp)" skippedskipped
has 'plan: a blocked test names its blocking input' "$out" '^run skills/heavy/tests/h\.test\.sh: scripts/helper\.sh newer than green 20[0-9-]{8} [0-9:]{8}$'
has 'plan: a skippable test is listed' "$out" '^skip skills/heavy/tests/cpp-x\.test\.sh \(green 20[0-9-]{8}, 25\.0 CPU s\)$'
has 'plan: summary counts files and CPU s' "$(tail -1 <<<"$out")" '^would skip 1 files, 25\.0 CPU s$'

# Apt input (T895): the DEPS.tsv package versions at the skill's levels, not /var/lib/dpkg/status; fixtures count by path only.
sed -i 's/^fx-pkg-m 1.0/fx-pkg-m 2.0/; s/^fx-pkg-v 1.0/fx-pkg-v 2.0/' "$Q/versions"
touched "$Q/versions"; is 'apt: optional:media and advisory version changes keep the skip of a non-media skill' "$(ran)" skipped
sed -i 's/^fx-pkg-a 1.0/fx-pkg-a 1.1/' "$Q/versions"; old; seed; sku --skip-unchanged >/dev/null; is 'apt: a DEPS package version change runs' "$(ran)" ran
sed -i 's/^fx-pkg-a 1.1/fx-pkg-a 1.2/' "$Q/versions"; old; seed; touch "$Q/mark"; out=$(sku --skip-unchanged --plan)
has 'apt: plan names the apt deps stamp as the blocker' "$out" '^run skills/heavy/tests/h\.test\.sh: apt deps [0-9a-f]{8} since 20[0-9-]{8} [0-9:]{8} newer than green '
is  'plan: a new version set writes nothing under state/' "$(find "$R2/state" -newer "$Q/mark" | wc -l)" 0
sku --skip-unchanged >/dev/null
dst=$(stat -c %Y /var/lib/dpkg/status 2>/dev/null || date +%s); printf 'fx-unrelated 9.9\n' >>"$Q/versions"
find "$Q" -exec touch -h -d "@$((dst - 7200))" {} +
printf '%s\tskills/heavy/tests/h.test.sh\t30.0\t0\t1.0\t25.0\n' "$(date -d "@$((dst - 3600))" +%FT%T)" >>"$R2/state/test-timings-history.tsv"
rm -f "$Q"/*.ran; env -u RUN_TESTS_SKIP_DEPS -u VCPKG_ROOT HOME="$Q/home" PATH="$Q/stub:$PATH" RUN_TESTS_ROOT="$R2" RUN_TESTS_SKILLS="$R2/skills" \
  bash "$RUN" --only 'skills/heavy/tests/h.*' --skip-unchanged >/dev/null 2>&1
is  'apt: an unrelated install (dpkg status newer than green) keeps the skip' "$(ran)" skipped
# T944: a DEPS package not installed counts as `<pkg> absent` (no backdating to an older .list); a set seen before is re-stamped
# when it comes back. coreutils gives the fixture set a real, old dpkg .list mtime to backdate to (read only).
printf 'fxbase\tcoreutils\tx\trequired\n' >>"$R2/bin/DEPS.tsv"; printf 'coreutils 9.5\n' >>"$Q/versions"; old; seed; sku --skip-unchanged >/dev/null
sed -i '/^fx-pkg-a /d' "$Q/versions"; old; seed; sku --skip-unchanged >/dev/null; is 'apt: a removed DEPS package runs' "$(ran)" ran
printf 'fx-pkg-a 1.2\n' >>"$Q/versions"; old; seed; sku --skip-unchanged >/dev/null; is 'apt: a set seen before that comes back runs' "$(ran)" ran
old; seed; sku --skip-unchanged >/dev/null; is 'apt: the same set again keeps the skip' "$(ran)" skipped
sed -i 's/^fx-pkg-a 1.2$/fx-pkg-a 1.2 config-files/' "$Q/versions"; old; seed; sku --skip-unchanged >/dev/null
is  'apt: a package left in config-files state counts as absent and runs' "$(ran)" ran
mkdir -p "$H2/tests/fixtures/plates/pl-a" "$H2/tests/fixtures/plates/pl-b"; : >"$H2/tests/fixtures/plates/pl-a/f"; : >"$H2/tests/fixtures/plates/pl-b/f"
printf 'echo no plates here; touch %q\n' "$Q/plw.ran" >"$H2/tests/plw.test.sh"
printf '. "$HERE/fixtures/plates/plates.sh"\nplates pl-a; touch %q\n' "$Q/pl.ran" >"$H2/tests/pl.test.sh"; : >"$H2/tests/fixtures/plates/plates.sh"
extra='plw pl'
touched "$H2/tests/fixtures/plates/pl-b/f"; is 'fixtures: the bare word plates is not blocked by fixtures/plates' "$(ran plw)" skipped
is  'fixtures: plates <name> is not blocked by another plate' "$(ran pl)" skipped
touched "$H2/tests/fixtures/plates/pl-a/f"; is 'fixtures: plates <name> runs on its own plate' "$(ran pl)" ran
touched "$H2/tests/fixtures/plates/plates.sh"; is 'fixtures: a deeper fixtures/<x>/<file> path runs' "$(ran pl)" ran
is  'fixtures: ... and only that test' "$(ran plw)" skipped

# Per-file timeout (T725): clamp(2 x p50 wall of the last 5 ok history rows, RUN_TESTS_TIMEOUT, 600); the summary names raised caps.
C="$W/caps"; mkdir -p "$C/bin/tests" "$C/state"
for f in p120 p400 p50 none; do printf 'echo %s\n' "$f" >"$C/bin/tests/$f.test.sh"; done
hrow() { printf '%s\tbin/tests/%s.test.sh\t%s\t%s\t1.0\t1.0\n' "$(date +%FT%T)" "$1" "$2" "${3:-0}" >>"$C/state/test-timings-history.tsv"; }
for s in 10 10 100 120 130 110 140; do hrow p120 "$s"; done; hrow p120 999 124; hrow p120 900 1
for s in 400 400 400; do hrow p400 "$s"; done
for s in 40 60; do hrow p50 "$s"; done
out=$(RUN_TESTS_ROOT="$C" bash "$RUN" -j 4 2>&1)
has 'caps: p50 120 of the last 5 ok runs -> 240, p50 400 -> 600 (cap)' "$out" '^timeouts raised: 240 s bin/tests/p120\.test\.sh \(p50 120\.0\), 600 s bin/tests/p400\.test\.sh \(p50 400\.0\)$'
is  'caps: p50 50 and no history keep 170' "$(grep -cE 'p50\.test|none\.test' <<<"$(grep '^timeouts raised' <<<"$out")")" 0
has 'caps: run passes' "$(tail -1 <<<"$out")" '^PASS 4/4 files'
D="$W/caps2"; mkdir -p "$D/bin/tests" "$D/state"
printf 'sleep 3\n' >"$D/bin/tests/known.test.sh"; printf 'sleep 3\n' >"$D/bin/tests/fresh.test.sh"
for i in 1 2 3; do printf '%s\tbin/tests/known.test.sh\t2.0\t0\t1.0\t0.0\n' "$(date +%FT%T)" >>"$D/state/test-timings-history.tsv"; done
out=$(RUN_TESTS_ROOT="$D" RUN_TESTS_TIMEOUT=2 bash "$RUN" -j 2 2>&1)
has 'caps: a raised cap (2 x 2 s) lets a 3 s file finish' "$out" '^ok bin/tests/known\.test\.sh [0-9.]+$'
has 'caps: a file with no history keeps RUN_TESTS_TIMEOUT' "$out" '^FAIL bin/tests/fresh\.test\.sh [0-9.]+ timeout$'

# Quiet-gated serial tail (T776): files in quiet-gated.txt run after the pool drains, one at a time; a timeout is still FAIL.
G="$W/quiet"; mkdir -p "$G/bin/tests"
for b in busy1 busy2; do printf 'touch %q; sleep 1; rm -f %q\n' "$G/on.$b" "$G/on.$b" >"$G/bin/tests/$b.test.sh"; done
printf 'sleep 0.3; ls %q/on.* >/dev/null 2>&1 && { echo "FAIL ran beside the pool"; exit 1; }; echo alone\n' "$G" >"$G/bin/tests/lonely.test.sh"
out=$(RUN_TESTS_ROOT="$G" bash "$RUN" -j 3 2>&1)
has 'selftest: unlisted lonely stub fails beside the pool' "$out" '^FAIL bin/tests/lonely\.test\.sh [0-9.]+$'
printf '# fixture\nbin/tests/lonely.test.sh  # fails beside another stub\nbin/tests/stuck.test.sh  # hangs\n' >"$G/bin/tests/quiet-gated.txt"
echo "$hang" >"$G/bin/tests/stuck.test.sh"
out=$(RUN_TESTS_ROOT="$G" RUN_TESTS_TIMEOUT=2 bash "$RUN" -j 3 2>&1)
has 'tail: headline counts the quiet-gated files' "$out" '^serial tail: 2 quiet-gated$'
has 'tail: listed lonely stub passes after the pool' "$out" '^ok bin/tests/lonely\.test\.sh [0-9]+\.[0-9]$'
is  'tail: runs after every pool file' "$(awk '/^(ok|FAIL) bin\//{print $2}' <<<"$out" | tail -n 2 | sort | paste -sd ' ')" 'bin/tests/lonely.test.sh bin/tests/stuck.test.sh'
has 'tail: a timed-out tail file is FAIL' "$out" '^FAIL bin/tests/stuck\.test\.sh [0-9.]+ timeout$'
has 'tail: summary counts tail files' "$(tail -1 <<<"$out")" '^FAIL 3/4 files in [0-9]+ s$'
out=$(RUN_TESTS_ROOT="$G" bash "$RUN" --only 'bin/tests/lonely.test.sh' 2>&1)
has '--only one quiet-gated file still runs it' "$(tail -1 <<<"$out")" '^PASS 1/1 files in [0-9]+ s$'

# Creative ledger (T861): ci_log in a test lands in the run's own ledger; a test that forces the real path FAILs the run.
L="$W/led"; RL="$HARNESS_HOME/log/creative-ci.jsonl"; mkdir -p "$L/bin/tests" "${RL%/*}"; echo '{"seed": 1}' >"$RL"
LIB="$(cd "$(dirname "$RUN")/../.." && pwd)/skills/gamedev/scripts/ci-lib.sh"
printf 'source %q; echo "{}" >s.json; ci_log cpp-ci demo true "[]" s.json; echo "$CREATIVE_CI_LOG $(wc -l <"$CREATIVE_CI_LOG")" >%q\n' "$LIB" "$L/own.out" >"$L/bin/tests/own.test.sh"
out=$(RUN_TESTS_ROOT="$L" bash "$RUN" 2>&1); rc=$?
is  'ledger: a ci_log test passes' "$rc" 0
has 'ledger: its row lands in the run root ledger' "$(cat "$L/own.out" 2>/dev/null)" '/fleet-tmp\.[A-Za-z0-9]{6}/creative-ci\.jsonl 1$'
is  'ledger: the real ledger is unchanged' "$(cat "$RL")" '{"seed": 1}'
is  'ledger: no summary copy in the real dir' "$(find "${RL%/*}" -name '*.json' | wc -l)" 0
has 'ledger: the run ledger is removed at exit' "$(test -e "$(cut -d' ' -f1 "$L/own.out")" && echo left || echo gone)" gone
printf 'source %q; echo "{}" >s.json; CREATIVE_CI_LOG= ci_log cpp-ci demo true "[]" s.json\n' "$LIB" >"$L/bin/tests/force.test.sh"
out=$(RUN_TESTS_ROOT="$L" bash "$RUN" 2>&1); rc=$?
is  'ledger: forcing the real path exits 1' "$rc" 1
has 'ledger: the write is named' "$out" '^run\.sh: tests wrote the real creative ledger \(1 rows, 1 summary copies in '
has 'ledger: the summary is FAIL though every file passed' "$(tail -1 <<<"$out")" '^FAIL 2/2 files in [0-9]+ s$'
rm "$L/bin/tests/force.test.sh"; mkdir -p "${RL%/*}/creative-ci/2026-10-20"
printf 'touch %q\n' "${RL%/*}/creative-ci/2026-10-20/x.json" >"$L/bin/tests/copy.test.sh"
out=$(RUN_TESTS_ROOT="$L" bash "$RUN" --only '*copy*' 2>&1)
has 'ledger: a summary copy alone is caught' "$out" '^run\.sh: tests wrote the real creative ledger \(0 rows, 1 summary copies '
has 'ledger: and FAILs the run' "$(tail -1 <<<"$out")" '^FAIL 1/1 files'
# The scratch ledger counts only rows ci_log tagged with this run's RUN_TESTS_ID (T944); another agent's row is a note.
SC=${RL%/*}/creative-ci-scratch.jsonl
rm "$L/bin/tests/copy.test.sh"; printf 'source %q; CREATIVE_CI_LOG=%q ci_log cpp-ci demo true "[]" none.json\n' "$LIB" "$SC" >"$L/bin/tests/scr.test.sh"
out=$(RUN_TESTS_ROOT="$L" bash "$RUN" --only '*scr*' 2>&1)
has 'ledger: a scratch row tagged with this run is caught' "$out" '^run\.sh: tests wrote the real creative ledger \(1 rows, 0 summary copies '
has 'ledger: and FAILs the run' "$(tail -1 <<<"$out")" '^FAIL 1/1 files'
printf 'echo "{}" >>%q\n' "$SC" >"$L/bin/tests/scr.test.sh"
out=$(RUN_TESTS_ROOT="$L" bash "$RUN" --only '*scr*' 2>&1)
has 'ledger: an untagged scratch row is a note' "$out" '^note: 1 scratch rows from outside the suite$'
has 'ledger: and the run passes' "$(tail -1 <<<"$out")" '^PASS 1/1 files'

# Red records (T904): state/test-fails/<file, / as __>.txt gets `## ts rc load wall` + `  | ` excerpt per red run; 30 days, 20 records kept.
R="$W/fails"; mkdir -p "$R/bin/tests" "$R/state/test-fails"; F="$R/state/test-fails/bin__tests__red.test.sh.txt"
printf 'echo "## 1 brief section"; echo "## Summary"; echo "FAIL red thing"; exit 3\n' >"$R/bin/tests/red.test.sh"; printf 'echo fine\n' >"$R/bin/tests/green.test.sh"
printf '## %s rc 1 load 1 wall 1.0\n  | FAIL too old\n## %s rc 1 load 1 wall 1.0\n  | FAIL recent\n' "$(date -d '31 days ago' +%FT%T)" "$(date -d '29 days ago' +%FT%T)" >"$F"
RUN_TESTS_ROOT="$R" bash "$RUN" >/dev/null 2>&1
has 'fails: red run appends `## ts rc load wall` then its excerpt as `  | ` lines' "$(tail -n 4 "$F")" '^## 20[0-9-]{8}T[0-9:]{8} rc 3 load [0-9.]+ wall [0-9.]+
  \| ## 1 brief section
  \| ## Summary
  \| FAIL red thing$'
is  'fails: the > 30 day record is dropped, the 29 day one kept' "$(grep -cE 'FAIL (too old|recent)$' "$F")" 1
is  'fails: excerpt lines starting `## ` are no records' "$(grep -c '^## ' "$F")" 2
is  'fails: green file writes nothing' "$(ls "$R/state/test-fails")" bin__tests__red.test.sh.txt
for i in $(seq -w 1 20); do printf '## %s rc 1 load 1 wall 1.0\n  | FAIL seed %s\n' "$(date -d "$((30 - ${i#0})) days ago" +%FT%T)" "$i"; done >"$F"
touch -d '31 days ago' "$R/state/test-fails/bin__tests__gone.test.sh.txt"
RUN_TESTS_ROOT="$R" bash "$RUN" >/dev/null 2>&1
is  'fails: 21 reds -> 20 records kept, the oldest seed dropped' "$(grep -c '^## ' "$F") $(grep -c 'FAIL seed 01$' "$F")" '20 0'
is  'fails: a file untouched for > 30 days is deleted' "$(ls "$R/state/test-fails")" bin__tests__red.test.sh.txt

[ $fail = 0 ] && echo "run-sh.test.sh: all green" || echo "run-sh.test.sh: FAILURES"
exit $fail
