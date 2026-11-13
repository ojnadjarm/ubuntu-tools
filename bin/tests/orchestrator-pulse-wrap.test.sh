#!/usr/bin/env bash
# orchestrator-pulse on a wrapped input box (T1696): a turn wrapped mid-word is still recognised and submitted; a turn
# that never echoes whole is cleared row by row (Claude Code's Ctrl+U deletes one wrapped row), leaving an empty box.
# Fake box: hard-wraps at 40 columns with 2-space continuation rows, Ctrl+U drops the last row, Enter records the text.
# Fixture-only (FLEET §5.6): a private tmux server (TMUX_TMPDIR); the real `claude` session is unreachable, proven first.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PULSE="$(dirname "$here")/orchestrator-pulse"
. "$HOME/agents/bin/tests/lib/assert.sh"

WORK=$(mktemp -d)
TMX=$(mktemp -d /tmp/tmx.XXXXXX)
FXS="pulsewrap-fx-$$"
mkdir -p "$WORK/stubs" "$WORK/bin" "$WORK/.claude/sessions"
for s in pc plan-usage systemctl; do printf '#!/bin/sh\necho "%s $*" >>"$WORK/stubs.argv"\n' "$s" >"$WORK/stubs/$s"; done
echo 'echo "[]"' >>"$WORK/stubs/pc"
chmod +x "$WORK/stubs/"*
cat >"$WORK/bin/box.py" <<'PY'
import os, sys, termios, tty
W, trunc, out = 40, int(os.environ.get("TRUNC") or 0), os.environ["WORK"] + "/submitted"
buf = ""
def rows(s): return [s[i:i + W] for i in range(0, len(s), W)] or [""]
def draw():
    shown = buf[:trunc] if trunc else buf
    sys.stdout.write("\033[H\033[2J────\r\n❯ " + "\r\n  ".join(rows(shown)) + "\r\n────\r\n"); sys.stdout.flush()
tty.setraw(0); draw()
while True:
    c = os.read(0, 1).decode("utf-8", "replace")
    if c == "\x15": buf = buf[:len(buf) - len(rows(buf)[-1])] if buf else ""
    elif c == "\r": open(out, "a").write(buf + "\n"); buf = ""
    else: buf += c
    draw()
PY
cat >"$WORK/bin/claude" <<'FAKE'
#!/bin/sh
W=$1
printf '{"pid":%s,"tmux":"%s:@0.%s","status":"idle"}' $$ "$(cat "$W/sess")" "$TMUX_PANE" >"$W/.claude/sessions/$$.json"
python3 "$W/bin/box.py"
FAKE
chmod +x "$WORK/bin/claude"
fx() { env -u TMUX -u PULSE_TMUX_SOCKET -u PULSE_FLOOR_H -u LIAISON_PAPERS TMUX_TMPDIR="$TMX" HOME="$WORK" PULSE_SESSION="$FXS" \
       PULSE_LOG="$WORK/pulse.log" PULSE_SETTLE=0 AGENT_WORK="$WORK/agent-work" WORK="$WORK" PATH="$WORK/stubs:$PATH" "$@"; }
cleanup() { fx tmux kill-server 2>/dev/null; rm -rf "$WORK" "$TMX"; }
trap cleanup EXIT

if fx tmux has-session -t claude 2>/dev/null; then echo "FAIL selftest: real session reachable"; exit 1; fi
ok "selftest: real session unreachable"

# run_case: fresh fake box (env TRUNC shows only the first N typed characters), one pulse run, prints its last log line.
run_case() {
  fx tmux kill-server 2>/dev/null; rm -f "$WORK/.claude/sessions/"* "$WORK/submitted" "$WORK/pulse.log"
  echo "$FXS" >"$WORK/sess"
  fx tmux new-session -d -s "$FXS" -x 80 -y 20 \
    "env WORK=$WORK TRUNC=${TRUNC:-0} bash -c '$WORK/bin/claude $WORK --append-system-prompt-file $WORK/agents/ORCHESTRATOR.md; true'"
  timeout 5 wait-for --every 0.05 --until "env -u TMUX TMUX_TMPDIR='$TMX' tmux capture-pane -pt '=$FXS:' | grep -q '❯'" >/dev/null
  fx bash "$PULSE" >/dev/null 2>&1
  tail -n1 "$WORK/pulse.log"
}
box() { fx tmux capture-pane -pt "=$FXS:" | awk '/^❯/{on=1} on&&/^─/{exit} on' | tr -d ' \n' | sed 's/^❯\xc2\xa0//'; }
TURN='Discord escalation: /home/fx-user/agent-work/discord-liaison/escalations/20261111T214347Z-1570192187441025045.md (answer it). Pulse: go.'

out=$(PULSE_TURN=$TURN run_case)
case "$out" in *" fired session="*) ok "turn wrapped mid-path is recognised and fired";; *) nok "turn wrapped mid-path is recognised and fired" "$out";; esac
grep -qF "$TURN" "$WORK/submitted" 2>/dev/null && ok "whole turn submitted" || nok "whole turn submitted" "$(cat "$WORK/submitted" 2>/dev/null)"

out=$(PULSE_TURN=$TURN TRUNC=60 run_case)
case "$out" in *"prompt never echoed whole; box cleared"*) ok "turn never echoed whole: box cleared";; *) nok "turn never echoed whole: box cleared" "$out";; esac
is "box empty after the clear" "$(box)" ""
ev "nothing submitted" '[ ! -s "$WORK/submitted" ]'

exit $bad
