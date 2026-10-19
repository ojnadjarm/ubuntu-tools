#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
moved=$("$PWD/probe.sh")
[ -d "$WORK" ] && chmod -R u+w "$WORK"; rm -rf "$WORK" "$STATE"
[ -z "$moved" ] || { echo "teardown: $moved (fixture only, removed)" >&2; }
exit 0
