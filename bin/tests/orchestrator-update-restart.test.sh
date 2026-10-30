#!/usr/bin/env bash
# orchestrator-update-restart: the decision table, then the restart path against fakes only.
# Fixture-only (FLEET §5.6): a private tmux server (TMUX_TMPDIR), stub claude/systemctl/notify-owner on PATH, a fake
# CLAUDE_DIR; the real `claude` session and unit are unreachable by construction, proven by the selftest before any run.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUR="$(dirname "$here")/orchestrator-update-restart"
. "$HOME/agents/bin/tests/lib/assert.sh"

# --- decide: facts in, verdict out ---------------------------------------------------------------
d() { ( OWNER_HOURS=08-01 OWNER_WAIT_H=24; . "$OUR"; decide "$@" ); }
is "same version: noop"                "$(d 2.1.1 2.1.1 0 04 '' 0)" "noop up to date"
is "no orchestrator: wait"             "$(d '' 2.1.1 0 04 '' 0)" "wait no orchestrator claude found"
is "installed unknown: wait"           "$(d 2.1.1 '' 0 04 '' 0)" "wait installed version unknown"
is "busy: wait with the reason"        "$(d 2.1.1 2.1.2 0 04 'input line not empty' 0)" "wait input line not empty"
is "escalation open: wait"             "$(d 2.1.1 2.1.2 0 04 '' 2)" "wait 2 Discord escalation(s) open"
is "night 04: restart"                 "$(d 2.1.1 2.1.2 0 04 '' 0)" "restart 2.1.1 -> 2.1.2"
is "01 is outside owner hours"         "$(d 2.1.1 2.1.2 0 01 '' 0)" "restart 2.1.1 -> 2.1.2"
is "07 is outside owner hours"         "$(d 2.1.1 2.1.2 0 07 '' 0)" "restart 2.1.1 -> 2.1.2"
is "08, 2 h old: wait"                 "$(d 2.1.1 2.1.2 7200 08 '' 0)" "wait owner hours, new version 2 h old"
is "00 is owner hours"                 "$(d 2.1.1 2.1.2 0 00 '' 0)" "wait owner hours, new version 0 h old"
is "14, 24 h old: restart"             "$(d 2.1.1 2.1.2 86400 14 '' 0)" "restart 2.1.1 -> 2.1.2"
is "escalation beats the 24 h rule"    "$(d 2.1.1 2.1.2 90000 14 '' 1)" "wait 1 Discord escalation(s) open"

# --- restart path against fakes -----------------------------------------------------------------
WORK=$(mktemp -d)
TMX=$(mktemp -d /tmp/tmx.XXXXXX)
FXS="our-fx-$$"
mkdir -p "$WORK/stubs" "$WORK/versions" "$WORK/.claude/sessions" "$WORK/esc"
# Fake claude: bash copied to versions/<v> so /proc/<pid>/exe names the version; argv[0] is claude with the orchestrator flag.
for v in 2.1.1 2.1.2; do cp /usr/bin/bash "$WORK/versions/$v"; done
cat >"$WORK/fake-claude" <<'FAKE'
W=$WORK
printf '{"pid":%s,"tmux":"%s:@0.%s","status":"%s","sessionId":"%s"}' $$ "$(cat "$W/sess")" "$TMUX_PANE" \
  "$(cat "$W/status" 2>/dev/null || echo idle)" "$(cat "$W/sid")" >"$W/.claude/sessions/$$.json"
printf "────\n❯\302\240%b\n────\n\033[2A\033[3G" "$(cat "$W/typed" 2>/dev/null)"
while read -r l; do [ "$l" = /exit ] && [ ! -e "$W/stubborn" ] && exit 0; done
FAKE
launch() { tmux new-session -d -s "$(cat "$WORK/sess")" -x 200 -y 10 bash -c \
  "(exec -a claude $WORK/versions/$1 $WORK/fake-claude --append-system-prompt-file $WORK/ORCHESTRATOR.md); true"; }
# Stubs log argv; systemctl start relaunches the fake on the installed version with $WORK/newsid (default: same id).
for s in systemctl notify-owner claude; do printf '#!/bin/bash\necho "%s $*" >>"$WORK/stubs.argv"\n' "$s" >"$WORK/stubs/$s"; done
echo 'echo "$(cat "$WORK/installed") (Claude Code)"' >>"$WORK/stubs/claude"
cat >>"$WORK/stubs/systemctl" <<EOF
[ "\$2" = start ] || exit 0
cp "\$WORK/newsid" "\$WORK/sid" 2>/dev/null
$(declare -f launch)
launch "\$(cat "\$WORK/installed")"
EOF
chmod +x "$WORK/stubs/"*
fx() { env -u TMUX TMUX_TMPDIR="$TMX" WORK="$WORK" CLAUDE_CONFIG_DIR="$WORK/.claude" ORCHESTRATOR_TMUX_SESSION="$FXS" \
       OUR_LOG="$WORK/our.log" OUR_ESCALATIONS="$WORK/esc" OUR_EXIT_WAIT=3 OUR_START_WAIT=10 OWNER_WAIT_H=0 \
       PATH="$WORK/stubs:$PATH" "$@"; }
