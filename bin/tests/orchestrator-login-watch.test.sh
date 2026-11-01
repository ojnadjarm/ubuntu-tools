#!/usr/bin/env bash
# orchestrator-login-watch decisions from fake auth JSON and fake pane text; claude, tmux and notify-owner are PATH shims.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$(dirname "$here")/orchestrator-login-watch"
. "$HOME/agents/bin/tests/lib/assert.sh"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
printf '#!/bin/sh\ncat "$FX_AUTH" 2>/dev/null\n' >"$WORK/bin/claude"
printf '#!/bin/sh\ncase "$1" in capture-pane) cat "$FX_PANE";; *) exit 1;; esac\n' >"$WORK/bin/tmux"
printf '#!/bin/sh\necho "$*" >>"$FX_CALLS"\nexit "${FX_NOTIFY_RC:-0}"\n' >"$WORK/bin/notify-owner"
chmod +x "$WORK/bin"/*
run() { env PATH="$WORK/bin:$PATH" FX_AUTH="$WORK/auth" FX_PANE="$WORK/pane" FX_CALLS="$WORK/calls" \
  OLW_STATE="$WORK/state" OLW_LOG="$WORK/log" ORCHESTRATOR_TMUX_SESSION=fx "$@"; }
auth() { printf '{"loggedIn": %s}\n' "$1" >"$WORK/auth"; }
pane() { printf '%b\n' "$1" >"$WORK/pane"; }
calls() { [ -f "$WORK/calls" ] && wc -l <"$WORK/calls" | tr -d ' ' || echo 0; }
T0=1800000000

# selftest: the shims are the ones on PATH, so no real push or pane read can happen.
is "selftest: notify-owner shim" "$(run sh -c 'command -v notify-owner')" "$WORK/bin/notify-owner"
is "selftest: tmux shim" "$(run sh -c 'command -v tmux')" "$WORK/bin/tmux"

auth true; pane '❯ hello\n'
is "healthy dry-run" "$(run OLW_NOW=$T0 "$W" --dry-run 2>&1 | sed 's/.*→ //')" none

pane '● Remote Control disconnected — OAuth token unavailable — run /login to\n  restore Remote Control\n\n\n'
is "pane marker dry-run says notify" "$(run OLW_NOW=$T0 "$W" --dry-run | sed 's/.*→ //')" notify
is "dry-run pushes nothing" "$(calls)" 0
ev "dry-run writes no state or log" '[ ! -e "$WORK/state" ] && [ ! -e "$WORK/log" ]'

run OLW_NOW=$T0 "$W" >/dev/null
is "first lost run pushes once" "$(calls)" 1
c=$(cat "$WORK/calls")
case "$c" in "-p high -k orchestrator-login-lost-"*"SSH (Termux) → tmux attach -t fx → /login") ok "push is high with the fix";; *) nok "push text" "$c";; esac
msg=${c#*-k * }; ev "push <= 200 chars" '[ ${#msg} -le 200 ]'
is "log line for lost" "$(grep -c ' lost (pane: run /login) push=ok' "$WORK/log")" 1

run OLW_NOW=$((T0 + 300)) "$W" >/dev/null
is "still lost within 6 h: no push" "$(calls)" 1
is "still lost within 6 h: no log line" "$(wc -l <"$WORK/log" | tr -d ' ')" 1

run OLW_NOW=$((T0 + 6 * 3600)) "$W" >/dev/null
is "re-push after 6 h" "$(calls)" 2
k1=$(sed -n 1p "$WORK/calls" | cut -d' ' -f4); k2=$(sed -n 2p "$WORK/calls" | cut -d' ' -f4)
ev "re-push key differs and has no digits" '[ "$k1" != "$k2" ] && ! printf %s "$k2" | grep -q "[0-9]"'

pane '● Remote Control disconnected — OAuth token unavailable — run /login\n❯ /login\nLogin successful. Press Enter to continue…\n'
is "Login successful after the marker clears it" "$(run OLW_NOW=$((T0 + 7 * 3600)) "$W" --dry-run | sed 's/.*→ //')" clear
run OLW_NOW=$((T0 + 7 * 3600)) "$W" >/dev/null
ev "healthy run removes the state" '[ ! -e "$WORK/state" ]'
is "log line for healthy again" "$(grep -c 'healthy again' "$WORK/log")" 1
run OLW_NOW=$((T0 + 8 * 3600)) "$W" >/dev/null
is "healthy stays quiet" "$(wc -l <"$WORK/log" | tr -d ' ')" 3

auth false; pane '❯ \n'; rm -f "$WORK/state"
is "auth loggedIn false is lost" "$(run OLW_NOW=$T0 "$W" --dry-run | sed 's/.*auth=\([a-z]*\).*→ /\1 /')" "out notify"
: >"$WORK/auth"
is "unparseable auth alone is not lost" "$(run OLW_NOW=$T0 "$W" --dry-run | sed 's/.*auth=\([a-z]*\).*→ /\1 /')" "unknown none"

auth true; pane 'API Error: 401 Invalid API key · Please run /login\n'; rm -f "$WORK/calls" "$WORK/state"
run FX_NOTIFY_RC=1 OLW_NOW=$T0 "$W" >/dev/null
is "failed push is logged" "$(grep -c 'push=fail' "$WORK/log")" 1
run OLW_NOW=$((T0 + 300)) "$W" >/dev/null
is "failed push retries next run" "$(calls)" 2

pane "$(for i in $(seq 1 45); do echo line $i; done | sed '1s/.*/Signed out of Claude — run \/login/')"
is "marker above the last 40 lines is ignored" "$(run OLW_NOW=$T0 OLW_STATE="$WORK/none" "$W" --dry-run | sed 's/.*→ //')" none
exit $bad
