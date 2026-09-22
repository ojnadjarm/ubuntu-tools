#!/usr/bin/env bash
# Fixture test for the notes brain (M05b): the unit, its ExecStart on stub tmux/claude,
# the kill switch and the roster, the brief. No real unit, tmux, claude or vault is reached.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINDIR="$(dirname "$here")"
AGENTS="$(dirname "$BINDIR")"
UNIT="$AGENTS/units/notes-brain.service"
BRIEF="$AGENTS/notes/BRIEF.md"
fail() { echo "notes-brain.test: FAIL — $1" >&2; exit 1; }

# --- the unit file --------------------------------------------------------------------
systemd-analyze --user verify "$UNIT" >/dev/null 2>&1 || fail "systemd-analyze verify"
exec_line="$(sed -n 's/^ExecStart=//p' "$UNIT")"
[ "$(printf '%s\n' "$exec_line" | wc -l)" = 1 ] || fail "one ExecStart expected"
for want in "--continue" "--no-chrome" "--name notes" "--model claude-sonnet-5" \
            "--append-system-prompt-file BRIEF.md" "--tools Monitor,Bash,Read" \
            "--permission-mode dontAsk" "--strict-mcp-config" "--add-dir %h/obsidian-vault" \
            '--allowedTools \\"Bash(eye:*),Bash(notes-file:*),Bash(sleep:*)\\"' \
            '--disallowedTools \\"Bash(eye tv:*),Bash(eye talk-to:*),Bash(eye mic:*),Bash(eye show:*)\\"'; do
  case "$exec_line" in *"$want"*) ;; *) fail "ExecStart lacks $want" ;; esac
done
grep -q '^WorkingDirectory=%h/agents/notes$' "$UNIT" || fail "WorkingDirectory"
grep -q '^ExecStop=/usr/bin/tmux kill-session -t notes$' "$UNIT" || fail "ExecStop"
grep -q '^After=dark-eye.service' "$UNIT" || fail "After=dark-eye.service"
timeout="$(sed -n 's/^TimeoutStartSec=\([0-9]*\)$/\1/p' "$UNIT")"
[ -n "$timeout" ] || fail "TimeoutStartSec in plain seconds (ExecStartPost must not be killed mid-arming)"

# --- ExecStart on stubs: tmux gets session "notes", claude gets the flags and the env -----
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
STUB="$WORK/stub"; mkdir -p "$STUB" "$WORK/agents/notes"
cp "$AGENTS/notes/agent.env" "$WORK/agents/notes/agent.env"
# The pane this stub reports is the prompt glyph plus whatever send-keys -l typed and C-u did
# not clear, so notes-brain-arm's echo read-back sees the turn it typed.
cat >"$STUB/tmux" <<'STUBEOF'
#!/bin/sh
echo "tmux $*" >>"$CALLS"
last=; for a in "$@"; do last=$a; done
case "$1" in
  has-session) exit 1 ;;
  capture-pane) printf '❯ '; cat "$CALLS.typed" 2>/dev/null; echo ;;
  send-keys) case " $* " in *" -l "*) printf '%s' "$last" >>"$CALLS.typed" ;; *" C-u "*) : >"$CALLS.typed" ;; esac ;;
  new-session) while [ $# -gt 1 ]; do [ "$1" = -c ] && cd "$2"; shift; done; sh -c "$1" ;;
esac
STUBEOF
cat >"$STUB/claude" <<'STUBEOF'
#!/bin/sh
echo "claude $*" >>"$CALLS"; echo "cwd $PWD vault $NOTES_VAULT_DIR folder $NOTES_FOLDER" >>"$CALLS"
STUBEOF
chmod +x "$STUB"/tmux "$STUB"/claude
CALLS="$WORK/calls.log"; : >"$CALLS"
resolved="$(PATH="$STUB:/usr/bin:/bin" sh -c 'command -v tmux; command -v claude')"
case "$resolved" in "$STUB/tmux
$STUB/claude") ;; *) fail "selftest: stubs not on PATH: $resolved" ;; esac
# systemd unquoting: the sh -c body sits in single quotes, \\" becomes \"
body="$(printf '%s' "$exec_line" | sed "s|^/bin/sh -c '||; s|'\$||; s|%h|$WORK|g; s|\\\\\\\\\"|\\\\\"|g")"
HOME="$WORK" CALLS="$CALLS" PATH="$STUB:/usr/bin:/bin" sh -c "$body" || fail "ExecStart body exited $?"
grep -q "^tmux new-session -d -s notes -c $WORK/agents/notes " "$CALLS" || fail "tmux session: $(cat "$CALLS")"
grep -q '^claude --continue --no-chrome --name notes --model claude-sonnet-5 --append-system-prompt-file BRIEF.md --tools Monitor,Bash,Read --permission-mode dontAsk --strict-mcp-config --add-dir '"$WORK"'/obsidian-vault --allowedTools Bash(eye:\*),Bash(notes-file:\*),Bash(sleep:\*) --disallowedTools Bash(eye tv:\*),Bash(eye talk-to:\*),Bash(eye mic:\*),Bash(eye show:\*)$' "$CALLS" || fail "claude args: $(cat "$CALLS")"
grep -q "^cwd $WORK/agents/notes vault $WORK/obsidian-vault folder audio notes$" "$CALLS" || fail "env/cwd: $(cat "$CALLS")"
[ "$(grep -c '^claude ' "$CALLS")" = 1 ] || fail "fallback claude ran although --continue succeeded"
post="$(sed -n 's/^ExecStartPost=//p' "$UNIT")"
[ "$post" = '%h/agents/bin/notes-brain-arm' ] || fail "ExecStartPost is not notes-brain-arm: $post"
[ -x "$BINDIR/notes-brain-arm" ] || fail "notes-brain-arm missing or not executable"
cat >"$STUB/eye" <<'STUBEOF'
#!/bin/sh
echo "eye $*" >>"$CALLS"
echo '{"ok":true,"brains":[{"name":"notes","connected":true}]}'
STUBEOF
chmod +x "$STUB/eye"
: >"$CALLS"; CALLS="$CALLS" PATH="$STUB:/usr/bin:/bin" NOTES_BOX_WAIT=8 NOTES_ARM_WAIT=4 NOTES_ECHO_WAIT=4 NOTES_POLL=1 \
  sh "$BINDIR/notes-brain-arm" >/dev/null || fail "notes-brain-arm exited $?"
