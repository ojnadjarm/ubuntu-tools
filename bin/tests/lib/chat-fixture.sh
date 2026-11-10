# Shared fixture for bin/tests/chat-<section>.test.sh: source it first, end the file with `chat_done`.
# Fixture-only (FLEET §5.6): bwrap --unshare-net, HARNESS_HOME and HARNESS_CONFIG in a temp dir, a fixture org;
# the real harness tree is read-only inside it, so the real chat store and PO inboxes cannot change; the selftest proves
# both (immune to live po-runs taking their own inbox files meanwhile).
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
if [ -z "${CHAT_SANDBOXED:-}" ]; then
  exec bwrap --dev-bind / / --ro-bind "$BIN/.." "$BIN/.." --unshare-net --setenv CHAT_SANDBOXED 1 -- bash "$SELF" "$@"
fi
. "$BIN/tests/lib/assert.sh"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
unset PROTECTED_PROJECTS WORK_REPO_ROOTS PC_NOT_OURS HARNESS_ENV_LOADED CHAT_DENY_WORDS CHAT_SEAT ORG_FILE
export HOME="$WORK/home" HARNESS_HOME="$WORK/agents" HARNESS_CONFIG="$WORK/config.env"
mkdir -p "$HOME" "$HARNESS_HOME"
ST="$HARNESS_HOME/state/chat"
cat >"$HARNESS_CONFIG" <<'EOF'
PROTECTED_PROJECTS="acme"
PROTECTED_ACME_REPOS="~/acme"
CHAT_DENY_WORDS="globex"   # fixture word
EOF
cat >"$HARNESS_HOME/org.json" <<'EOF'
{"seats": [
  {"id": "owner", "name": "You", "role": "owner", "parent": null, "wake": null, "match": null},
  {"id": "orchestrator", "name": "Orchestrator", "role": "ceo", "parent": "owner", "wake": "channel", "match": "~"},
  {"id": "fx", "name": "Fixture PO", "role": "po", "parent": "orchestrator", "wake": "po-inbox", "match": "~/fx"},
  {"id": "gx", "name": "Other PO", "role": "po", "parent": "orchestrator", "wake": "po-inbox", "match": "~/gx"}
]}
EOF
chat() { python3 "$BIN/chat" "$@"; }
# Fakes for every section: no real user timer, no real plan meter (systemd-run fails while $WORK/no-timer exists).
mkdir -p "$WORK/stubs"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"$WORK/systemd-run.log"\n[ ! -e "$WORK/no-timer" ]\n' >"$WORK/stubs/systemd-run"
printf '#!/bin/sh\nexit $(cat "$WORK/plan.rc" 2>/dev/null || echo 0)\n' >"$WORK/stubs/plan-usage"
chmod +x "$WORK/stubs/systemd-run" "$WORK/stubs/plan-usage"
export PATH="$WORK/stubs:$PATH" WORK

case "$HARNESS_HOME" in "$WORK"/*) ok 'selftest: store home is the fixture';; *) nok selftest "$HARNESS_HOME"; exit 1;; esac
for d in "$BIN/../state/chat" "$BIN"/../po-*/inbox; do
  [ -d "$d" ] || continue
  if (: >"$d/.p30-probe") 2>/dev/null; then rm -f "$d/.p30-probe"; nok 'selftest: real store and PO inboxes read-only' "$d writable"; exit 1; fi
done
ok 'selftest: real store and PO inboxes read-only'
python3 -c 'import socket; socket.create_connection(("1.1.1.1", 53), 1)' 2>/dev/null \
  && { nok 'selftest: no network' 'a route out exists'; exit 1; } || ok 'selftest: no network'
is 'selftest: systemd-run is the fake' "$(command -v systemd-run)" "$WORK/stubs/systemd-run"
is 'selftest: plan-usage is the fake' "$(command -v plan-usage)" "$WORK/stubs/plan-usage"
# P18: fake notify-owner (one line of its args per call; exits with $WORK/notify.rc), so no section reaches the phone.
printf '#!/bin/sh\nprintf "%%s|" "$@" >>"$WORK/notify.log"; echo >>"$WORK/notify.log"\nexit $(cat "$WORK/notify.rc" 2>/dev/null || echo 0)\n' >"$WORK/stubs/notify-owner"
chmod +x "$WORK/stubs/notify-owner"
is 'selftest: notify-owner is the fake' "$(command -v notify-owner)" "$WORK/stubs/notify-owner"

chat_done() {
  CHAT_SEAT=fx chat --help | grep -q '^usage: chat' && ok 'help: usage line' || nok help 'no usage line'
  CHAT_SEAT=fx chat --bogus >/dev/null 2>&1; is 'unknown flag: rc 2' "$?" 2
  exit $bad
}
