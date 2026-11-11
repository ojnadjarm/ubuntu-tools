#!/usr/bin/env bash
# idle-compact: the decision table, then dry run, --apply and every skip against a fake claude in a private tmux server.
# Fixture-only (FLEET §5.6): tmux -L <fixture socket>, a fake CLAUDE_DIR (registry + transcript), fixture config.env,
# stub systemctl; the real session and registry are unreachable by construction, proven by the selftest before any run.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IC="$(dirname "$here")/idle-compact"
. "$HOME/agents/bin/tests/lib/assert.sh"

# --- decide: facts in, verdict out (enabled status idle_min tokens compacted pane_reason) ----------
d() { ( IDLE_COMPACT_AFTER=45 IDLE_COMPACT_MIN_TOKENS=100000 HARNESS_CONFIG=/dev/null; . "$IC"; decide "$@" ); }
is "idle, large, empty prompt: compact" "$(d on idle 50 150000 0 '')" "compact"
is "off: skip"                          "$(d off idle 50 150000 0 '')" "skip off (IDLE_COMPACT=off)"
is "mid-turn: skip"                     "$(d on busy 50 150000 0 '')" "skip session busy, not idle"
is "idle 44 min: skip"                  "$(d on idle 44 150000 0 '')" "skip idle 44 min < 45"
is "already compacted: skip"            "$(d on idle 50 150000 1 '')" "skip already compacted since its last request"
is "small context: skip"                "$(d on idle 50 99999 0 '')" "skip 99999 tokens < 100000"
is "typed text: skip"                   "$(d on idle 50 150000 0 'prompt box not empty (len=5)')" "skip prompt box not empty (len=5)"

# --- fixture: fake claude in a private tmux server --------------------------------------------------
WORK=$(mktemp -d)
SOCK="ic-fx-$$"
SID=11111111-2222-3333-4444-555555555555
TR="$WORK/.claude/projects/-fx/$SID.jsonl"
mkdir -p "$WORK/.claude/sessions" "$WORK/.claude/projects/-fx" "$WORK/stubs"
# Fake claude: registers itself with its tmux pane, draws a prompt box; a typed /compact appends a compaction boundary.
cat >"$WORK/fake-claude" <<'FAKE'
W=$WORK
printf '{"pid":%s,"sessionId":"%s","tmux":"fx:@0.%s","status":"%s","statusUpdatedAt":%s}' $$ "$SID" "$TMUX_PANE" \
  "$(cat "$W/status")" "$(cat "$W/st_at")" >"$W/.claude/sessions/$$.json"
printf "%b\n────\n❯\302\240%b\n────\n\033[2A\033[3G" "$(cat "$W/above")" "$(cat "$W/typed")"
while read -r l; do
  echo "$l" >>"$W/keys"
  [ "$l" = /compact ] && printf '{"type":"system","subtype":"compact_boundary","timestamp":"x","compactMetadata":{"trigger":"manual","preTokens":1,"postTokens":12000}}\n' >>"$TR"
done
FAKE
printf '#!/bin/bash\necho "systemctl $*" >>"$WORK/stubs.argv"\n' >"$WORK/stubs/systemctl"; chmod +x "$WORK/stubs/systemctl"
fx() { env -u TMUX WORK="$WORK" SID="$SID" TR="$TR" CLAUDE_CONFIG_DIR="$WORK/.claude" IDLE_COMPACT_TMUX_SOCKET="$SOCK" \
       HARNESS_CONFIG="$WORK/config.env" IDLE_COMPACT_LOG="$WORK/ic.log" IDLE_COMPACT_WAIT=15 \
       PATH="$WORK/stubs:$PATH" "$@"; }
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

# Selftest: the fixture's tmux server holds no real session, its registry holds no real pid, systemctl is stubbed.
real=${ORCHESTRATOR_TMUX_SESSION:-claude}
tmux -L "$SOCK" new-session -d -s probe true 2>/dev/null
if fx bash -c ". '$IC'; tm has-session -t '=$real'" 2>/dev/null; then echo "FAIL selftest: real session reachable"; exit 1; fi
ok "selftest: real tmux session unreachable"
[ -z "$(fx bash -c ". '$IC'; sessions")" ] || { echo "FAIL selftest: registry not the fixture's"; exit 1; }
ok "selftest: registry is the fixture's (empty before launch)"
[ "$(fx sh -c 'command -v systemctl')" = "$WORK/stubs/systemctl" ] || { echo "FAIL selftest: systemctl not stubbed"; exit 1; }
ok "selftest: systemctl stubbed"

