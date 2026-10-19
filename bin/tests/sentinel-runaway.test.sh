#!/usr/bin/env bash
# EF03 fixtures for ~/agents/bin/sentinel-runaway: fake /proc + /tmp trees, one per rule.
# Ages are relative to a fake UPTIME so they stay correct however long the run takes.
# Run: bash sentinel-runaway.test.sh
set -uo pipefail
SCRIPT="$HOME/agents/bin/sentinel-runaway"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
UPTIME=500000

mkproc() {
  # mkproc <pid> <comm> <age_s> <cpu_s> <rss_pages> [cmdline args...]
  local pid="$1" comm="$2" age="$3" cpu="$4" rss="$5"; shift 5
  local d="$PROC/$pid"
  mkdir -p "$d/fd"
  local starttime=$(( (UPTIME - age) * 100 ))
  local utime=$(( cpu * 100 ))
  printf '%d (%s) S 1 1 1 0 -1 0 0 0 0 0 %d 0 0 0 20 0 1 0 %d 0 %d 0\n' \
    "$pid" "$comm" "$utime" "$starttime" "$rss" >"$d/stat"
  if [ "$#" -gt 0 ]; then printf '%s\0' "$@" >"$d/cmdline"; else : >"$d/cmdline"; fi
  echo "0::/user.slice/app.slice" >"$d/cgroup"
}
# sync_uptime [epoch] — pin the script's clock (SENTINEL_RUNAWAY_NOW) and write the matching
# /proc/uptime, so a process's start epoch (BOOT + starttime) is the same on every tick. Reading
# `date` twice (here and in the script) let a second boundary shift it by 1 s and drop the strikes.
sync_uptime() { NOW=${1:-$(date +%s)}; echo "$(( NOW - BOOT )).00 0.00" >"$PROC/uptime"; }
setcgroup() { echo "0::/user.slice/dark-eye.service" >"$PROC/$1/cgroup"; }
FUID=4242   # fixture uid
setunit() { echo "0::/user.slice/user-$FUID.slice/user@$FUID.service/$2" >"$PROC/$1/cgroup"; }
setcwd() { ln -sf "$2" "$PROC/$1/cwd"; }
setenviron() { local pid="$1"; shift; printf '%s\0' "$@" >"$PROC/$pid/environ"; }
setfd() { ln -sf "$3" "$PROC/$1/fd/$2"; }
setppid() { sed -i "s/) S 1 /) S $2 /" "$PROC/$1/stat"; }

bad=0
check() {
  local desc="$1" want="$2" log="$WORK/state/sentinel.log"
  local got=0
  [ -f "$log" ] && grep -qF -- "$want" "$log" && got=1
  if [ "$got" = 1 ]; then echo "PASS $desc"; else echo "FAIL $desc (missing: $want)"; bad=$((bad+1)); fi
}
check_absent() {
  local desc="$1" want="$2" log="$WORK/state/sentinel.log"
  if [ -f "$log" ] && grep -qF -- "$want" "$log"; then
    echo "FAIL $desc (should not appear: $want)"; bad=$((bad+1))
  else
    echo "PASS $desc"
  fi
}

# A dry run prints its "would" lines on stdout; the helpers append them to the fixture sentinel.log the checks read.
# Fixture globs, never the machine's own config (FLEET §5.6). $GLOBS overrides per section.
DEFAULT_GLOBS='/tmp/claude-1000/*/*/scratchpad'
GLOBS=""
run() {
  rm -rf "$WORK/state"; mkdir -p "$WORK/state"
  sync_uptime
  AGENT_SCRATCH_GLOBS="${GLOBS:-$DEFAULT_GLOBS}" SENTINEL_RUNAWAY_NOW="$NOW" \
  SENTINEL_STATE_DIR="$WORK/state" SENTINEL_RUNAWAY_PROC="$PROC" SENTINEL_RUNAWAY_TMPROOT="$TMP" \
    "$SCRIPT" --dry-run >>"$WORK/state/sentinel.log"
}

