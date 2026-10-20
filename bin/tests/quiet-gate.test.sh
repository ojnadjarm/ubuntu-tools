#!/usr/bin/env bash
# quiet-gate on a fake loadavg file and nproc: the per-CPU limits make the same decisions as the old absolute ones at 16 threads (T595).
set -uo pipefail
B="$HOME/agents/bin"; Q="$B/quiet-gate"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export QUIET_LOADAVG="$W/loadavg" QUIET_NPROC=16 QUIET_EVERY=1 WAIT_FOR_DIR="$W/waits"
. "$HOME/agents/bin/tests/lib/assert.sh"
load() { echo "$1 1.00 1.00 1/100 1" >"$QUIET_LOADAVG"; }
rc() { "$@" >/dev/null 2>&1; echo $?; }

# Old rules: awk `$1 < 8` (game-ci perf, godot-perfgate, cpp-ci, gamedev-perf), awk `$1 < 16` (game-ci export),
# integer part < 16 (motion-video build.sh, mv.test.sh); quiet = 0, busy = 3.
old_awk() { awk -v m="$1" '{exit !($1 < m)}' "$QUIET_LOADAVG" && echo 0 || echo 3; }
old_int() { [ "$(cut -d' ' -f1 "$QUIET_LOADAVG" | cut -d. -f1)" -lt 16 ] && echo 0 || echo 3; }
for l in 0.00 3.99 4.00 7.99 8.00 15.99 16.00 40.50; do
  load "$l"
  eq "load $l: 0.5/cpu = old < 8" "$(old_awk 8)" "$(rc "$Q" --max-per-cpu 0.5)"
  eq "load $l: 1/cpu = old < 16" "$(old_awk 16)" "$(rc "$Q" --max-per-cpu 1)"
  eq "load $l: 1/cpu = old int < 16" "$(old_int)" "$(rc "$Q" --max-per-cpu 1)"
done

load 5.00
eq "default 0.25/cpu: 5 >= 4 busy" 3 "$(rc "$Q")"
eq "nproc scales: 0.25 × 32 = 8, quiet" 0 "$(QUIET_NPROC=32 rc "$Q")"
eq "--max-load1 wins over --max-per-cpu" 3 "$(rc "$Q" --max-per-cpu 1 --max-load1 2)"
eq "empty --max-load1 falls back to per-CPU" 0 "$(rc "$Q" --max-per-cpu 1 --max-load1 '')"
eq "--json" '{"quiet":false,"load1":5.00,"max":4,"nproc":16,"waited_s":0}' "$("$Q" --json)"
eq "busy line" "quiet-gate: busy, load1 5.00 >= 4" "$("$Q")"
eq "bad flag: rc 2" 2 "$(rc "$Q" --bogus)"
# shellcheck source=/dev/null
eq "sourced parser" 5.00 "$(. "$Q"; qg_load1)"

eq "--wait: busy past the wait, rc 3" 3 "$(rc "$Q" --wait 2)"
( sleep 1; load 1.00 ) &
eq "--wait: load drops, rc 0" 0 "$(rc "$Q" --wait 20)"
wait

# --gpu on /proc-shaped fixtures: snapshots a/ and b/ are 1 s apart; client 7 shares two fds, gnome-shell and Xwayland are the compositor (T617).
proc() {  # SNAP PID NAME PPID CLIENT NS
  mkdir -p "$W/fd/$1/$2/fdinfo"
  printf 'Name:\t%s\nPPid:\t%s\nUid:\t%s\t%s\t%s\t%s\n' "$3" "$4" "$(id -u)" "$(id -u)" "$(id -u)" "$(id -u)" >"$W/fd/$1/$2/status"
  for fd in 3 4; do printf 'drm-driver:\ti915\ndrm-client-id:\t%s\ndrm-engine-render:\t%s ns\n' "$5" "$6" >"$W/fd/$1/$2/fdinfo/$fd"; done
}
gpufix() {  # BLENDER_A BLENDER_B SHELL_B
  rm -rf "$W/fd"
  proc a 100 gnome-shell 1 1 5000000000; proc b 100 gnome-shell 1 1 "$3"
  proc a 101 Xwayland 100 2 100000000; proc b 101 Xwayland 100 2 900000000
  proc a 200 blender 150 7 "$1"; proc b 200 blender 150 7 "$2"
}
export QUIET_FDINFO="$W/fd"; load 1.00
gpufix 1000000000 1000000000 5000000000
eq "gpu idle: 0 %" '{"quiet":true,"load1":1.00,"max":4,"nproc":16,"waited_s":0,"gpu_busy_pct":0}' "$("$Q" --gpu 15 --json)"
gpufix 1000000000 1400000000 5000000000
eq "gpu busy 40 %: rc 3" 3 "$(rc "$Q" --gpu 15)"
eq "gpu busy line" "quiet-gate: busy, gpu 40% > 15%" "$("$Q" --gpu)"
eq "gpu 40 % under --gpu 50: quiet" 0 "$(rc "$Q" --gpu 50)"
# shellcheck source=/dev/null
eq "gpu: the excluded tree (parent 150) drops blender" 0 "$(. "$Q"; qg_gpu_pct 150)"
gpufix 1000000000 1000000000 5900000000
eq "gpu: compositor at 90 % excluded" 0 "$(rc "$Q" --gpu 15)"
unset QUIET_FDINFO

# A caller end to end: motion-video build.sh refuses at 1/cpu before any render.
mkdir -p "$W/proj" && cp "$HOME/agents/skills/motion-video/templates/build.sh" "$W/proj/"
load 16.00; out=$(cd "$W/proj" && PATH="$B:$PATH" ./build.sh 2>&1); r=$?
eq "build.sh busy: rc 3" 3 "$r"
eq "build.sh busy: says why" "build: load1 16.00 >= 16, render later" "$out"

exit $bad