# case_ [args…]: fresh fixture, one run, prints its output. Env: STATUS, IDLE (min), TOKENS, TYPED, ABOVE, CONF.
case_() {
  tmux -L "$SOCK" kill-server 2>/dev/null; rm -f "$WORK/.claude/sessions/"* "$WORK/keys"
  local idle=${IDLE:-50} old; old=$(( $(date +%s) - idle * 60 ))
  echo "${STATUS:-idle}" >"$WORK/status"; echo "$((old * 1000))" >"$WORK/st_at"
  printf '%s' "${TYPED:-}" >"$WORK/typed"; printf '%s' "${ABOVE:-}" >"$WORK/above"; printf '%s\n' "${CONF:-}" >"$WORK/config.env"
  printf '{"type":"user","message":{"content":"hi"}}\n{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}}}\n' \
    "${TOKENS:-150000}" >"$TR"
  [ -z "${COMPACTED:-}" ] || printf '{"type":"system","subtype":"compact_boundary","compactMetadata":{"postTokens":12000}}\n' >>"$TR"
  fx tmux -L "$SOCK" new-session -d -s fx -x 200 -y 12 "env WORK=$WORK SID=$SID TR=$TR bash -c '(exec -a claude bash $WORK/fake-claude); true'"
  timeout 5 wait-for --every 0.05 --until "ls '$WORK/.claude/sessions/'*.json" >/dev/null
  touch -d "@$old" "$TR"
  fx bash "$IC" "$@" 2>&1
}
keys() { cat "$WORK/keys" 2>/dev/null; }

out=$(case_)
is "dry run: would line" "$out" "would: fx idle 50 min, 150000 tokens → compact"
ev "dry run: no keys sent" '[ -z "$(keys)" ]'
ev "dry run: nothing logged" '[ ! -s "$WORK/ic.log" ]'

out=$(case_ --apply)
case "$out" in *"compacted: fx before=150000 after=12000"*) ok "apply: compacted, after read back";; *) nok "apply: compacted, after read back" "$out";; esac
is "apply: /compact typed once" "$(keys)" "/compact"
ev "apply: one log line with before and after" '[ "$(grep -c "compacted session=fx sid=11111111 idle=50m before=150000 after=12000" "$WORK/ic.log")" = 1 ]'
st=$(fx bash "$IC" status)
case "$st" in *"firings: 1, tokens saved: 138000"*) ok "status: firing and tokens saved";; *) nok "status: firing and tokens saved" "$st";; esac
case "$st" in *"last firing: "*"before=150000 after=12000"*) ok "status: last firing";; *) nok "status: last firing" "$st";; esac

out=$(COMPACTED=1 case_ --apply)
case "$out" in "skip already compacted since its last request: fx"*) ok "already compacted: skip";; *) nok "already compacted: skip" "$out";; esac
ev "already compacted: no keys" '[ -z "$(keys)" ]'

out=$(TYPED=hello case_ --apply)
case "$out" in "skip prompt box not empty (len=5): fx"*) ok "typed text: skip";; *) nok "typed text: skip" "$out";; esac
ev "typed text: no keys" '[ -z "$(keys)" ]'

out=$(ABOVE='✻ Working… (esc to interrupt)' case_ --apply)
case "$out" in "skip turn in progress: fx"*) ok "turn on screen: skip";; *) nok "turn on screen: skip" "$out";; esac

out=$(STATUS=busy case_ --apply)
case "$out" in "skip session busy, not idle: fx"*) ok "registry busy: skip";; *) nok "registry busy: skip" "$out";; esac

out=$(IDLE=30 case_ --apply)
case "$out" in "skip idle 30 min < 45: fx"*) ok "idle 30 min: skip";; *) nok "idle 30 min: skip" "$out";; esac

out=$(TOKENS=60000 case_ --apply)
case "$out" in "skip 60000 tokens < 100000: fx"*) ok "small context: skip";; *) nok "small context: skip" "$out";; esac

out=$(CONF='IDLE_COMPACT=off' case_ --apply)
case "$out" in "skip off (IDLE_COMPACT=off): fx"*) ok "config off: skip";; *) nok "config off: skip" "$out";; esac
ev "no skip sent keys or logged" '[ -z "$(keys)" ] && [ "$(wc -l <"$WORK/ic.log")" = 1 ]'

exit $bad