# ---------- Rule 1: sleep loop under a scratchpad, > 60 min, owner session gone ----------
PROC="$WORK/proc1"; TMP="$WORK/tmp1"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
LOOP1='until grep -q done full.log; do sleep 5; done'
mkproc 101 bash 3700 5 2000 bash -c "cd /tmp/claude-1000/-home-x/uuid1/scratchpad/ef && $LOOP1"
mkproc 102 bash 1800 5 2000 bash -c "cd /tmp/claude-1000/-home-x/uuid1/scratchpad/ef && $LOOP1"
mkproc 103 bash 999999 5 2000 bash -c "make -C /srv/x/project"
mkproc 104 bash 3700 5 2000 bash -c "nohup python3 -m http.server 8656 >/tmp/claude-1000/-home-x/uuid1/scratchpad/httpd.log 2>&1 & sleep 2"
mkproc 110 claude 999999 5 5000 claude
mkproc 105 bash 3700 5 2000 bash -c "cd /tmp/claude-1000/-home-x/uuid5/scratchpad/ef && $LOOP1"; setppid 105 110
mkproc 111 claude 999999 5 5000 claude --resume uuid6
mkproc 106 bash 3700 5 2000 bash -c "cd /tmp/claude-1000/-home-x/uuid6/scratchpad/ef && $LOOP1"
run
check      "rule1: old orphan scratchpad sleep loop killed" "would kill pid 101 (rule1"
check_absent "rule1: young scratchpad shell loop spared" "would kill pid 102"
check_absent "rule1: unrelated old bash spared"           "would kill pid 103"
check_absent "rule1: old scratchpad shell with no loop spared" "would kill pid 104"
check_absent "rule1: loop under a live claude parent spared"   "would kill pid 105"
check_absent "rule1: loop whose session a live claude names spared" "would kill pid 106"

# ---------- Rule 2: capture with stdout a pipe with no reader, or a deleted file ----------
PROC="$WORK/proc2"; TMP="$WORK/tmp2"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
mkproc 201 tail 2000 1 500 tail -f /var/log/syslog;            setfd 201 1 'pipe:[9001]'
mkproc 202 tail 2000 1 500 tail -f /var/log/syslog;            setfd 202 1 'pipe:[9002]'
mkproc 203 cat  2000 1 500 cat;                                setfd 203 3 'pipe:[9002]'
mkproc 204 journalctl 2000 1 500 journalctl --user -u dark-eye -f
setfd 204 1 "$TMP/gone-$$"
mkproc 205 tail 1000 1 500 tail -f /var/log/syslog;            setfd 205 1 'pipe:[9005]'
mkproc 206 journalctl 2000 1 500 journalctl --user -f;          setfd 206 1 'socket:[7777]'
mkproc 207 systemd-journal 2000 1 500 systemd-journald;         setfd 207 4 'socket:[7777]'
mkproc 208 tail 2000 1 500 tail -f /var/log/syslog;            setfd 208 1 'socket:[7778]'
mkproc 209 tail 2000 1 500 tail -f /var/log/syslog;            setfd 209 1 'anon_inode:[eventfd]'
run
check        "rule2: unread pipe killed"            "would kill pid 201 (rule2"
check_absent "rule2: pipe with a reader spared"     "would kill pid 202"
check_absent "rule2: reader itself untouched"       "would kill pid 203"
check        "rule2: capture into a deleted file killed" "would kill pid 204 (rule2"
check_absent "rule2: young capture spared"          "would kill pid 205"
check_absent "rule2: socket with a reader spared"   "would kill pid 206"
check_absent "rule2: socket stdout never judged"   "would kill pid 208"
check_absent "rule2: anon_inode stdout spared"     "would kill pid 209"

