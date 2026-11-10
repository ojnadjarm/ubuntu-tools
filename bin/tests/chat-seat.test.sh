#!/usr/bin/env bash
# T1551 bin/chat seat from the cwd: with no $CHAT_SEAT a caller in a seat's folder (or below) is that seat; a pull seat
# whose folder is in its protected folder keeps #harness + direct messages, and nothing opens, lists or stats that folder.
# Fixture-only (FLEET §5.6): bwrap --unshare-net, fake HOME, HARNESS_HOME and HARNESS_CONFIG in a temp dir.
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
if [ -z "${CHAT_SANDBOXED:-}" ]; then
  exec bwrap --dev-bind / / --ro-bind "$BIN/.." "$BIN/.." --unshare-net --setenv CHAT_SANDBOXED 1 -- bash "$SELF" "$@"
fi
. "$BIN/tests/lib/assert.sh"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
unset PROTECTED_PROJECTS WORK_REPO_ROOTS PC_NOT_OURS HARNESS_ENV_LOADED CHAT_DENY_WORDS CHAT_SEAT ORG_FILE CLAUDE_SESSIONS_DIR
export HOME="$WORK/home" HARNESS_HOME="$WORK/agents" HARNESS_CONFIG="$WORK/config.env" GUIDES_DIR="$WORK/no-guides"
ACME="$HOME/acme/moodle"; mkdir -p "$HARNESS_HOME" "$GUIDES_DIR" "$ACME/local/x" "$HOME/fx/sub" "$WORK/stubs"
ST="$HARNESS_HOME/state/chat"
printf 'PROTECTED_PROJECTS="acme"\nPROTECTED_ACME_PATHS="~/acme"\n' >"$HARNESS_CONFIG"
cat >"$HARNESS_HOME/org.json" <<'EOF'
{"seats": [
  {"id": "owner", "name": "You", "role": "owner", "parent": null, "wake": null, "match": null},
  {"id": "orchestrator", "name": "Orchestrator", "role": "ceo", "parent": "owner", "wake": "channel", "match": "~"},
  {"id": "fx", "name": "Fixture PO", "role": "po", "parent": "orchestrator", "wake": "po-inbox", "match": "~/fx"},
  {"id": "acme", "name": "Acme seat", "role": "po", "parent": "orchestrator", "wake": "pull", "match": "~/acme/moodle"}
]}
EOF
for s in systemd-run notify-owner plan-usage; do printf '#!/bin/sh\nexit 0\n' >"$WORK/stubs/$s"; chmod +x "$WORK/stubs/$s"; done
export PATH="$WORK/stubs:$PATH"
chat() { python3 "$BIN/chat" "$@"; }

case "$HARNESS_HOME" in "$WORK"/*) ok 'selftest: store home is the fixture';; *) nok selftest "$HARNESS_HOME"; exit 1;; esac
python3 -c 'import socket; socket.create_connection(("1.1.1.1", 53), 1)' 2>/dev/null \
  && { nok 'selftest: no network' 'a route out exists'; exit 1; } || ok 'selftest: no network'
is 'selftest: systemd-run is the fake' "$(command -v systemd-run)" "$WORK/stubs/systemd-run"

from() { python3 -c "import json, glob; print(json.loads(open(sorted(glob.glob('$ST/$1.*.jsonl'))[0]).readlines()[-1])['from'])"; }
out=$(cd "$HOME/fx/sub" && chat post harness 'from the fx folder'); rc=$?
is 'cwd: below a po folder posts as that seat' "$rc $(from harness)" '0 fx'
out=$(cd "$ACME/local/x" && chat post harness 'from the seat folder'); rc=$?
is 'cwd: below the pull seat folder posts as the pull seat' "$rc $(from harness)" '0 acme'
out=$(cd "$ACME" && chat read org 2>&1); rc=$?
is 'cwd: the pull seat keeps #harness + direct messages only (rc 2)' "$rc $out" '2 chat: acme has #harness and direct messages only'
out=$(cd "$ACME" && CHAT_SEAT=fx chat post harness 'env wins'); rc=$?
is 'cwd: $CHAT_SEAT wins over the cwd' "$rc $(from harness)" '0 fx'
out=$(cd "$HOME" && chat read 2>&1); rc=$?
is 'cwd: home (the ~ catch-all) is no seat' "$rc $out" '2 chat: CHAT_SEAT is not set and no seat folder holds the cwd'
out=$(cd "$HOME/acme" && chat read 2>&1); rc=$?
is 'cwd: above the seat folder is no seat' "$rc" 2

# Proof: the pull seat's flow from inside its folder under strace: no open, list or stat there.
CHAT_SEAT=fx chat post @acme 'ping' >/dev/null
(cd "$ACME/local/x" && for args in 'read --unread' 'post harness is-the-build-green'; do
  strace -f -y -qq -o "$WORK/seat.trace.${args%% *}" -e trace=%file,getdents64,fchdir python3 "$BIN/chat" $args; done) >"$WORK/seat.out" 2>&1
cat "$WORK"/seat.trace.* >"$WORK/seat.trace"
ev 'proof: read --unread as the cwd seat shows the direct message' 'grep -q "fx -> acme: ping" "$WORK/seat.out"'
ev 'proof selftest: the trace saw the store and the cwd readlink' \
   'grep -q "$ST" "$WORK/seat.trace" && grep -q "readlink(\"/proc/self/cwd\"" "$WORK/seat.trace"'
is 'proof: no open, list or stat of the protected folder, no container runtime' \
   "$(python3 "$BIN/tests/lib/no_touch.py" "$WORK/seat.trace" "$HOME/acme")" ''
(cd "$ACME" && strace -f -y -qq -o "$WORK/bad.trace" -e trace=%file,getdents64,fchdir python3 -c "import os; os.stat('local')")
ev 'selftest: no_touch flags a relative stat inside the protected cwd' \
   '[ -n "$(python3 "$BIN/tests/lib/no_touch.py" "$WORK/bad.trace" "$HOME/acme")" ]'
exit $bad
