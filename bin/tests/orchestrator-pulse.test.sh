#!/usr/bin/env bash
# orchestrator-pulse idle detection: dim ghost-text suggestions count as an empty prompt, typed text does not;
# it fires only into the exact session's pane running the orchestrator claude that the session registry marks idle.
# Fixture-only (FLEET §5.6): a private tmux server (TMUX_TMPDIR) hosts pulse-fx-<pid>; the real `claude` session is
# unreachable by construction, proven by the selftest before any run.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PULSE="$(dirname "$here")/orchestrator-pulse"
. "$HOME/agents/bin/tests/lib/assert.sh"

WORK=$(mktemp -d)
# tmux socket paths cap at 108 bytes: a short dir, not one under a nested run.sh TMPDIR.
TMX=$(mktemp -d /tmp/tmx.XXXXXX)
mkdir -p "$WORK/stubs"
FXS="pulse-fx-$$"
# Read-only stubs: argv goes to stubs.argv; needs.json, failed.txt and plan.rc set the queue.
for s in pc plan-usage systemctl; do
  printf '#!/bin/sh\necho "%s $*" >>"$WORK/stubs.argv"\n' "$s" >"$WORK/stubs/$s"
done
echo 'cat "$WORK/needs.json" 2>/dev/null || echo "[]"' >>"$WORK/stubs/pc"
echo 'exit $(cat "$WORK/plan.rc" 2>/dev/null || echo 0)' >>"$WORK/stubs/plan-usage"
echo 'cat "$WORK/failed.txt" 2>/dev/null; exit 0' >>"$WORK/stubs/systemctl"
# Time compression: the pulse's 1 s echo poll runs at 0.1 s; every other sleep is real.
printf '#!/bin/sh\n[ "$*" = 1 ] && exec /usr/bin/sleep 0.1\nexec /usr/bin/sleep "$@"\n' >"$WORK/stubs/sleep"
chmod +x "$WORK/stubs/"*
# Fake claude: registers itself like Claude Code (sessions/<pid>.json with its tmux pane and $WORK/status), draws $1 as the prompt.
mkdir -p "$WORK/bin" "$WORK/.claude/sessions"
cat >"$WORK/bin/claude" <<'FAKE'
#!/bin/sh
W=$1; shift; [ "$1" = --append-system-prompt-file ] && shift 2
[ -e "$W/noreg" ] || printf '{"pid":%s,"tmux":"%s:@0.%s","status":"%s"}' $$ "$(cat "$W/sess")" "$TMUX_PANE" \
  "$(cat "$W/status" 2>/dev/null || echo idle)" >"$W/.claude/sessions/$$.json"
printf "────\n❯\302\240$1\n────\n\033[2A\033[3G"; sleep 30
FAKE
chmod +x "$WORK/bin/claude"
fx() { env -u TMUX -u PULSE_TMUX_SOCKET -u PULSE_FLOOR_H TMUX_TMPDIR="$TMX" HOME="$WORK" PULSE_SESSION="$FXS" \
       PULSE_LOG="$WORK/pulse.log" PULSE_SETTLE=0 AGENT_WORK="$WORK/agent-work" WORK="$WORK" \
       PATH="$WORK/stubs:$PATH" "$@"; }
cleanup() { fx tmux kill-server 2>/dev/null; rm -rf "$WORK" "$TMX"; }
trap cleanup EXIT

# selftest: the fixture server cannot see the real orchestrator session
if fx tmux has-session -t claude 2>/dev/null; then echo "FAIL selftest: real session reachable"; exit 1; fi
ok "selftest: real session unreachable"
for s in pc plan-usage systemctl; do
  [ "$(fx sh -c "command -v $s")" = "$WORK/stubs/$s" ] || { echo "FAIL selftest: $s not stubbed"; exit 1; }
done
ok "selftest: pc, plan-usage, systemctl stubbed"