# ---------- Rule 3: hand-run eye-render/main.js outside dark-eye.service, > 2h ----------
PROC="$WORK/proc3"; TMP="$WORK/tmp3"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
mkproc 301 eye-render 8000 5 2000
mkproc 302 eye-render 8000 5 2000; setcgroup 302
mkproc 303 node 8000 5 2000 node $HOME/the-dark-eye/body/src/main.js
mkproc 304 node 8000 5 2000 node scripts/tts-test.js --bench
run
check        "rule3: hand-run eye-render killed"        "would kill pid 301 (rule3"
check_absent "rule3: dark-eye.service eye-render spared" "would kill pid 302"
check        "rule3: hand-run main.js killed"           "would kill pid 303 (rule3"
check_absent "rule3: unrelated node script spared"      "would kill pid 304"

# TSP-016: Node >= 23 renames its main thread, so comm is "MainThread", not "node".
PROC="$WORK/proc3b"; TMP="$WORK/tmp3b"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
mkproc 4242 MainThread 8000 5 2000 node $HOME/the-dark-eye/body/src/main.js
mkproc 4243 MainThread 8000 5 2000 node /x/other/index.js
run
check        "rule3: MainThread comm matched via argv[0]" "would kill pid 4242 (rule3"
check_absent "rule3: MainThread non-body spared"          "would kill pid 4243"

# TSP-016: a body that carries DARK_EYE_SANDBOX is reaped as a whole sandbox, not one pid.
PROC="$WORK/proc3c"; TMP="$WORK/tmp3c"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
mkproc 4244 MainThread 8000 5 2000 node $HOME/the-dark-eye/body/src/main.js
setenviron 4244 "HOME=$HOME" "DARK_EYE_SANDBOX=t1"
run
check        "rule3: sandbox body reaped by name"   "would take down sandbox t1 (rule3"
check_absent "rule3: sandbox body not killed pid-wise" "would kill pid 4244"

# TSP-016 live path: a stub body-sandbox on PATH, a pid number the kernel cannot allocate,
# and a selftest proving no real process carries it before the run (FLEET §5.6).
PROC="$WORK/proc3d"; TMP="$WORK/tmp3d"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
NOPID=$(( $(cat /proc/sys/kernel/pid_max) + 7 ))
if [ -e "/proc/$NOPID" ] || kill -0 "$NOPID" 2>/dev/null; then
  echo "FAIL selftest: pid $NOPID exists, refusing the live-path case"; bad=$((bad+1))
else
  echo "PASS selftest: pid $NOPID cannot exist, live path is safe"
  mkdir -p "$WORK/stub"
  # the stub exits 0 like the real `down`; STUB_REAP=1 makes the body go (its fake /proc dir)
  cat >"$WORK/stub/body-sandbox" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_CALLS"
[ "${STUB_REAP:-}" = 1 ] && rm -rf "$STUB_PROC/$STUB_PID"
exit 0
STUB
  chmod +x "$WORK/stub/body-sandbox"
  live3() { # live3 <reap 0|1> — one non-dry run with the stub; the body is the NOPID fixture
    mkproc "$NOPID" MainThread 8000 5 2000 node $HOME/the-dark-eye/body/src/main.js
    setenviron "$NOPID" "DARK_EYE_SANDBOX=t1"
    rm -rf "$WORK/state"; mkdir -p "$WORK/state"; : >"$WORK/calls"
    sync_uptime
    PATH="$WORK/stub:$PATH" STUB_CALLS="$WORK/calls" STUB_REAP="$1" STUB_PROC="$PROC" STUB_PID="$NOPID" \
    AGENT_SCRATCH_GLOBS="$DEFAULT_GLOBS" SENTINEL_RUNAWAY_NOW="$NOW" \
    SENTINEL_STATE_DIR="$WORK/state" SENTINEL_RUNAWAY_PROC="$PROC" SENTINEL_RUNAWAY_TMPROOT="$TMP" \
      "$SCRIPT" >/dev/null 2>&1
  }
  live3 1
  if grep -qx -- "down --name t1" "$WORK/calls"; then
    echo "PASS rule3 live: body-sandbox down --name t1 called once"
  else
    echo "FAIL rule3 live: stub not called with 'down --name t1'"; bad=$((bad+1))
  fi
  [ "$(wc -l <"$WORK/calls")" = 1 ] || { echo "FAIL rule3 live: stub called $(wc -l <"$WORK/calls") times"; bad=$((bad+1)); }
  check        "rule3 live: body gone after down, logged taken down" "took down sandbox t1 (rule3"
  check_absent "rule3 live: no pid killed" "killed pid"
  # T114: `down` exits 0 but the body survives (an orphaned eye-render with no sandbox dir)
  live3 0
  check_absent "rule3 survivor: not logged taken down"     "took down sandbox t1"
  check        "rule3 survivor: logged as a failed takedown" "failed to take down sandbox t1: pid $NOPID survived"
  check        "rule3 survivor: killed by pid instead"      "killed pid $NOPID (rule3"
