#!/usr/bin/env bash
# Fixture test for notes-brain-arm (M05c): a throwaway tmux server, stub claude sessions, a
# stub eye and a stub notify-owner. The real notes session, unit, vault and Eye are unreachable
# by construction — the stub tmux forces a private socket, proven by selftest.
#
# The record: in the observed incident (journal, 2026-09-15) the pane never showed a prompt box
# within 60 s and nothing was ever typed — no keystroke was dropped. The real defect was giving
# up silently. The dropped/partial-keystroke panes below are plausible failures of a tmux pane
# that this script must survive, not a replay of what happened.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS="$(dirname "$(dirname "$here")")"
ARM="$AGENTS/bin/notes-brain-arm"
UNIT="$AGENTS/units/notes-brain.service"
LIVE="$HOME/.config/systemd/user/notes-brain.service"
SOCK=notesarmtest
EYE=${EYE_REPO:-$HOME/the-dark-eye}
fail() { echo "notes-brain-arm.test: FAIL — $1" >&2; exit 1; }

WORK=$(mktemp -d)
cleanup() { /usr/bin/tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

STUB="$WORK/stub"; mkdir -p "$STUB"
ARMED="$WORK/armed"; CALLS="$WORK/calls.log"; : >"$CALLS"
HALF="$WORK/half-submitted"; SEEN="$WORK/turns-seen"

cat >"$STUB/tmux" <<EOF
#!/bin/sh
exec /usr/bin/tmux -L $SOCK "\$@"
EOF
# The roster the stub eye serves is not hand-written: it is the one the body's own
# brains.js builds, for the channel main.js registers. A rename in the body therefore
# renames it here too, and the script — which greps for a literal name — fails loudly
# instead of passing against a roster nothing serves. Read-only: no unit, no live body.
CHAN=$(sed -n 's/^const NOTES_BRAIN = "\([a-z0-9-]*\)";$/\1/p' "$EYE/body/src/main.js")
[ -n "$CHAN" ] || fail "no NOTES_BRAIN channel in $EYE/body/src/main.js — the body no longer registers one under that constant"
roster() { # $1 = connected (anything) or empty
  CHAN="$CHAN" F="$WORK/active.json" CONNECTED="${1:-}" node -e '
    const { createBrains } = require(process.env.EYE + "/body/src/brains");
    const b = createBrains({ main: { name: "main", color: "#b04dff", voice: 17 }, channels: [process.env.CHAN], file: process.env.F, say() {}, log() {} });
    if (process.env.CONNECTED) b.take(process.env.CHAN, 300);
    console.log(JSON.stringify({ ok: true, ...b.roster() }));
    process.exit(0);'
}
EYE="$EYE" roster >"$WORK/roster-off.json" || fail "the body's brains.js did not build a roster ($EYE)"
EYE="$EYE" roster 1 >"$WORK/roster-on.json" || fail "the body's brains.js did not build a connected roster"
grep -q "\"name\":\"$CHAN\"" "$WORK/roster-off.json" || fail "the body's roster has no channel named $CHAN"
grep -q "\"name\":\"$CHAN\"" "$ARM" || fail "notes-brain-arm greps for a channel the body does not serve (body: $CHAN)"

cat >"$STUB/eye" <<EOF
#!/bin/sh
echo "eye \$*" >>"$CALLS"
[ "\$1" = brains ] || { echo '{"ok":false}'; exit 0; }
if [ -f "$ARMED" ]; then cat "$WORK/roster-on.json"; else cat "$WORK/roster-off.json"; fi
EOF
cat >"$STUB/notify-owner" <<EOF
#!/bin/sh
echo "notify-owner \$*" >>"$CALLS"
EOF
# All four stubs below run in raw mode and redraw the input line themselves, as the real
# Claude Code box does: C-u clears the line and reprints the prompt glyph.
#
# 1. A transient prompt frame that is not ready: for 10 s keystrokes are read and discarded
# without ever reaching the prompt line, then the real box echoes and accepts the turn.
cat >"$STUB/claude" <<EOF
#!/bin/bash
echo "No conversation found to continue"
stty raw -echo 2>/dev/null
printf '\xe2\x9d\xaf '
end=\$(( \$(date +%s) + 10 ))
while [ "\$(date +%s)" -lt "\$end" ]; do read -r -N1 -t 1 junk; done
printf '\r\n\xe2\x9d\xaf '
buf=''
while IFS= read -r -N1 c; do
  case "\$c" in
    \$'\025') buf=''; printf '\r\033[K\xe2\x9d\xaf ' ;;
    \$'\r'|\$'\n')
      if [ "\$buf" = "Start: arm the ear." ]; then : >"$ARMED"; printf '\r\nEar armed.\r\n\xe2\x9d\xaf '
      else printf '\r\n\xe2\x9d\xaf '; fi
      buf='' ;;
    *) buf="\$buf\$c"; printf '%s' "\$c" ;;
  esac
