#!/usr/bin/env bash
# PT01: pclib.sh's fixture roots (PC_SYS/PC_PROC/PC_FIXTURE), pc_cmd, pc_opt, pc_usage,
# pc_json and cached()'s TTL. No machine state is read or written.
set -uo pipefail
LIB="$HOME/agents/bin/pclib.sh"
FIX="$HOME/agents/bin/tests/fixtures/pclib"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
# run <script-body> — sources pclib in a clean subshell with $WORK as the runtime dir.
run() { XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/changes.jsonl" bash -c ". '$LIB'; $1" _ "$@"; }

# 1. defaults
is 'PC_SYS defaults to /sys'   "$(run 'echo $PC_SYS')"  /sys
is 'PC_PROC defaults to /proc' "$(run 'echo $PC_PROC')" /proc

# 2. PC_FIXTURE redirects both roots and makes the recorded tree readable.
is 'PC_FIXTURE sets PC_SYS'  "$(PC_FIXTURE=$FIX run 'echo $PC_SYS')"  "$FIX/sys"
is 'PC_FIXTURE sets PC_PROC' "$(PC_FIXTURE=$FIX run 'echo $PC_PROC')" "$FIX/proc"
is 'fixture sysfs reads back' "$(PC_FIXTURE=$FIX run 'cat $PC_SYS/class/power_supply/BAT0/capacity')" 77

# 3. pc_cmd prefers the recorded binary under the fixture, the real one otherwise.
is 'pc_cmd uses the recorded binary' \
  "$(PC_FIXTURE=$FIX run 'pc_cmd sensors -j' | jq -r '."coretemp-isa-0000"."Package id 0".temp1_input')" 42.0
is 'pc_cmd falls through to the real binary' "$(run 'pc_cmd echo hello')" hello
is 'pc_cmd falls through when the fixture has no such binary' \
  "$(PC_FIXTURE=$FIX run 'pc_cmd echo hello')" hello

# 4. pc_opt / pc_usage / pc_json
is 'pc_opt parses the flags' \
  "$(run 'pc_opt --json --apply --seconds 3 alpha --fresh beta; echo "$JSON$APPLY$SECONDS_$FRESH ${PC_ARGS[*]}"')" \
  '1131 alpha beta'
is 'pc_opt accepts --seconds=N' "$(run 'pc_opt --seconds=7; echo $SECONDS_')" 7
run 'pc_opt --nope' >/dev/null 2>&1; is 'pc_opt exits 2 on an unknown option' "$?" 2
is 'pc_usage prints and exits 0 on -h' "$(run 'pc_usage "usage: x" --json -h; echo NOTREACHED')" 'usage: x'
is 'pc_json emits objects' "$(run 'pc_json "{a:\$v}" -c --arg v one')" '{"a":"one"}'

# 5. cached: first call runs the command, second reuses it, TTL 0 and FRESH=1 bypass.
mk='c() { echo run-$(cat '"$WORK"'/n); }; echo 1 >'"$WORK"'/n'
is 'cached runs the command once'  "$(run "$mk; cached t 60 c; echo 2 >$WORK/n; cached t 60 c")" $'run-1\nrun-1'
is 'cached re-runs past the TTL'   "$(run "$mk; cached u 60 c; echo 2 >$WORK/n; cached u 0 c")"  $'run-1\nrun-2'
is 'FRESH=1 bypasses the cache'    "$(run "$mk; cached v 60 c; echo 2 >$WORK/n; FRESH=1; cached v 60 c")" $'run-1\nrun-2'
is 'cached writes into XDG_RUNTIME_DIR' "$(run 'echo $CACHE')" "$WORK/pc-status"

# 6. the ledger path is overridable and defaults under ~/agents/log.
is 'PC_LEDGER is overridable' "$(run 'echo $PC_LEDGER')" "$WORK/changes.jsonl"
is 'PC_LEDGER default' "$(XDG_RUNTIME_DIR=$WORK bash -c ". '$LIB'; echo \$PC_LEDGER")" "$HOME/agents/log/changes.jsonl"

# 7. pc_id is base36, monotonic and unique.
a=$(run 'pc_id'); b=$(run 'pc_id')
case "$a" in *[!0-9a-z]*|'') nok 'pc_id is base36' "$a";; *) ok 'pc_id is base36';; esac
[ "$a" != "$b" ] && [[ "$a" < "$b" ]] && ok 'pc_id increases' || nok 'pc_id increases' "$a >= $b"

