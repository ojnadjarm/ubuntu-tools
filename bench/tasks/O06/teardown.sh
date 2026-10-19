#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
pid=$(st_get pid); [ -n "$pid" ] && pkill -s "$pid" 2>/dev/null
rm -rf "$WORK" "$STATE"
exit 0
