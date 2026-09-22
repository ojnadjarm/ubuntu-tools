#!/usr/bin/env bash
# Fixture test for the kill switch and the agent-* argument guards (TSP-009).
# Everything runs under a throwaway $HOME/$HARNESS_HOME whose bin/ shadows systemctl,
# notify-owner and claude with recorders, so no real unit, timer or push can be reached
# (FLEET.md §5.6). A selftest proves the shims are the ones on PATH before any assertion.
# The only process killed is a `sleep` this test started itself.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINDIR="$(dirname "$here")"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/agents/bin"
mkdir -p "$BIN/guards" "$WORK/agents/alpha/state"
ln -s "$BINDIR/env.sh" "$BIN/env.sh"
ln -s "$BINDIR/fleetlib.sh" "$BIN/fleetlib.sh"
printf 'fixture agent\n' >"$WORK/agents/alpha/BRIEF.md"
: >"$WORK/config.env"
CALLS="$WORK/calls.log"; : >"$CALLS"

cat >"$BIN/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >>"$CALLS"
case "$*" in
  *list-units*agent@*.service*) echo "agent@alpha.service loaded active running agent alpha" ;;
  *list-units*) : ;;
  *is-active*agent@alpha.service*) echo active ;;
  *is-active*) echo inactive ;;
esac
exit 0
EOF
for c in notify-owner claude agents-start; do
  printf '#!/bin/sh\necho "%s $*" >>"$CALLS"\nexit 0\n' "$c" >"$BIN/$c"
done
chmod +x "$BIN"/systemctl "$BIN"/notify-owner "$BIN"/claude "$BIN"/agents-start

run() { # run <script> [args...] — the fixture environment, nothing of the real fleet
  HOME="$WORK" HARNESS_HOME="$WORK/agents" HARNESS_CONFIG="$WORK/config.env" \
  HARNESS_AGENT="" CALLS="$CALLS" PATH="$BIN:/usr/bin:/bin" bash "$BINDIR/$1" "${@:2}"
}

fail() { echo "agents-stop.test: FAIL — $1" >&2; exit 1; }

# --- selftest: the shims, not the real tools, are what the script will find ------------
probe="$WORK/probe.sh"
cat >"$probe" <<'EOF'
. "$HOME/agents/bin/fleetlib.sh"
fleet_path
command -v systemctl; command -v notify-owner; command -v claude
EOF
resolved="$(HOME="$WORK" HARNESS_HOME="$WORK/agents" HARNESS_CONFIG="$WORK/config.env" \
            PATH="/usr/bin:/bin" bash "$probe")"
for p in $resolved; do
  case "$p" in "$WORK"/*) ;; *) fail "selftest: $p is not a fixture shim — refusing to run" ;; esac
done
[ "$(printf '%s\n' "$resolved" | wc -l)" = 3 ] || fail "selftest: expected 3 shims, got: $resolved"

# --- metric: a background run recorded in state/pid is killed by agents-stop -----------
sleep 300 & victim=$!
printf '%s\n' "$victim" >"$WORK/agents/alpha/state/pid"
out="$(run agents-stop 2>&1)"; rc=$?
[ "$rc" = 0 ] || fail "agents-stop exited $rc: $out"
sleep 0.2
killed=0; kill -0 "$victim" 2>/dev/null || killed=1
kill "$victim" 2>/dev/null; wait "$victim" 2>/dev/null
[ "$killed" = 1 ] || fail "state/pid run survived agents-stop (0 of 1)"
case "$out" in *"pid:$victim"*) ;; *) fail "agents-stop did not report pid:$victim — $out" ;; esac
grep -q 'systemctl .*stop agent@alpha.service' "$CALLS" || fail "agent unit not stopped"
grep -q '^notify-owner ' "$CALLS" || fail "no push recorded (shim not reached)"

# --- guards: -h and an unknown name never start anything -------------------------------
for cli in agent-now agent-run agent-enable agent-disable; do
  : >"$CALLS"
  msg="$(run "$cli" -h 2>&1)"; rc=$?
  [ "$rc" = 2 ] || fail "$cli -h exited $rc, want 2"
  case "$msg" in usage:*) ;; *) fail "$cli -h printed no usage: $msg" ;; esac
  [ -s "$CALLS" ] && fail "$cli -h reached $(head -1 "$CALLS")"

  case "$cli" in agent-enable) args=(no-such-agent "09:00") ;; *) args=(no-such-agent) ;; esac
  msg="$(run "$cli" "${args[@]}" 2>&1)"; rc=$?
  [ "$rc" = 2 ] || fail "$cli no-such-agent exited $rc, want 2"
  [ -s "$CALLS" ] && fail "$cli no-such-agent reached $(head -1 "$CALLS")"
  [ -e "$WORK/agents/no-such-agent" ] && fail "$cli created ~/agents/no-such-agent"
done

echo "agents-stop: state/pid runs killed 1 of 1; -h and unknown-name rejected by 4 agent-* CLIs"
exit 0