done
EOF
# 2. A pane that drains only part of the line: of the first 19 characters typed, 12 to 19 never
# reach the app and never appear on the prompt line. An Enter pressed on that half line is
# recorded in \$HALF — the script must clear and retype instead of submitting it.
cat >"$STUB/claude-partial" <<EOF
#!/bin/bash
echo "No conversation found to continue"
stty raw -echo 2>/dev/null
printf '\xe2\x9d\xaf '
buf=''; tot=0
while IFS= read -r -N1 c; do
  case "\$c" in
    \$'\025') buf=''; printf '\r\033[K\xe2\x9d\xaf ' ;;
    \$'\r'|\$'\n')
      if [ "\$buf" = "Start: arm the ear." ]; then : >"$ARMED"; printf '\r\nEar armed.\r\n\xe2\x9d\xaf '
      else echo "\$buf" >>"$HALF"; printf '\r\nUnknown.\r\n\xe2\x9d\xaf '; fi
      buf='' ;;
    *)
      tot=\$((tot + 1))
      if [ "\$tot" -gt 11 ] && [ "\$tot" -le 19 ]; then continue; fi
      buf="\$buf\$c"; printf '%s' "\$c" ;;
  esac
done
EOF
# 3. A turn that lands late: the session takes 6 s to reach its listen loop. Every turn it
# receives is recorded in \$SEEN — a retry must not double-send one that already landed.
cat >"$STUB/claude-late" <<EOF
#!/bin/bash
echo "No conversation found to continue"
stty raw -echo 2>/dev/null
printf '\xe2\x9d\xaf '
buf=''
while IFS= read -r -N1 c; do
  case "\$c" in
    \$'\025') buf=''; printf '\r\033[K\xe2\x9d\xaf ' ;;
    \$'\r'|\$'\n')
      if [ "\$buf" = "Start: arm the ear." ]; then
        echo "\$buf" >>"$SEEN"
        printf '\r\nworking...\r\n\xe2\x9d\xaf '
        sleep 6
        : >"$ARMED"
        printf '\r\nEar armed.\r\n\xe2\x9d\xaf '
      else printf '\r\n\xe2\x9d\xaf '; fi
      buf='' ;;
    *) buf="\$buf\$c"; printf '%s' "\$c" ;;
  esac
done
EOF
# 4. A first turn whose output scrolls the turn out of the visible pane: it prints 40 lines
# into a 30-row pane, then arms 6 s later. Every turn it receives is recorded in \$SEEN — a
# retry must not double-send one the session already took just because it left the view.
cat >"$STUB/claude-scroll" <<EOF
#!/bin/bash
echo "No conversation found to continue"
stty raw -echo 2>/dev/null
printf '\xe2\x9d\xaf '
buf=''
while IFS= read -r -N1 c; do
  case "\$c" in
    \$'\025') buf=''; printf '\r\033[K\xe2\x9d\xaf ' ;;
    \$'\r'|\$'\n')
      if [ "\$buf" = "Start: arm the ear." ]; then
        echo "\$buf" >>"$SEEN"
        printf '\r\n'
        for i in \$(seq 40); do printf 'thinking line %s\r\n' "\$i"; done
        printf '\xe2\x9d\xaf '
        sleep 6
        : >"$ARMED"
        printf '\r\nEar armed.\r\n\xe2\x9d\xaf '
      else printf '\r\n\xe2\x9d\xaf '; fi
      buf='' ;;
    *) buf="\$buf\$c"; printf '%s' "\$c" ;;
  esac