# 8. PT15: pc_opt's PC_EXTRA_FLAGS passthrough — declared flags are collected, not stripped.
is 'PC_EXTRA_FLAGS collects a bare flag' \
  "$(run 'PC_EXTRA_FLAGS=(--deep); pc_opt --json --deep a; echo "$JSON|${PC_EXTRA[*]}|${PC_ARGS[*]}"')" \
  '1|--deep|a'
is 'PC_EXTRA_FLAGS collects a flag with its value' \
  "$(run 'PC_EXTRA_FLAGS=(--level:); pc_opt --level err a; echo "${PC_EXTRA[*]}|${PC_ARGS[*]}"')" \
  '--level err|a'
is 'PC_EXTRA_FLAGS accepts --flag=value' \
  "$(run 'PC_EXTRA_FLAGS=(--level:); pc_opt --level=err; echo "${PC_EXTRA[*]}"')" '--level=err'
run 'PC_EXTRA_FLAGS=(--deep); pc_opt --nope' >/dev/null 2>&1
is 'an undeclared option still exits 2' "$?" 2

# 9. PT15: the guard covers bare unit names and the D-Bus cases centrally.
denies() { run "pc_guard $1" >/dev/null 2>&1; [ "$?" = 3 ] && ok "guard denies: $1" || nok "guard denies: $1" "exit $?"; }
allows() { run "pc_guard $1" >/dev/null 2>&1; [ "$?" = 0 ] && ok "guard allows: $1" || nok "guard allows: $1" "exit $?"; }
for u in dark-eye ssh ufw tailscaled claude-orchestrator dark-eye-ptt ssh.socket; do
  denies "systemctl --user restart -- $u"
done
denies 'systemctl restart dark-eye.service'
allows 'systemctl --user restart -- pt13-test'
allows 'systemctl --user restart -- agent@hello.service'
is 'PC_ORCHESTRATOR=1 lets dark-eye through' \
  "$(PC_ORCHESTRATOR=1 run 'pc_guard systemctl restart dark-eye; echo allowed')" allowed
is 'pc_unit_why strips the type suffix' "$(run 'pc_unit_why ufw.service')" 'a second access path'
is 'pc_unit_why is empty for an allowed unit' "$(run 'pc_unit_why moodle-keep-weekly.timer')" ''
run 'pc_guard_unit tailscaled' >/dev/null 2>&1; is 'pc_guard_unit exits 3' "$?" 3
denies 'call org.freedesktop.login1 /org/freedesktop/login1 Manager.HybridSleep true'
denies 'call org.freedesktop.systemd1 /org/freedesktop/systemd1 StopUnit ssh.service replace'
denies 'call org.freedesktop.systemd1 /org/freedesktop/systemd1 RestartUnit tailscaled.service replace'
denies 'call org.gnome.Shell /org/gnome/Shell org.gnome.Shell.Eval 1+1'
denies 'call org.gnome.SessionManager /org/gnome/SessionManager org.gnome.SessionManager.Logout 0'
denies 'call org.gnome.ScreenSaver /org/gnome/ScreenSaver SetActive true'
denies 'call org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig ApplyMonitorsConfig'
allows 'call org.gnome.ScreenSaver /org/gnome/ScreenSaver GetActive'

[ $bad = 0 ] && echo 'PASS pclib' || echo 'FAIL pclib'
exit $bad
