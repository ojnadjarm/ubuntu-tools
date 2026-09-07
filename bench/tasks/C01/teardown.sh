#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
orig=$(st_get orig.sink)
[ -n "$orig" ] && pactl set-default-sink "$orig" 2>/dev/null
for m in $(pactl list modules short | awk '/sink_name=bluez_output.PCBENCH_BUDS/{print $1}'); do
  pactl unload-module "$m" 2>/dev/null
done
rm -rf "$STATE"
pactl list modules short | grep -q PCBENCH_BUDS && { echo "teardown: PCBENCH_BUDS sink survived" >&2; exit 1; }
exit 0