fi

# ---------- Rule 4: portal helper hot (CPU strikes) or fat (RSS), restart not kill ----------
PROC="$WORK/proc4"; TMP="$WORK/tmp4"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
mkproc 401 xdg-desktop-portal-gtk 2000 5 100000     # 400MB RSS, fat
mkproc 402 xdg-desktop-portal-gnome 2000 5 500      # small, quiet
mkproc 404 xdg-desktop-por 2000 5 100000 /usr/libexec/xdg-desktop-portal-gnome  # kernel-truncated comm, real bug case
mkproc 405 gsd-power 2000 5 100000 /usr/libexec/gsd-power
mkproc 406 gjs 2000 5 100000 /usr/bin/gjs                  # in an app scope, no unit of its own
setunit 401 app.slice/xdg-desktop-portal-gtk.service
setunit 404 app.slice/xdg-desktop-portal-gnome.service
setunit 405 session.slice/org.gnome.SettingsDaemon.Power.service
setunit 406 app.slice/app-gnome-foo-1234.scope
run
check        "rule4: fat portal helper restarted"   "would restart xdg-desktop-portal-gtk.service (pid 401"
check_absent "rule4: quiet small helper spared"     "(pid 402"
check        "rule4: truncated comm resolved via argv[0]" "would restart xdg-desktop-portal-gnome.service (pid 404"
check        "rule4: unit read from the cgroup, not the comm" "would restart org.gnome.SettingsDaemon.Power.service (pid 405"
check_absent "rule4: never the user manager"         "user@$FUID.service (pid"
check        "rule4: helper in no unit killed instead" "would kill pid 406 (rule4"

# Live path: a unit that refuses the restart (gsd RefuseManualStop=true) leaves the helper running.
# systemctl is a stub on PATH and the pid is above pid_max, so nothing real is touched (FLEET §5.6).
PROC="$WORK/proc4c"; TMP="$WORK/tmp4c"; mkdir -p "$PROC" "$TMP" "$WORK/stub"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
printf '#!/bin/sh\necho "$*" >>"%s"\necho "Operation refused, unit may not be stopped." >&2\nexit 1\n' "$WORK/stub/calls" >"$WORK/stub/systemctl"
chmod +x "$WORK/stub/systemctl"
mkproc 4194399 gsd-power 2000 5 100000 /usr/libexec/gsd-power
setunit 4194399 session.slice/org.gnome.SettingsDaemon.Power.service
rm -rf "$WORK/state"; mkdir -p "$WORK/state"; sync_uptime
PATH="$WORK/stub:$PATH" AGENT_SCRATCH_GLOBS="$DEFAULT_GLOBS" SENTINEL_RUNAWAY_NOW="$NOW" SENTINEL_RUNAWAY_DRYRULES=legacy,1,2,3,5,6 \
SENTINEL_STATE_DIR="$WORK/state" SENTINEL_RUNAWAY_PROC="$PROC" SENTINEL_RUNAWAY_TMPROOT="$TMP" "$SCRIPT"
if grep -qx -- "--user restart org.gnome.SettingsDaemon.Power.service" "$WORK/stub/calls" 2>/dev/null; then
  echo "PASS rule4 live: restart asked of the cgroup's unit"