# $1 case name, $2 the prompt line body after '❯ ' (escapes allowed); cursor is left on the prompt line; $SEED pre-fills the log.
# $ORCH=0 drops the orchestrator flag, $NAME names the fixture session (default $FXS, the pulse target).
run_case() {
  fx tmux kill-server 2>/dev/null; rm -f "$WORK/.claude/sessions/"*
  printf '%s' "${SEED:-}" >"$WORK/pulse.log"
  name=${NAME:-$FXS}; echo "$name" >"$WORK/sess"
  flag="--append-system-prompt-file $WORK/agents/ORCHESTRATOR.md"; [ "${ORCH:-1}" = 1 ] || flag=
  fx tmux new-session -d -s "$name" -x 200 -y 10 "bash -c '$WORK/bin/claude $WORK $flag \"$2\"; true'"
  timeout 5 wait-for --every 0.05 --until "env -u TMUX TMUX_TMPDIR='$TMX' tmux capture-pane -pt '=$name:' | grep -q '❯'" >/dev/null
  fx bash "$PULSE" >/dev/null 2>&1
  fx tmux capture-pane -pJt "=$name:" 2>/dev/null | tr -d '\n' >"$WORK/typed"
  tail -n1 "$WORK/pulse.log"
}

out=$(run_case ghost '\033[7mt\033[27m\033[2mry running the tests\033[22m')
case "$out" in *" fired session="*) ok "ghost suggestion is idle";; *) nok "ghost suggestion is idle" "$out";; esac

out=$(run_case ghost-unfocused '\033[2mry running the tests\033[22m')
case "$out" in *" fired session="*) ok "unfocused ghost is idle";; *) nok "unfocused ghost is idle" "$out";; esac

out=$(run_case empty '\033[7m \033[27m')
case "$out" in *" fired session="*) ok "empty prompt fires";; *) nok "empty prompt fires" "$out";; esac

out=$(run_case typed 'hello\033[7m \033[27m')
case "$out" in *"input line not empty"*) ok "typed text skips";; *) nok "typed text skips" "$out";; esac

out=$(run_case typed-cursor-in-text '\033[7mh\033[27mello')
case "$out" in *"input line not empty"*) ok "typed text with cursor inside skips";; *) nok "typed text with cursor inside skips" "$out";; esac

recent="$(date -Is -d '-1 hour') fired session=$FXS prompt submitted
"
old="$(date -Is -d '-7 hours') fired session=$FXS prompt submitted
"
out=$(SEED=$recent run_case queue-empty '\033[7m \033[27m')
case "$out" in *"skip"*"queue empty"*) ok "empty queue skips";; *) nok "empty queue skips" "$out";; esac

echo '[{"id":"x1","text":"fx need"}]' >"$WORK/needs.json"
out=$(SEED=$recent run_case one-need '\033[7m \033[27m')
case "$out" in *" fired session="*) ok "open need fires";; *) nok "open need fires" "$out";; esac
rm -f "$WORK/needs.json"

out=$(SEED=$old run_case floor '\033[7m \033[27m')
case "$out" in *" fired session="*) ok "floor exceeded fires";; *) nok "floor exceeded fires" "$out";; esac

