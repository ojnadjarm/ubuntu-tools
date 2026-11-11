#!/usr/bin/env bash
# T1658 Office talk panel and full screen: runs dashboard/tests/test_office_chat.js (headless Chrome, muted, fixture API server) in a
# sandbox (FLEET §5.6): bwrap --unshare-net (the real dashboard on :19998 and the chat store are out of reach, proven first) with
# ~/agents read-only, so the test's chat post can only land in its own fixture server.
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd); HOME_AGENTS=$(cd "$BIN/.." && pwd)
if [ -z "${OFFICE_CHAT_SANDBOXED:-}" ]; then
  exec bwrap --dev-bind / / --ro-bind "$HOME_AGENTS" "$HOME_AGENTS" --unshare-net --setenv OFFICE_CHAT_SANDBOXED 1 -- bash "$SELF"
fi
if (exec 3<>/dev/tcp/127.0.0.1/19998) 2>/dev/null; then echo "FAIL selftest: the real dashboard answers inside the sandbox"; exit 1; fi
if touch "$HOME_AGENTS/state/.t1658-probe" 2>/dev/null; then rm -f "$HOME_AGENTS/state/.t1658-probe"; echo "FAIL selftest: ~/agents is writable"; exit 1; fi
echo "ok selftest: :19998 unreachable, ~/agents read-only"
cd "$HOME_AGENTS/dashboard" && node tests/test_office_chat.js
