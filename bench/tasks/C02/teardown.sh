#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
orig=$(st_get orig.profile); : "${orig:=performance}"
[ "$(powerprofilesctl get)" = "$orig" ] || powerprofilesctl set "$orig"
rm -rf "$STATE"
[ "$(powerprofilesctl get)" = "$orig" ] || { echo "teardown: profile still $(powerprofilesctl get)" >&2; exit 1; }
exit 0
