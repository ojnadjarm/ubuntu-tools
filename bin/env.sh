# Harness environment: config values first, then the session variables desktop scripts need.
HARNESS_CONFIG="${HARNESS_CONFIG:-$HOME/.config/pc-harness/config.env}"
# Variables already exported by the caller win over config.env (one-off overrides on the command line).
_harness_pre="$(export -p | grep -E '(HARNESS_|NTFY_|ORCHESTRATOR_|AGENT_SCRATCH_GLOBS|MOODLE_ENVS_DIR)' || true)"
# shellcheck source=/dev/null
if [ -r "$HARNESS_CONFIG" ]; then . "$HARNESS_CONFIG"
elif [ -r "$HOME/agents/config.env" ]; then . "$HOME/agents/config.env"; fi
eval "$_harness_pre"; unset _harness_pre

: "${HARNESS_HOME:=$HOME/agents}"
: "${HARNESS_UID:=${UID:-$(id -u)}}"
: "${HARNESS_HOST:=$(hostname)}"
: "${HARNESS_TAILNET_FQDN:=}"
: "${HARNESS_BRAND:=}"
: "${HARNESS_LAN_IP:=}"
: "${HARNESS_BUDS_MAC:=}"
: "${HARNESS_AGENT:=}"
: "${HARNESS_AGENT_CMD:=}"
: "${NTFY_ENV_FILE:=$HARNESS_HOME/secrets/ntfy.env}"
: "${ORCHESTRATOR_TMUX_SESSION:=claude}"
: "${ORCHESTRATOR_UNIT:=claude-orchestrator.service}"
: "${AGENT_SCRATCH_GLOBS:=/tmp/claude-$HARNESS_UID/*/*/scratchpad}"
: "${MOODLE_ENVS_DIR:=$HOME/moodle-envs}"
: "${HARNESS_CONTEXT_DIR:=$HOME/.claude}"
HARNESS_ENV_LOADED=1
export HARNESS_HOME HARNESS_UID HARNESS_HOST HARNESS_BRAND HARNESS_TAILNET_FQDN HARNESS_LAN_IP HARNESS_BUDS_MAC \
       HARNESS_AGENT HARNESS_AGENT_CMD NTFY_ENV_FILE ORCHESTRATOR_TMUX_SESSION \
       ORCHESTRATOR_UNIT AGENT_SCRATCH_GLOBS MOODLE_ENVS_DIR HARNESS_CONTEXT_DIR HARNESS_ENV_LOADED

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$HARNESS_UID}" WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$HARNESS_UID/bus" YDOTOOL_SOCKET=/tmp/.ydotool_socket
PC_FOCUS_FILE="${XDG_RUNTIME_DIR:-/tmp}/pc-focus-window"
# The bin/ this file lives in, so a sourcing script needs no dirname/readlink of its own.
# Parameter expansion, not dirname: every script on the box sources this file (PT15, exec budget).
PC_BIN="${BASH_SOURCE[0]%/*}"; [ "$PC_BIN" = "${BASH_SOURCE[0]}" ] && PC_BIN=.

# pc_screen — "W H" of the current screen, empty when unknown.
pc_screen() { xrandr 2>/dev/null | sed -n 's/^Screen 0:.*current \([0-9]*\) x \([0-9]*\).*/\1 \2/p' | head -1; }

# pc_xy X Y — exit 2 unless both are integers inside the screen; 0,0 is the overview hot corner.
pc_xy() {
  local a s w h
  for a in "${1:-}" "${2:-}"; do
    case "$a" in ''|*[!0-9]*) echo "pc: X Y must be integers on screen, got '${1:-}' '${2:-}'" >&2; exit 2;; esac
  done
  [ "$1" = 0 ] && [ "$2" = 0 ] && { echo "pc: 0,0 is the overview hot corner, use 1,1" >&2; exit 2; }
  s="$(pc_screen)"
  [ -n "$s" ] || return 0
  w="${s% *}"; h="${s#* }"
  [ "$1" -lt "$w" ] && [ "$2" -lt "$h" ] || { echo "pc: $1,$2 is outside the screen (${w}x${h})" >&2; exit 2; }
}

# pc_moveto X Y — check the point, move the pointer there and let the compositor settle.
pc_moveto() {
  pc_xy "$1" "$2"
  ydotool mousemove --absolute -x "$1" -y "$2" || exit 1
  sleep 0.15
}

# pc_focus_guard <verb> — exit 2 unless the window `pc win focus` left focused still holds it
# and no in-window modal is up; `--force` skips both (KB/quirks.md, AT-SPI).
pc_focus_guard() {
  local msg m
  msg="$("$PC_BIN/pc-win" verify 2>&1)" || {
    echo "pc $1: ${msg:-no focused window} — 'pc win focus <sel>' first, or pass --force" >&2
    exit 2
  }
  m="$(python3 "$PC_BIN/a11y_tree.py" --modal-check 2>/dev/null)" && {
    echo "pc $1: modal $m is up - answer it with 'pc a11y-click \"<button>\"', or pass --force" >&2
    exit 2
  }
}