done
EOF
# A pane that never shows a box: the trust dialog.
cat >"$STUB/claude-dialog" <<'EOF'
#!/bin/sh
echo "Do you trust the files in this folder?"
while IFS= read -r line; do :; done
EOF
chmod +x "$STUB"/tmux "$STUB"/eye "$STUB"/notify-owner "$STUB"/claude \
         "$STUB"/claude-partial "$STUB"/claude-late "$STUB"/claude-scroll "$STUB"/claude-dialog
export PATH="$STUB:/usr/bin:/bin"

# --- selftest: the real notes session is unreachable through the stub tmux --------------
[ "$(command -v tmux)" = "$STUB/tmux" ] || fail "selftest: stub tmux not on PATH"
[ "$(command -v eye)" = "$STUB/eye" ] || fail "selftest: stub eye not on PATH"
[ "$(command -v notify-owner)" = "$STUB/notify-owner" ] || fail "selftest: stub notify-owner not on PATH"
tmux has-session -t notes 2>/dev/null && fail "selftest: stub tmux can see a session named notes — NOT isolated"
/usr/bin/tmux -L "$SOCK" list-sessions 2>/dev/null | grep -q . && fail "selftest: private socket not empty"
# the stub roster is the body's shape, connected only when the fixture armed
grep -q '"name":"main","color":"#b04dff","voice":17,"connected":false,"parked":0' "$WORK/roster-off.json" \
  || fail "selftest: the roster from brains.js is not the shape eye brains serves: $(cat "$WORK/roster-off.json")"
"$STUB/eye" brains | grep -q "\"name\":\"$CHAN\"[^}]*\"connected\":false" || fail "selftest: the stub roster is connected before anything armed"
: >"$ARMED"; "$STUB/eye" brains | grep -q "\"name\":\"$CHAN\"[^}]*\"connected\":true" || fail "selftest: the stub roster never reports connected"
rm -f "$ARMED"; : >"$CALLS"

start_fixture() { # $1 = stub claude to run
  tmux kill-session -t notes 2>/dev/null
  rm -f "$ARMED" "$HALF" "$SEEN"
  tmux new-session -d -s notes -x 100 -y 30 "$STUB/$1" || fail "fixture session did not start"
  sleep 1
  tmux capture-pane -pt notes | grep -q "No conversation found to continue" \
    || [ "$1" = claude-dialog ] || fail "fixture pane lacks the --continue error"
}

# --- 1. the new script: retries and verifies, ear armed ---------------------------------
: >"$CALLS"
start_fixture claude
out="$(NOTES_BOX_WAIT=20 NOTES_ARM_WAIT=8 NOTES_ECHO_WAIT=6 NOTES_POLL=2 sh "$ARM" 2>&1)" \
  || fail "notes-brain-arm exited non-zero: $out"
[ -f "$ARMED" ] || fail "new script did not arm the ear: $out"
grep -qE "ear armed" <<<"$out" || fail "new script did not report the arming: $out"
grep -q '^notify-owner ' "$CALLS" && fail "new script pushed although it armed: $out"
grep -q '^eye brains' "$CALLS" || fail "new script did not verify with eye brains"
echo "  transient frame: $out"

# --- 2. a pane that drains only part of the line: never submit a half line --------------
: >"$CALLS"
start_fixture claude-partial
out="$(NOTES_BOX_WAIT=20 NOTES_ARM_WAIT=8 NOTES_ECHO_WAIT=6 NOTES_POLL=2 sh "$ARM" 2>&1)" \
  || fail "notes-brain-arm exited non-zero on a partial pane: $out"
[ -f "$HALF" ] && fail "partial pane: a half-typed line was submitted: $(cat "$HALF") — $out"
[ -f "$ARMED" ] || fail "partial pane: never armed after clearing and retyping: $out"
grep -q "never echoed the whole turn" <<<"$out" || fail "partial pane: the half line was not reported: $out"
grep -q '^notify-owner ' "$CALLS" && fail "partial pane: pushed although it armed: $out"
echo "  partial pane: $out"

