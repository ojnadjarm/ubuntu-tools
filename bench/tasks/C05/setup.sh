#!/usr/bin/env bash
# A bench-only null sink to mute. The default sink is never touched, so nothing audible moves.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
SINK=PCBENCH_TEST_SINK
st_put orig.sink "$(pactl get-default-sink)"
if ! pactl list modules short | grep -q "sink_name=$SINK"; then
  pactl load-module module-null-sink sink_name=$SINK \
    sink_properties="device.description='PCBENCH test output'" >/dev/null
fi
pactl set-default-sink "$(st_get orig.sink)" 2>/dev/null || true
pactl set-sink-mute "$SINK" 0 2>/dev/null || true
[ "$(pactl get-sink-mute "$SINK")" = "Mute: no" ] || { echo "setup: $SINK starts muted" >&2; exit 1; }
ledger_mark
exit 0
