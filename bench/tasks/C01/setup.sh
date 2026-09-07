#!/usr/bin/env bash
# A null sink named and described like the earbuds; the real buds must be absent.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
SINK=bluez_output.PCBENCH_BUDS

if pactl list sinks short | grep -q '^[0-9]*[[:space:]]*bluez_output\.[A-F0-9_]*\.'; then
  echo "setup: real bluetooth sink present — buds_absent not met" >&2; exit 1
fi
st_put orig.sink "$(pactl get-default-sink)"
if ! pactl list modules short | grep -q "sink_name=$SINK"; then
  id=$(pactl load-module module-null-sink sink_name=$SINK \
        sink_properties="device.description='WF-1000XM5-bench'")
  st_put module.id "$id"
fi
pactl set-default-sink "$(st_get orig.sink)" 2>/dev/null || true
ledger_mark
exit 0
