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
# Keep the fake boot epoch fixed across ticks (real /proc/uptime tracks wall clock;
# a static uptime value would make a process's computed start epoch drift with real time).
sync_uptime() { echo "$(( $(date +%s) - BOOT )).00 0.00" >"$PROC/uptime"; }
setcgroup() { echo "0::/user.slice/dark-eye.service" >"$PROC/$1/cgroup"; }
setcwd() { ln -sf "$2" "$PROC/$1/cwd"; }
setfd() { ln -sf "$3" "$PROC/$1/fd/$2"; }

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

# Fixture globs, never the machine's own config (FLEET §5.6). $GLOBS overrides per section.
DEFAULT_GLOBS='/tmp/claude-1000/*/*/scratchpad'
GLOBS=""
run() {
  rm -rf "$WORK/state"; mkdir -p "$WORK/state"
  sync_uptime
  AGENT_SCRATCH_GLOBS="${GLOBS:-$DEFAULT_GLOBS}" \
  SENTINEL_STATE_DIR="$WORK/state" SENTINEL_RUNAWAY_PROC="$PROC" SENTINEL_RUNAWAY_TMPROOT="$TMP" \
    "$SCRIPT" --dry-run
}

# ---------- Rule 1: shell loop under a scratchpad, > 60 min ----------
PROC="$WORK/proc1"; TMP="$WORK/tmp1"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
mkproc 101 bash 3700 5 2000 bash -c "cd /tmp/claude-1000/-home-x/uuid1/scratchpad/ef && sleep 999999"
mkproc 102 bash 1800 5 2000 bash -c "cd /tmp/claude-1000/-home-x/uuid1/scratchpad/ef && sleep 999999"
mkproc 103 bash 999999 5 2000 bash -c "make -C /srv/x/project"
run
check      "rule1: old scratchpad shell loop killed"     "would kill pid 101 (rule1"
check_absent "rule1: young scratchpad shell loop spared" "would kill pid 102"
check_absent "rule1: unrelated old bash spared"           "would kill pid 103"

# ---------- Rule 2: capture with stdout a pipe with no reader, or a deleted file ----------
PROC="$WORK/proc2"; TMP="$WORK/tmp2"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
mkproc 201 tail 2000 1 500 tail -f /var/log/syslog;            setfd 201 1 'pipe:[9001]'
mkproc 202 tail 2000 1 500 tail -f /var/log/syslog;            setfd 202 1 'pipe:[9002]'
mkproc 203 cat  2000 1 500 cat;                                setfd 203 3 'pipe:[9002]'
mkproc 204 journalctl 2000 1 500 journalctl --user -u dark-eye-ptt -f
setfd 204 1 "$TMP/gone-$$"
mkproc 205 tail 1000 1 500 tail -f /var/log/syslog;            setfd 205 1 'pipe:[9005]'
run
check        "rule2: unread pipe killed"            "would kill pid 201 (rule2"
check_absent "rule2: pipe with a reader spared"     "would kill pid 202"
check_absent "rule2: reader itself untouched"       "would kill pid 203"
check        "rule2: capture into a deleted file killed" "would kill pid 204 (rule2"
check_absent "rule2: young capture spared"          "would kill pid 205"

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

# ---------- Rule 4: portal helper hot (CPU strikes) or fat (RSS), restart not kill ----------
PROC="$WORK/proc4"; TMP="$WORK/tmp4"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
mkproc 401 xdg-desktop-portal-gtk 2000 5 100000     # 400MB RSS, fat
mkproc 402 xdg-desktop-portal-gnome 2000 5 500      # small, quiet
mkproc 404 xdg-desktop-por 2000 5 100000 /usr/libexec/xdg-desktop-portal-gnome  # kernel-truncated comm, real bug case
run
check        "rule4: fat portal helper restarted"   "would restart xdg-desktop-portal-gtk.service (pid 401"
check_absent "rule4: quiet small helper spared"     "(pid 402"
check        "rule4: truncated comm resolved via argv[0]" "would restart xdg-desktop-portal-gnome.service (pid 404"

# CPU-strike path needs a real (non-dry) baseline tick so the next tick has state to compare to.
# The script scores pct = 100 * delta_cpu / delta_wall, so a fixed +9 cpu-s per tick only stayed
# over the 90% line while the ticks were under 10 s apart — the test failed intermittently on a
# loaded box. Each tick now adds CPU_STEP cpu-seconds, which keeps pct >= 90 for any gap under
# CPU_STEP/0.9 seconds (~30 h), so wall-clock jitter cannot reach the threshold.
CPU_STEP=100000
tick4b() {  # tick4b <cpu_seconds> [--dry-run]
  local cpu="$1"; shift
  mkproc 403 gsd-color 2000 "$cpu" 500
  sync_uptime
  SENTINEL_STATE_DIR="$WORK/state" SENTINEL_RUNAWAY_PROC="$PROC" SENTINEL_RUNAWAY_TMPROOT="$TMP" \
    "$SCRIPT" "$@"
}
PROC="$WORK/proc4b"; TMP="$WORK/tmp4b"; mkdir -p "$PROC" "$TMP"
BOOT=$(( $(date +%s) - UPTIME )); sync_uptime
rm -rf "$WORK/state"; mkdir -p "$WORK/state"
tick4b 10 >/dev/null                                  # tick 1: baseline, no previous sample
sleep 1                                               # the script reads whole seconds: force dt >= 1
tick4b $(( 10 + CPU_STEP )) >/dev/null                # tick 2: strike 1, persisted
sleep 1
tick4b $(( 10 + 2 * CPU_STEP )) --dry-run             # tick 3: strike 2, should trigger
check "rule4: hot helper restarted after strikes" "would restart gsd-color.service (pid 403"

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
mkproc 701 bash 3700 5 2000 bash -c "cd $TMP/agentwork-9/sess-live/scratch && sleep 999999"
run
check        "glob2 rule1: shell loop under the second glob killed"  "would kill pid 701 (rule1"
check        "glob2 rule5: dead dir under the second glob removed"   "would rm -rf $TMP/agentwork-9/sess-dead/scratch"
check_absent "glob2 rule5: live dir under the second glob spared"    "would rm -rf $TMP/agentwork-9/sess-live/scratch"
check_absent "glob2 rule5: dir matching no glob spared"              "would rm -rf $TMP/elsewhere/sess-dead/scratch"
check        "glob2: the default glob still applies"                 "would rm -rf $TMP/claude-1000/-home-x/uuid-dead/scratchpad"
GLOBS=""

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