cleanup() { fx tmux kill-server 2>/dev/null; rm -rf "$WORK" "$TMX"; }
trap cleanup EXIT

if fx tmux has-session -t "=claude" 2>/dev/null; then echo "FAIL selftest: real session reachable"; exit 1; fi
ok "selftest: real session unreachable"
for s in systemctl notify-owner claude; do
  [ "$(fx sh -c "command -v $s")" = "$WORK/stubs/$s" ] || { echo "FAIL selftest: $s not stubbed"; exit 1; }
done
ok "selftest: systemctl, notify-owner, claude stubbed"

# case_ <running> <installed> [args…]: fresh fixture, one run; prints its log line. $TYPED pre-fills the input line, $NEWSID forks the session id.
case_() {
  fx tmux kill-server 2>/dev/null; rm -f "$WORK/.claude/sessions/"* "$WORK/stubs.argv" "$WORK/newsid"
  [ -z "${NEWSID:-}" ] || echo "$NEWSID" >"$WORK/newsid"
  echo "$FXS" >"$WORK/sess"; echo sid-old >"$WORK/sid"; echo "$2" >"$WORK/installed"; printf '%s' "${TYPED:-}" >"$WORK/typed"
  fx bash -c "$(declare -f launch); launch $1"
  timeout 5 wait-for --every 0.05 --until "ls '$WORK/.claude/sessions/'*.json" >/dev/null
  basename "$(ls "$WORK/.claude/sessions/"*.json)" .json >"$WORK/old"
  shift 2; fx bash "$OUR" "$@" >/dev/null 2>&1; echo "rc=$?" >"$WORK/rc"
  tail -n1 "$WORK/our.log"
}
argv() { cat "$WORK/stubs.argv" 2>/dev/null; }

out=$(case_ 2.1.1 2.1.1)
case "$out" in *"noop up to date"*) ok "same version: noop logged";; *) nok "same version: noop logged" "$out";; esac
ev "noop: no unit start" '! argv | grep -q "systemctl"'

out=$(case_ 2.1.1 2.1.2 --dry-run)
case "$out" in *"dry-run restart 2.1.1 -> 2.1.2"*) ok "dry-run prints restart";; *) nok "dry-run prints restart" "$out";; esac
ev "dry-run: old session still running" 'kill -0 $(cat "$WORK/old") 2>/dev/null'
ev "dry-run: no unit start" '! argv | grep -q "systemctl"'

echo busy >"$WORK/status"; out=$(case_ 2.1.1 2.1.2); rm -f "$WORK/status"
case "$out" in *"wait session busy, not idle"*) ok "busy registry: wait";; *) nok "busy registry: wait" "$out";; esac
ev "busy: old session still running" 'kill -0 $(cat "$WORK/old") 2>/dev/null'

out=$(TYPED='hello' case_ 2.1.1 2.1.2)
case "$out" in *"wait input line not empty"*) ok "typed text: wait";; *) nok "typed text: wait" "$out";; esac

echo fx >"$WORK/esc/1.md"; out=$(case_ 2.1.1 2.1.2); rm -f "$WORK/esc/1.md"
case "$out" in *"wait 1 Discord escalation(s) open"*) ok "open escalation: wait";; *) nok "open escalation: wait" "$out";; esac

out=$(case_ 2.1.1 2.1.2)
case "$out" in *"restarted 2.1.1 -> 2.1.2 session=sid-old"*) ok "idle + newer: restarted, read back";; *) nok "idle + newer: restarted, read back" "$out";; esac
ev "restart: old pid gone" '! kill -0 $(cat "$WORK/old") 2>/dev/null'
ev "restart: unit started once" '[ "$(argv | grep -c "systemctl --user start claude-orchestrator.service")" = 1 ]'
ev "restart: owner not notified" '! argv | grep -q notify-owner'
is "restart: exit 0" "$(cat "$WORK/rc")" "rc=0"

out=$(NEWSID=sid-forked case_ 2.1.1 2.1.2)
case "$out" in *"fail after restart the pane does not run 2.1.2 in session sid-old"*) ok "new session id: fail";; *) nok "new session id: fail" "$out";; esac
ev "new session id: owner notified" 'argv | grep -q "notify-owner orchestrator-update-restart: after restart"'

touch "$WORK/stubborn"; out=$(case_ 2.1.1 2.1.2); rm -f "$WORK/stubborn"
case "$out" in *"fail /exit did not end pid"*) ok "/exit ignored: fail";; *) nok "/exit ignored: fail" "$out";; esac
ev "/exit ignored: owner notified, no unit start" 'argv | grep -q notify-owner && ! argv | grep -q systemctl'
ev "/exit ignored: session left running" 'kill -0 $(cat "$WORK/old") 2>/dev/null'
is "/exit ignored: exit 1" "$(cat "$WORK/rc")" "rc=1"

exit $bad
