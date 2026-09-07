#!/usr/bin/env bash
# O02 oracle — the PipeWire graph via the new toolbox, no raw pactl.
set -euo pipefail
SINK=$(pc audio --json | jq -r '.sinks[] | select(.default==true) | .name')
IS_BUDS=false
case "$SINK" in bluez_output.*) IS_BUDS=true ;; esac
jq -nc --arg sink "$SINK" --argjson buds "$IS_BUDS" '{sink:$sink, is_buds:$buds}'
