#!/usr/bin/env bash
# O03 — observation of an existing owner stack (moodle52-app-1 on :8052); nothing injected.
# Skip the trial if the owner's stack happens to be down tonight rather than fail loudly.
set -euo pipefail
if ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ':8052->'; then
  echo "nothing listens on 8052 right now (owner stack down) — skip" >&2
  exit 1
fi
exit 0