grep -q '^tmux send-keys -t notes -l Start: arm the ear.$' "$CALLS" || fail "first turn not typed: $(cat "$CALLS")"
grep -q '^tmux send-keys -t notes Enter$' "$CALLS" || fail "first turn not submitted"
grep -q '^eye brains$' "$CALLS" || fail "arming not verified against eye brains"

# --- kill switch and roster on shims ---------------------------------------------------
BIN="$WORK/agents/bin"; mkdir -p "$BIN"
ln -s "$BINDIR/env.sh" "$BIN/env.sh"; ln -s "$BINDIR/fleetlib.sh" "$BIN/fleetlib.sh"
: >"$WORK/config.env"
cat >"$BIN/systemctl" <<'STUBEOF'
#!/bin/sh
echo "systemctl $*" >>"$CALLS"
case "$*" in *is-active*notes-brain.service*) echo active ;; *is-active*) echo inactive ;; esac
exit 0
STUBEOF
for c in notify-owner claude jq; do printf '#!/bin/sh\nexit 0\n' >"$BIN/$c"; done
chmod +x "$BIN"/systemctl "$BIN"/notify-owner "$BIN"/claude "$BIN"/jq
run() { HOME="$WORK" HARNESS_HOME="$WORK/agents" HARNESS_CONFIG="$WORK/config.env" HARNESS_AGENT="" \
        CALLS="$CALLS" PATH="$BIN:/usr/bin:/bin" bash "$BINDIR/$1"; }
resolved="$(HOME="$WORK" HARNESS_HOME="$WORK/agents" HARNESS_CONFIG="$WORK/config.env" PATH="/usr/bin:/bin" \
  bash -c '. "$HOME/agents/bin/fleetlib.sh"; fleet_path; command -v systemctl; command -v notify-owner')"
case "$resolved" in "$BIN/systemctl
$BIN/notify-owner") ;; *) fail "selftest: fleet shims not on PATH: $resolved" ;; esac
: >"$CALLS"; out="$(run agents-stop 2>&1)" || fail "agents-stop: $out"
grep -q '^systemctl --user stop notes-brain.service$' "$CALLS" || fail "agents-stop did not stop notes-brain"
case "$out" in *notes-brain*) ;; *) fail "agents-stop did not list notes-brain: $out" ;; esac
grep '^| notes ' "$HOME/agents/KB/orchestrator.md" >"$WORK/CLAUDE.md" || fail "no notes row in KB/orchestrator.md"
grep -q '`notes-brain.service`' "$WORK/CLAUDE.md" || fail "roster row does not name notes-brain.service"
: >"$CALLS"; out="$(run agents-start 2>&1)" || fail "agents-start: $out"
grep -q '^systemctl --user enable --now notes-brain.service$' "$CALLS" || fail "agents-start did not enable notes-brain"

# --- the brief -------------------------------------------------------------------------
for want in '`file it`, `save it`, `that'"'"'s it`, `done`, `guárdalo`, `ya está`, `archívalo`,' '`listo`' \
            'eye listen-loop --as notes' 'eye speak --as notes' 'notes-file raw' "notes-file apply - <<'EOF'" \
            'no new `VOICE:` line has come for 10 minutes' 'sleep 600' 'refused: no vault' \
            'Not atomic across files' 'Never speak unprompted' 'never forward anything to `main`' \
            'never file an idea twice' 'Synthesise' 'One file per idea' '`[[wikilink]]`'; do
  grep -qF -- "$want" "$BRIEF" || fail "BRIEF.md lacks: $want"
done

echo "notes-brain: unit verified, ExecStart on stubs ok, kill switch + roster ok, brief carries 2.4"
exit 0