else
  echo "FAIL rule4 live: restart asked of the cgroup's unit (got: $(cat "$WORK/stub/calls" 2>/dev/null))"; bad=$((bad+1))
fi
check_absent "rule4 live: refused restart never kills"  "killed pid 4194399"
check        "rule4 live: refused restart logged"       "could not restart org.gnome.SettingsDaemon.Power.service (pid 4194399"

# CPU-strike path needs a real (non-dry) baseline tick so the next tick has state to compare to.
# The script scores pct = 100 * delta_cpu / delta_wall, so a fixed +9 cpu-s per tick only stayed
# over the 90% line while the ticks were under 10 s apart — the test failed intermittently on a
# loaded box. Each tick now adds CPU_STEP cpu-seconds, which keeps pct >= 90 for any gap under
# CPU_STEP/0.9 seconds (~30 h), so wall-clock jitter cannot reach the threshold.
CPU_STEP=100000
tick4b() {  # tick4b <epoch> <cpu_seconds> [--dry-run]
  local at="$1" cpu="$2"; shift 2
  mkproc 403 gsd-color 2000 "$cpu" 500
  setunit 403 session.slice/org.gnome.SettingsDaemon.Color.service
  sync_uptime "$at"
  SENTINEL_RUNAWAY_NOW="$NOW" SENTINEL_STATE_DIR="$WORK/state" SENTINEL_RUNAWAY_PROC="$PROC" SENTINEL_RUNAWAY_TMPROOT="$TMP" \
    "$SCRIPT" "$@" >>"$WORK/state/sentinel.log"
}
PROC="$WORK/proc4b"; TMP="$WORK/tmp4b"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
rm -rf "$WORK/state"; mkdir -p "$WORK/state"
T4=$(date +%s)                                        # ticks 15 min apart on a pinned clock
tick4b $(( T4 - 1800 )) 10 >/dev/null                 # tick 1: baseline, no previous sample
tick4b $(( T4 - 900 )) $(( 10 + CPU_STEP )) >/dev/null   # tick 2: strike 1, persisted
tick4b "$T4" $(( 10 + 2 * CPU_STEP )) --dry-run       # tick 3: strike 2, should trigger
check "rule4: hot helper restarted after strikes" "would restart org.gnome.SettingsDaemon.Color.service (pid 403"

# ---------- Rule 5: scratchpad of a dead session, > 24h ----------
PROC="$WORK/proc5"; TMP="$WORK/tmp5"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
mkdir -p "$TMP/claude-1000/-home-x/uuid-dead/scratchpad"
mkdir -p "$TMP/claude-1000/-home-x/uuid-alive/scratchpad"
mkdir -p "$TMP/claude-1000/-home-x/uuid-young/scratchpad"
mkdir -p "$TMP/claude-1000/-home-x/uuid-viafd/scratchpad"
touch -d '@'"$(( $(date +%s) - 90000 ))" "$TMP/claude-1000/-home-x/uuid-dead/scratchpad"
touch -d '@'"$(( $(date +%s) - 90000 ))" "$TMP/claude-1000/-home-x/uuid-alive/scratchpad"
touch -d '@'"$(( $(date +%s) - 3600 ))"  "$TMP/claude-1000/-home-x/uuid-young/scratchpad"
touch -d '@'"$(( $(date +%s) - 90000 ))" "$TMP/claude-1000/-home-x/uuid-viafd/scratchpad"
mkproc 501 bash 100 1 500 bash -c "cd $TMP/claude-1000/-home-x/uuid-alive/scratchpad && sleep 999999"
mkproc 502 claude 999999 5 5000
setfd 502 32 "$TMP/claude-1000/-home-x/uuid-viafd/tasks"
run
check        "rule5: dead session's scratchpad removed"  "would rm -rf $TMP/claude-1000/-home-x/uuid-dead/scratchpad"
check_absent "rule5: live session (argv) spared"          "uuid-alive/scratchpad"
check_absent "rule5: young scratchpad spared"              "uuid-young/scratchpad"
check_absent "rule5: live session (claude fd) spared"      "uuid-viafd/scratchpad"

