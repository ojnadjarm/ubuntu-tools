#!/usr/bin/env bash
# The orchestrator pane health signal (pc status orch=) and sentinel-check's repair of it.
# Fixture-only (FLEET §5.6): a private tmux server (TMUX_TMPDIR) hosts sessions named
# claude-fx-<pid>; systemctl, notify-owner and every other side effect are PATH shims that only
# record their call; the real `claude` session, claude-orchestrator.service and ntfy are
# unreachable by construction, proven by the selftest before any run.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTINEL="$(dirname "$here")/sentinel-check"
PCS="$(dirname "$here")/pc-status"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
has() { case "$2" in *"$3"*) ok "$1";; *) nok "$1" "'$3' not in: $2";; esac; }
lacks() { case "$2" in *"$3"*) nok "$1" "'$3' found in: $2";; *) ok "$1";; esac; }

WORK=$(mktemp -d)
BIN="$WORK/agents/bin"; ST="$WORK/agents/sentinel/state"; CALLS="$WORK/calls.log"
FXS="claude-fx-$$"; FXU="claude-fx-$$.service"
mkdir -p "$BIN" "$ST" "$WORK/tmux" "$WORK/xdg/pc-status" "$WORK/fxbin"
REAL_TMUX=$(command -v tmux)
fx() { env -u TMUX TMUX_TMPDIR="$WORK/tmux" HOME="$WORK" HARNESS_HOME="$WORK/agents" \
       XDG_RUNTIME_DIR="$WORK/xdg" ORCHESTRATOR_TMUX_SESSION="$FXS" ORCHESTRATOR_UNIT="$FXU" \
       PATH="$BIN:$PATH" CALLS="$CALLS" SENTINEL_STATUS_CMD="$BIN/status-real" SENTINEL_ORCH_WAIT=1 FX_UNIT_ENABLED="${FX_UNIT_ENABLED:-enabled}" "$@"; }
printf 'set -g remain-on-exit on\n' >"$WORK/tmux.conf"
ftmux() { fx "$REAL_TMUX" -f "$WORK/tmux.conf" "$@"; }
cleanup() { ftmux kill-server 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

# --- shims: record, change nothing -------------------------------------------
for c in sudo tailscale docker notify-owner agent-run sentinel-runaway pw-metadata; do
  printf '#!/bin/sh\necho "%s $*" >>"$CALLS"\nexit 0\n' "$c" >"$BIN/$c"
done
cat >"$BIN/systemctl" <<'S'
#!/bin/sh
echo "systemctl $*" >>"$CALLS"
case "$*" in *is-active*) for a in "$@"; do case "$a" in -*|is-active) ;; *) echo active;; esac; done;;
            *is-enabled*) echo "$FX_UNIT_ENABLED";; esac