# TSP-043: the gate is a delta against the snapshot written at the last fire, not a non-empty queue.
SNAP="$WORK/pulse-queue.json"
echo 'run-fx1.scope loaded failed failed fx' >"$WORK/failed.txt"
out=$(SEED=$recent run_case failed-new '\033[7m \033[27m')
case "$out" in *" fired session="*"new: failed run-fx1.scope"*) ok "new failed unit fires, line names it";; *) nok "new failed unit fires, line names it" "$out";; esac
snap=$(cat "$SNAP" 2>/dev/null)
out=$(SEED=$recent run_case failed-same '\033[7m \033[27m')
case "$out" in *"skip"*"queue unchanged (needs 0, failed 1"*) ok "same failed unit skips as unchanged";; *) nok "same failed unit skips as unchanged" "$out";; esac
[ "$(cat "$SNAP" 2>/dev/null)" = "$snap" ] && [ -n "$snap" ] && ok "snapshot written only on fire" || nok "snapshot written only on fire" "$snap -> $(cat "$SNAP" 2>/dev/null)"
echo 'run-fx2.scope loaded failed failed fx' >>"$WORK/failed.txt"
out=$(SEED=$recent run_case failed-second '\033[7m \033[27m')
case "$out" in *" fired session="*"queue: needs 0, failed 2"*"new: failed run-fx2.scope"*) ok "second failed unit fires";; *) nok "second failed unit fires" "$out";; esac
out=$(SEED=$old run_case failed-floor '\033[7m \033[27m')
case "$out" in *" fired session="*"new: none"*) ok "floor exceeded with an unchanged queue fires";; *) nok "floor exceeded with an unchanged queue fires" "$out";; esac
# T721: a failed unit that is not ours (PC_NOT_OURS) never enters the queue.
echo 'fx-foreign-cron.service loaded failed failed fx' >>"$WORK/failed.txt"
out=$(PC_NOT_OURS='^fx-foreign' SEED=$recent run_case failed-foreign '\033[7m \033[27m')
case "$out" in *"skip"*"queue unchanged (needs 0, failed 2"*) ok "foreign failed unit stays out of the queue";; *) nok "foreign failed unit stays out of the queue" "$out";; esac
rm -f "$WORK/failed.txt"

# T1411: an open Discord escalation (discord-liaison/state/escalations/*.md) fires once and is named in the turn.
ESC="$WORK/agents/discord-liaison/state/escalations"; mkdir -p "$ESC/done"
echo fx >"$ESC/20261027T090000Z-111.md"
out=$(SEED=$recent run_case escalation-new '\033[7m \033[27m')
case "$out" in *" fired session="*"escalations 1"*"new: escalation $ESC/20261027T090000Z-111.md"*) ok "new escalation fires, line names it";;
  *) nok "new escalation fires, line names it" "$out";; esac
grep -qF "Discord escalation: $ESC/20261027T090000Z-111.md" "$WORK/typed" && ok "turn names the escalation file" \
  || nok "turn names the escalation file" "$(cat "$WORK/typed" 2>/dev/null)"
out=$(SEED=$recent run_case escalation-same '\033[7m \033[27m')
case "$out" in *"skip"*"queue unchanged"*"escalations 1"*) ok "same escalation skips as unchanged";; *) nok "same escalation skips as unchanged" "$out";; esac
mv "$ESC/20261027T090000Z-111.md" "$ESC/done/"
out=$(SEED=$recent run_case escalation-done '\033[7m \033[27m')
case "$out" in *"skip"*"queue empty"*"escalations 0"*) ok "done escalation leaves the queue";; *) nok "done escalation leaves the queue" "$out";; esac
rm -rf "$WORK/agents/discord-liaison"

out=$(ORCH=0 run_case not-orchestrator '\033[7m \033[27m')
case "$out" in *"runs no orchestrator claude"*) ok "pane without the orchestrator claude skips";; *) nok "pane without the orchestrator claude skips" "$out";; esac

touch "$WORK/noreg"
out=$(run_case unregistered '\033[7m \033[27m')
case "$out" in *"registry does not confirm"*) ok "unregistered claude skips";; *) nok "unregistered claude skips" "$out";; esac
rm -f "$WORK/noreg"

echo busy >"$WORK/status"
out=$(run_case busy '\033[7m \033[27m')
case "$out" in *"session busy, not idle"*) ok "busy registry status skips";; *) nok "busy registry status skips" "$out";; esac
rm -f "$WORK/status"

out=$(NAME="${FXS}x" run_case prefix-name '\033[7m \033[27m')
case "$out" in *"no tmux session"*) ok "session name prefix never matches";; *) nok "session name prefix never matches" "$out";; esac

if grep -vxE 'pc need list --json|plan-usage --check 80|systemctl --user list-units --state=failed --plain --no-legend' \
     "$WORK/stubs.argv" 2>/dev/null | grep -q .; then
  nok "stubs saw only read-only verbs" "$(sort -u "$WORK/stubs.argv" | tr '\n' ';')"
else ok "stubs saw only read-only verbs"; fi

exit $bad