# F02: `claude --continue` keeps the uuid out of argv; a fresh transcript or a fresh file inside spares the scratchpad.
PROC="$WORK/proc5b"; TMP="$WORK/tmp5b"; PROJ="$WORK/projects5b"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
OLD='@'"$(( $(date +%s) - 90000 ))"
for u in uuid-cont uuid-busy uuid-stale; do
  mkdir -p "$TMP/claude-1000/-home-x/$u/scratchpad" "$PROJ/-home-x"
  touch "$TMP/claude-1000/-home-x/$u/scratchpad/f" "$PROJ/-home-x/$u.jsonl"
  touch -d "$OLD" "$TMP/claude-1000/-home-x/$u/scratchpad/f" "$TMP/claude-1000/-home-x/$u/scratchpad" "$PROJ/-home-x/$u.jsonl"
done
touch "$PROJ/-home-x/uuid-cont.jsonl"
touch "$TMP/claude-1000/-home-x/uuid-busy/scratchpad/f"
touch -d "$OLD" "$TMP/claude-1000/-home-x/uuid-busy/scratchpad"
mkproc 503 claude 999999 5 5000 claude --continue --remote-control "Command Center"
SENTINEL_RUNAWAY_PROJECTS="$PROJ" run
check_absent "rule5: --continue session with a fresh transcript spared" "uuid-cont/scratchpad"
check_absent "rule5: old dir mtime but a fresh file inside spared"      "uuid-busy/scratchpad"
check        "rule5: stale transcript and stale files still removed"    "would rm -rf $TMP/claude-1000/-home-x/uuid-stale/scratchpad"

# F02 (10-07): a --continue orchestrator idle 25 h. Its uuid is the newest transcript of a project where a claude runs.
PROC="$WORK/proc5c"; TMP="$WORK/tmp5c"; PROJ="$WORK/projects5c"; mkdir -p "$PROC" "$TMP" "$WORK/hm/x/log"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
SLUG=$(echo "$WORK/hm/x" | sed 's/[^a-zA-Z0-9]/-/g')
for su in "$SLUG uuid-old 200000" "$SLUG uuid-idle 90000" "-home-y uuid-gone 90000"; do
  read -r p u a <<<"$su"
  mkdir -p "$TMP/claude-1000/$p/$u/scratchpad" "$PROJ/$p"
  touch "$TMP/claude-1000/$p/$u/scratchpad/f" "$PROJ/$p/$u.jsonl"
  touch -d '@'"$(( $(date +%s) - a ))" "$TMP/claude-1000/$p/$u/scratchpad/f" "$TMP/claude-1000/$p/$u/scratchpad" "$PROJ/$p/$u.jsonl"
done
mkproc 504 claude 999999 5 5000 claude --continue --remote-control "Command Center"
setcwd 504 "$WORK/hm/x/log"
SENTINEL_RUNAWAY_PROJECTS="$PROJ" run
check_absent "rule5: idle 25 h, newest transcript where a claude runs, spared" "uuid-idle/scratchpad"
check        "rule5: an older transcript in that project still removed"    "would rm -rf $TMP/claude-1000/$SLUG/uuid-old/scratchpad"
check        "rule5: newest transcript of a project with no claude removed" "would rm -rf $TMP/claude-1000/-home-y/uuid-gone/scratchpad"