exit 0
S
printf '#!/bin/sh\nexec "%s" --json\n' "$PCS" >"$BIN/status-real"   # --fresh dropped: orch= is never cached
chmod +x "$BIN"/*
# A healthy probe cache (copied, timestamps renewed) so only the orchestrator can fail and no
# real probe (screenshot, smartctl) runs.
real_cache="${XDG_RUNTIME_DIR:-/run/user/$UID}/pc-status"
for f in "$real_cache"/*; do
  [ -r "$f" ] || continue
  { date +%s; tail -n +2 "$f"; } >"$WORK/xdg/pc-status/$(basename "$f")"
done
printf '#!/bin/sh\nsleep 300\n' >"$WORK/fxbin/claude"   # comm=claude, as the real pane shows
cat >"$WORK/fxbin/dialog" <<S
#!/bin/sh
cat <<'T'
 Quick safety check: Is this a project you created or one you trust? (Like your
 own code, a well-known open source project, or work from your team).

 ❯ No, exit
   Yes, I trust this folder

 Enter to confirm · Esc to cancel
T
read -r _answer
clear; echo "fake claude serving"; exec "$WORK/fxbin/claude" 300
S
chmod +x "$WORK/fxbin"/*
fxsession() { ftmux kill-session -t "$FXS" 2>/dev/null; ftmux new-session -d -s "$FXS" -x 90 -y 30 "$@"; }
brief() { fx "$PCS" --brief; }
field() { local v=${2#*"$1="}; printf '%s\n' "${v%% *}"; }

# --- 0. selftest: the real names are unreachable ------------------------------
ftmux has-session -t claude 2>/dev/null \
  && nok "selftest: fixture tmux server cannot see session 'claude'" "it can" \
  || ok "selftest: fixture tmux server cannot see session 'claude'"
[ "$(fx bash -c 'command -v systemctl')" = "$BIN/systemctl" ] && ok "selftest: systemctl is the shim" || nok "selftest: systemctl shim" "$(fx bash -c 'command -v systemctl')"
[ "$(fx bash -c 'command -v notify-owner')" = "$BIN/notify-owner" ] && ok "selftest: notify-owner is the shim" || nok "selftest: notify-owner shim" "$(fx bash -c 'command -v notify-owner')"
case "$FXS" in claude) nok "selftest: fixture session name" "$FXS";; *) ok "selftest: fixture session is $FXS";; esac
ntfy_log="$HOME/agents/log/notify.log"; ntfy_before=$(wc -c <"$ntfy_log" 2>/dev/null || echo 0)

# --- 1. orch= tells the pane states apart --------------------------------------
b=$(brief); [ "$(field tmux "$b")" = down ] && [ "$(field orch "$b")" = dead ] \
  && ok "no session: tmux=down orch=dead" || nok "no session" "$b"
fxsession true; sleep 0.5
b=$(brief); [ "$(field orch "$b")" = dead ] && ok "exited pane: orch=dead" || nok "exited pane" "$b"
fxsession sh; sleep 0.5
b=$(brief); [ "$(field tmux "$b")" = alive ] && [ "$(field orch "$b")" = shell ] \
  && ok "bare shell: tmux=alive orch=shell" || nok "bare shell" "$b"
fxsession "$WORK/fxbin/dialog"; sleep 0.5
b=$(brief); [ "$(field tmux "$b")" = alive ] && [ "$(field orch "$b")" = trust-prompt ] \
  && ok "trust dialog: tmux=alive orch=trust-prompt (the 2026-09-13 gap)" || nok "trust dialog" "$b"
has "trust dialog fails --brief" "$(field FAIL "$b")" orchestrator
fx "$PCS" --check >/dev/null 2>&1 && nok "--check exits 1 on trust-prompt" "exit 0" || ok "--check exits 1 on trust-prompt"

# --- 2. sentinel-check answers the dialog, no push ---------------------------
: >"$CALLS"; fx "$SENTINEL"; rc=$?
slog=$(cat "$ST/sentinel.log" 2>/dev/null)
has "sentinel logs the answer" "$slog" "orchestrator trust-prompt: answered (Down Enter)"
b=$(brief); [ "$(field orch "$b")" = ok ] && ok "pane serving after the answer (orch=ok)" || nok "pane after answer" "$b"
lacks "no push when the answer worked" "$(cat "$CALLS")" notify-owner
[ -e "$ST/orch-repaired" ] && ok "episode marker set" || nok "episode marker" "missing"
fx "$SENTINEL"; [ -e "$ST/orch-repaired" ] && nok "healthy tick clears the marker" "still there" || ok "healthy tick clears the marker"

# --- 3. shell: one restart per episode, then one push -------------------------
fxsession sh; sleep 0.5; : >"$CALLS"; : >"$ST/sentinel.log"
fx "$SENTINEL"; fx "$SENTINEL"
calls=$(cat "$CALLS")
n=$(grep -c "systemctl --user restart $FXU" <<<"$calls")
[ "$n" = 1 ] && ok "shell: unit restarted exactly once over two ticks" || nok "shell: restarts" "$n: $calls"
n=$(grep -c '^notify-owner' <<<"$calls")
[ "$n" = 1 ] && ok "shell: owner pushed exactly once" || nok "shell: pushes" "$n: $calls"
has "push names the state" "$calls" "orchestrator pane shell after one repair"
lacks "no Claude escalation for the orchestrator" "$calls" agent-run
has "sentinel logs the restart" "$(cat "$ST/sentinel.log")" "orchestrator shell: restarted $FXU"

# --- 4. unit disabled (owner runs the orchestrator himself): orch=off is healthy ---------
fxsession sh; sleep 0.5; : >"$CALLS"; : >"$ST/sentinel.log"; rm -f "$ST/orch-repaired" "$ST/orch-notified"
b=$(FX_UNIT_ENABLED=disabled brief); [ "$(field orch "$b")" = off ] && ok "unit disabled: orch=off" || nok "unit disabled" "$b"
lacks "orch=off is not a FAIL" "$(field FAIL "$b")" orchestrator
FX_UNIT_ENABLED=disabled fx "$PCS" --check >/dev/null 2>&1 && ok "--check exits 0 on orch=off" || nok "--check on orch=off" "exit 1"
FX_UNIT_ENABLED=disabled fx "$SENTINEL"
lacks "sentinel: no restart for orch=off" "$(cat "$CALLS")" "systemctl --user restart"
lacks "sentinel: no push for orch=off" "$(cat "$CALLS")" notify-owner

# --- 5. nothing real was touched ---------------------------------------------
[ "$(wc -c <"$ntfy_log" 2>/dev/null || echo 0)" = "$ntfy_before" ] && ok "real notify.log unchanged" || nok "real notify.log" "grew"
"$REAL_TMUX" has-session -t "$FXS" 2>/dev/null && nok "fixture session never on the real server" "it is" || ok "fixture session never on the real server"

exit $bad
