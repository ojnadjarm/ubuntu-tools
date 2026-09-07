#!/usr/bin/env bash
# fleetlib.sh — shared library for the fleet CLIs (agent-*, agents-*, notify-owner,
# maintenance-run). Source it (`. "$HOME/agents/bin/fleetlib.sh"`), never execute it.
# Sourcing loads the harness environment once; PATH and locking are opt-in calls, because
# maintenance-run and sentinel-check deliberately keep the PATH they inherited.
#
# API — one line per function:
#   fleet_path              export the hermetic fleet PATH (a systemd user shell inherits almost none)
#   fleet_lock <file> <fd>  exclusive non-blocking flock on <file> through <fd>; 1 when another run holds it
# shellcheck source=/dev/null
[ -n "${HARNESS_ENV_LOADED:-}" ] || . "$HOME/agents/bin/env.sh"

fleet_path() {
  export PATH="$HOME/.local/bin:$HARNESS_HOME/bin:/usr/local/bin:/usr/bin:/bin"
}

fleet_lock() {
  case "${2:-}" in ''|*[!0-9]*) echo "fleet_lock: <fd> must be a number" >&2; return 2 ;; esac
  eval "exec $2>\"\$1\"" || return 2
  flock -n "$2"
}