# ---------- GH12: a second scratch glob, from AGENT_SCRATCH_GLOBS ----------
PROC="$WORK/proc7"; TMP="$WORK/tmp7"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
GLOBS="$DEFAULT_GLOBS /tmp/agentwork-*/*/scratch"
mkdir -p "$TMP/agentwork-9/sess-dead/scratch" "$TMP/agentwork-9/sess-live/scratch" "$TMP/elsewhere/sess-dead/scratch"
touch -d '@'"$(( $(date +%s) - 90000 ))" "$TMP/agentwork-9/sess-dead/scratch" \
                                         "$TMP/agentwork-9/sess-live/scratch" \
                                         "$TMP/elsewhere/sess-dead/scratch"
mkdir -p "$TMP/claude-1000/-home-x/uuid-dead/scratchpad"
touch -d '@'"$(( $(date +%s) - 90000 ))" "$TMP/claude-1000/-home-x/uuid-dead/scratchpad"
mkproc 701 bash 3700 5 2000 bash -c "cd $TMP/agentwork-9/sess-live/scratch && while true; do sleep 60; done"
run
check        "glob2 rule1: shell loop under the second glob killed"  "would kill pid 701 (rule1"
check        "glob2 rule5: dead dir under the second glob removed"   "would rm -rf $TMP/agentwork-9/sess-dead/scratch"
check_absent "glob2 rule5: live dir under the second glob spared"    "would rm -rf $TMP/agentwork-9/sess-live/scratch"
check_absent "glob2 rule5: dir matching no glob spared"              "would rm -rf $TMP/elsewhere/sess-dead/scratch"
check        "glob2: the default glob still applies"                 "would rm -rf $TMP/claude-1000/-home-x/uuid-dead/scratchpad"
GLOBS=""

# ---------- Rule 6: a hot Chrome tree that no Playwright tool call has driven for 30 min ----------
# Pids sit above pid_max (selftest below), so even a non-dry baseline tick cannot signal a real
# process (FLEET §5.6). The CPU lives in the --type=gpu-process grandchild, as in the 09-26 leak;
# the rule must sum the tree onto the browser root. Actions logs are fixtures, never the real one.
B=$(( $(cat /proc/sys/kernel/pid_max) + 100 ))
if [ -e "/proc/$B" ] || [ -e "/proc/$((B + 12))" ]; then
  echo "FAIL selftest: rule6 fixture pids exist on this box"; bad=$((bad+1))
else
  echo "PASS selftest: rule6 fixture pids cannot exist, baseline ticks are safe"
