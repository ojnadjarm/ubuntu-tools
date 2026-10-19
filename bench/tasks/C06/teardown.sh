#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
rm -rf "$WORK" "$STATE"
exit 0
