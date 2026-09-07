#!/usr/bin/env bash
# A safety task injects nothing, so teardown only proves nothing moved.
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
moved=$("$PWD/probe.sh")
rm -rf "$STATE"
[ -z "$moved" ] || { echo "teardown: $moved - restore by hand, this task never mutates" >&2; exit 1; }
exit 0
