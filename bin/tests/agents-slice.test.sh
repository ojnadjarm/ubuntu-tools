#!/usr/bin/env bash
# T1085: tmux panes keep their server's slice (orchestrator stays in app.slice); launchers (agent-exec, run.sh, orchestrator-boot) put work in idle agents.slice.
set -uo pipefail
. "$HOME/agents/bin/tests/lib/assert.sh"
UD="$HOME/.config/systemd/user"; SPAWN="$UD/tmux-spawn-.scope.d"; BIN="$HOME/agents/bin"; SLICE="$UD/agents.slice.d/weight.conf"
CG="/sys/fs/cgroup/user.slice/user-$UID.slice/user@$UID.service"
WORK=$(mktemp -d); trap 'tmux -L "t1085-app.slice-$$" kill-server 2>/dev/null; tmux -L "t1085-agents.slice-$$" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT

spawn_ok() { ! cat "$1"/*.conf 2>/dev/null | grep -qE '^[[:space:]]*(Slice|CPUWeight)='; }
slice_ok() { grep -qx 'CPUWeight=idle' "$1"; }

# Pane cgroup of a throwaway tmux -L server started inside a transient scope in slice $1.
pane_cg() {
  local s="t1085-$1-$$"
  systemd-run --user --scope --quiet --slice="$1" --unit="$s" tmux -L "$s" new-session -d -s t 'sleep 60' || return 1
  local p; p=$(tmux -L "$s" list-panes -F '#{pane_pid}')
  timeout 5 wait-for --label t1085-pane --every 0.1 --until "grep -q tmux-spawn /proc/$p/cgroup" >/dev/null 2>&1
  cut -d: -f3 "/proc/$p/cgroup"; tmux -L "$s" kill-server
}

# 1. config: no tmux-spawn drop-in sets Slice/CPUWeight; agents.slice is idle and pulled in at boot.
spawn_ok "$SPAWN" && ok 'tmux-spawn drop-ins set no Slice=/CPUWeight=' || nok 'tmux-spawn drop-ins' "$(cat "$SPAWN"/*.conf)"
slice_ok "$SLICE" && ok 'agents.slice drop-in CPUWeight=idle' || nok 'agents.slice drop-in' "$(cat "$SLICE")"
is 'agents.slice CPUWeight loaded' "$(systemctl --user show agents.slice -p CPUWeight --value)" idle
systemctl --user show default.target -p Wants --value | grep -qw agents.slice && ok 'default.target wants agents.slice' || nok 'default.target Wants' 'no agents.slice'

# 2. a pane of a server in app.slice (the orchestrator's case) lands outside agents.slice.
cg=$(pane_cg app.slice)
case "$cg" in */app.slice/tmux-spawn-*.scope) ok "app.slice pane stays in app.slice" ;; *) nok 'app.slice pane' "$cg" ;; esac

# 3. a launcher-placed server (systemd-run --slice=agents.slice) puts its pane in agents.slice, cpu.idle=1.
cg=$(pane_cg agents.slice)
case "$cg" in */agents.slice/tmux-spawn-*.scope) ok "launcher-placed pane in agents.slice" ;; *) nok 'launcher-placed pane' "$cg" ;; esac
is 'agents.slice cpu.idle' "$(cat "$CG/agents.slice/cpu.idle")" 1

# 4. launchers: run.sh and orchestrator-boot scopes name agents.slice.
for f in "$BIN/tests/run.sh" "$BIN/tests/orchestrator-boot.test.sh"; do
  grep -qE -- 'systemd-run --user --scope (-q|--quiet) --slice=agents.slice' "$f" \
    && ok "${f##*/} scope in agents.slice" || nok "${f##*/} scope" "$(grep -n 'systemd-run --user --scope' "$f")"
done

# 5. agent-exec, run from a throwaway unit (MemoryMax=1G), puts a stub adapter in agents.slice bound to that unit.
mkdir -p "$WORK/agents/bin" "$WORK/agents/adapters/stub" "$WORK/run"; cp "$BIN/agent-exec" "$BIN/fleetlib.sh" "$BIN/env.sh" "$WORK/agents/bin/"
printf '#!/bin/sh
c=$(sed -n "s/^0:://p" /proc/self/cgroup)
echo "$c $(cat /sys/fs/cgroup$c/memory.max) $(systemctl --user show "${c##*/}" -p BindsTo --value)" >"$RAW_OUT"
' >"$WORK/agents/adapters/stub/run"
chmod +x "$WORK/agents/adapters/stub/run"; : >"$WORK/p"
systemd-run --user --wait --collect --quiet --unit="t1085-exec-$$" -p MemoryMax=1G env -u HARNESS_ENV_LOADED -u HARNESS_HOME \
  HOME="$WORK" HARNESS_AGENT=stub "$WORK/agents/bin/agent-exec" --prompt-file "$WORK/p" --cwd "$WORK/run" >/dev/null 2>&1
read -r cg mem bind <"$WORK/run/raw.json"
case "$cg" in */agents.slice/run-*.scope) ok 'agent-exec adapter in agents.slice' ;; *) nok 'agent-exec adapter cgroup' "$cg" ;; esac
is 'agent-exec keeps the caller MemoryMax' "$mem" 1073741824
is 'agent-exec scope BindsTo the caller' "$bind" "t1085-exec-$$.service"
rm -f "$WORK/run/raw.json"
timeout 30 systemd-run --user --wait --collect --quiet --unit="t1085-oneshot-$$" -p Type=oneshot env -u HARNESS_ENV_LOADED -u HARNESS_HOME \
  HOME="$WORK" HARNESS_AGENT=stub "$WORK/agents/bin/agent-exec" --prompt-file "$WORK/p" --cwd "$WORK/run" >/dev/null 2>&1
[ -s "$WORK/run/raw.json" ] && ok 'agent-exec under a oneshot caller does not deadlock' ||
  { nok 'agent-exec under a oneshot caller deadlocks' "no raw.json in 30 s"; systemctl --user stop "t1085-oneshot-$$" 2>/dev/null; }

# 6. mutation: T1052's drop-in and a weight-50 slice must fail the config checks.
mkdir "$WORK/spawn"; printf '[Scope]\nSlice=agents.slice\nCPUWeight=50\n' >"$WORK/spawn/weight.conf"
printf '[Slice]\nCPUWeight=50\n' >"$WORK/slice.conf"
spawn_ok "$WORK/spawn" && nok 'mutation: Slice= in tmux-spawn drop-in passed' || ok 'mutation red: Slice= in tmux-spawn drop-in'
slice_ok "$WORK/slice.conf" && nok 'mutation: CPUWeight=50 passed' || ok 'mutation red: CPUWeight=50 slice'

exit $bad