# --- 3. a turn that lands late: no duplicate send, no false failure push -----------------
# Distinct from 4: the submitted turn stays visible in the pane; only the arming is slow.
: >"$CALLS"
start_fixture claude-late
out="$(NOTES_BOX_WAIT=20 NOTES_ARM_WAIT=4 NOTES_ECHO_WAIT=4 NOTES_POLL=2 sh "$ARM" 2>&1)" \
  || fail "notes-brain-arm exited non-zero on a late turn: $out"
[ -f "$ARMED" ] || fail "late turn: never armed: $out"
[ "$(wc -l <"$SEEN")" = 1 ] || fail "late turn: the turn was sent $(wc -l <"$SEEN") times: $out"
grep -q '^notify-owner ' "$CALLS" && fail "late turn: false failure push: $out"
grep -q "ear armed" <<<"$out" || fail "late turn: arming not reported: $out"
echo "  late turn: $out"

# --- 4. a first turn that scrolls out of the visible pane: no duplicate send ------------
# Distinct from 3: the turn itself scrolls out of view, so "is it still on the input line?"
# cannot be answered by searching the pane for the turn text.
: >"$CALLS"
start_fixture claude-scroll
out="$(NOTES_BOX_WAIT=20 NOTES_ARM_WAIT=4 NOTES_ECHO_WAIT=4 NOTES_POLL=2 sh "$ARM" 2>&1)" \
  || fail "notes-brain-arm exited non-zero on a scrolled-out turn: $out"
tmux capture-pane -pJt notes | grep -qF "Start: arm the ear." \
  && fail "scrolled-out turn: the fixture kept the turn in view — it does not exercise the case"
[ -f "$ARMED" ] || fail "scrolled-out turn: never armed: $out"
[ "$(wc -l <"$SEEN")" = 1 ] || fail "scrolled-out turn: the turn was sent $(wc -l <"$SEEN") times: $out"
grep -q '^notify-owner ' "$CALLS" && fail "scrolled-out turn: false failure push: $out"
echo "  scrolled-out turn: $out"

# --- 5. no box at all: nothing typed, owner told, unit not failed ----------------------
: >"$CALLS"
start_fixture claude-dialog
out="$(NOTES_BOX_WAIT=4 NOTES_ARM_WAIT=4 NOTES_ECHO_WAIT=2 NOTES_POLL=2 sh "$ARM" 2>&1)" \
  || fail "notes-brain-arm exited non-zero on a dialog pane: $out"
grep -q "no prompt box" <<<"$out" || fail "dialog pane: wrong message: $out"
grep -q '^notify-owner -p high ' "$CALLS" || fail "dialog pane: owner not told: $(cat "$CALLS")"
tmux capture-pane -pt notes | grep -q "Start: arm the ear." && fail "dialog pane: it typed anyway"
echo "  dialog pane: $out"

# --- 6. the script's worst case stays under the unit's start timeout -------------------
budget="$(sh "$ARM" --budget)" || fail "notes-brain-arm --budget failed"
[[ $budget =~ ^[0-9]+$ ]] || fail "--budget is not a number: $budget"
timeout="$(sed -n 's/^TimeoutStartSec=\([0-9]*\)$/\1/p' "$UNIT")"
[ -n "$timeout" ] || fail "the unit has no TimeoutStartSec in plain seconds"
[ "$((budget + 30))" -lt "$timeout" ] \
  || fail "worst case ${budget}s + 30s slop is not under TimeoutStartSec=${timeout}s — systemd would kill ExecStartPost and Restart=on-failure would loop"
# The timeout above is only meaningful if the unit systemd actually runs carries it.
cmp -s "$UNIT" "$LIVE" \
  || fail "the synced unit $LIVE differs from $UNIT — the live TimeoutStartSec may be stale"
echo "  budget: worst case ${budget}s < TimeoutStartSec=${timeout}s (source and synced unit identical)"

# --- 7. the unit points at the script --------------------------------------------------
grep -q '^ExecStartPost=%h/agents/bin/notes-brain-arm$' "$UNIT" || fail "unit does not call notes-brain-arm"
[ -x "$ARM" ] || fail "notes-brain-arm is not executable"
systemd-analyze --user verify "$UNIT" >/dev/null 2>&1 || fail "systemd-analyze verify"

echo "notes-brain-arm: the script arms, never submits a half line, never double-sends a late turn, pushes only when the box never came; budget < start timeout"
exit 0
