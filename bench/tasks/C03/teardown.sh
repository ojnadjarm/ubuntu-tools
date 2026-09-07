#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
docker rm -f pcbench-sick >/dev/null 2>&1
rm -rf "$PWD/flag" "$STATE"
docker ps -a --format '{{.Names}}' | grep -qx pcbench-sick && { echo "teardown: pcbench-sick survived" >&2; exit 1; }
exit 0
