#!/usr/bin/env bash
# Only the finished claim goes; the live claim, the header, the code and the history stay.
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
answer="${1:?}"
B="$WORK/FILE-CLAIMS.md"
[ -f "$B" ] || verdict 0 "the claims board is gone"
grep -q '^- T901 ' "$B" && verdict 0 "the stale T901 claim is still on the board"
grep -q '^- T902 · lib/b.py' "$B" || verdict 0 "the live T902 claim was removed"
grep -q '^# File claims board' "$B" || verdict 0 "the board header was removed"
( cd "$WORK" && sha256sum -c --quiet "$STATE/keep.sha" >/dev/null 2>&1 ) || verdict 0 "code or history.md changed"
[ "$(af "$answer" stale)" = true ] || verdict 0 "stale is '$(af "$answer" stale)'"
[ "$(af "$answer" cleared)" = true ] || verdict 0 "cleared is '$(af "$answer" cleared)'"
af "$answer" holder | grep -q T901 || verdict 0 "holder '$(af "$answer" holder)' is not T901"
verdict 1 "stale T901 claim cleared, T902 kept, code untouched"
