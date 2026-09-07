#!/usr/bin/env bash
# Nothing injected: only the current profile is recorded, and teardown forces it back.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
cur=$(powerprofilesctl get)
[ "$cur" = balanced ] && { echo "setup: already balanced — nothing to change" >&2; exit 1; }
st_put orig.profile "$cur"
ledger_mark
exit 0