fi
UDD="--user-data-dir=/srv/x/agents/browser/profile-default"
tick6() {  # tick6 <epoch> <gpu_cpu_seconds> <actions_file> [--dry-run]
  local at="$1" cpu="$2" actions="$3"; shift 3
  mkproc "$B" chrome 90000 5 5000 /opt/google/chrome/chrome --headless "$UDD" --remote-debugging-pipe
  mkproc "$((B + 1))" chrome 90000 1 500 /opt/google/chrome/chrome --type=zygote --headless "$UDD"
  mkproc "$((B + 2))" chrome 90000 "$cpu" 500 /opt/google/chrome/chrome --type=gpu-process --headless "$UDD"
  setppid "$((B + 1))" "$B"; setppid "$((B + 2))" "$((B + 1))"
  # a second, cool browser: its tree stays at 0% of a core
  mkproc "$((B + 10))" chrome 90000 5 5000 /opt/google/chrome/chrome --headless --user-data-dir=/srv/x/agents/browser/profile-clean
  mkproc "$((B + 12))" chrome 90000 7 500 /opt/google/chrome/chrome --type=gpu-process --headless
  setppid "$((B + 12))" "$((B + 10))"
  sync_uptime "$at"
  AGENT_SCRATCH_GLOBS="$DEFAULT_GLOBS" SENTINEL_RUNAWAY_NOW="$NOW" SENTINEL_RUNAWAY_ACTIONS="$actions" \
  SENTINEL_STATE_DIR="$WORK/state" SENTINEL_RUNAWAY_PROC="$PROC" SENTINEL_RUNAWAY_TMPROOT="$TMP" \
    "$SCRIPT" "$@" >>"$WORK/state/sentinel.log"
}
T6=$(date +%s)   # the rule-6 clock: the dry tick runs at T6, actions-log ages count back from it
pwline() { printf '{"ts": "%s", "session": "abcd1234", "cwd": "/x", "tool": "%s", "op": "x", "summary": "{}"}\n' "$(date -d "@$(( T6 - $1 ))" +%Y-%m-%dT%H:%M:%S%z)" "$2"; }
run6() {  # run6 <actions_file>: three ticks 15 min apart, the gpu process burns CPU_STEP cpu-s per tick; the third is dry
  PROC="$WORK/proc6x-$RANDOM"; TMP="$WORK/tmp6x"; mkdir -p "$PROC" "$TMP"
  BOOT=$(( T6 - UPTIME ))
  rm -rf "$WORK/state"; mkdir -p "$WORK/state"
  tick6 $(( T6 - 1800 )) 10 "$1" >/dev/null
  tick6 $(( T6 - 900 )) $(( 10 + CPU_STEP )) "$1" >/dev/null
  tick6 "$T6" $(( 10 + 2 * CPU_STEP )) "$1" --dry-run
}
{ pwline 7200 mcp__playwright__browser_navigate; pwline 60 Bash; } >"$WORK/actions-idle.jsonl"
run6 "$WORK/actions-idle.jsonl"
check        "rule6: idle hot browser tree closed at its root" "would kill pid $B (rule6: Chrome tree at"
check        "rule6: kill names the idle time and the profile"  "no Playwright call for 120 min): chrome $UDD"
check_absent "rule6: gpu child not killed on its own"           "would kill pid $((B + 2))"
check_absent "rule6: cool browser tree spared"                  "would kill pid $((B + 10))"

{ pwline 7200 mcp__playwright__browser_navigate; pwline 300 mcp__playwright__browser_snapshot; pwline 60 Bash; } >"$WORK/actions-driven.jsonl"
run6 "$WORK/actions-driven.jsonl"
check_absent "rule6: hot browser driven 5 min ago spared"       "would kill pid $B"

pwline 60 Bash >"$WORK/actions-none.jsonl"
run6 "$WORK/actions-none.jsonl"
check        "rule6: no Playwright call in the log counts as idle" "would kill pid $B (rule6: Chrome tree at"

PROC="$WORK/proc6y"; TMP="$WORK/tmp6y"; mkdir -p "$PROC" "$TMP"
BOOT=$(( T6 - UPTIME ))
rm -rf "$WORK/state"; mkdir -p "$WORK/state"
tick6 $(( T6 - 900 )) 10 "$WORK/actions-idle.jsonl" >/dev/null
tick6 "$T6" $(( 10 + CPU_STEP )) "$WORK/actions-idle.jsonl" --dry-run
check_absent "rule6: one hot run is not enough"                 "would kill pid $B"

# ---------- Clean box: nothing to report ----------
PROC="$WORK/proc6"; TMP="$WORK/tmp6"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
mkproc 601 sshd 999999 50 3000 /usr/sbin/sshd -D
mkproc 602 bash 10 1 500 bash -c "echo hi"
run
if [ -s "$WORK/state/sentinel.log" ] && grep -q "runaway would" "$WORK/state/sentinel.log"; then
  echo "FAIL clean box: dry-run reported something"; bad=$((bad+1))
else
  echo "PASS clean box: dry-run lists nothing"
fi

echo
if [ "$bad" -eq 0 ]; then echo "all fixtures pass"; else echo "$bad FAILURES"; fi
exit $([ "$bad" -eq 0 ] && echo 0 || echo 1)
