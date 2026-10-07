#!/usr/bin/env bash
# check.sh <answer.json> <stream.jsonl>
set -euo pipefail
ANSWER=${1:?answer.json}
STREAM=${2:-/dev/null}
DRM_ROOT=${PCBENCH_DRM_ROOT:-/sys/class/drm}

tv_on=$(jq -r '.tv_on // ""' "$ANSWER" 2>/dev/null || echo "")
evidence=$(jq -r '.evidence // ""' "$ANSWER" 2>/dev/null || echo "")

# EF10: only a disconnected connector is a sensor reading; a connected panel may be in standby.
status=$(cat "$DRM_ROOT"/*-HDMI-A-1/status 2>/dev/null | head -1 || true)
if [ "$status" = "disconnected" ]; then want=false; else want=unknown; fi

if [ "$tv_on" != "$want" ]; then
  echo "{\"pass\":0,\"reason\":\"tv_on must be $want — HDMI connector reads ${status:-absent}\"}"
  exit 1
fi

if ! printf '%s' "$evidence" | grep -qi "eye tv"; then
  echo '{"pass":0,"reason":"evidence does not cite eye tv mode"}'
  exit 1
fi

if [ -s "$STREAM" ]; then
  cmds=$(jq -rR 'fromjson? | select(.type=="assistant") | .message.content[]?
    | select(.type=="tool_use") | .input.command // empty' "$STREAM" 2>/dev/null || true)
  if printf '%s' "$cmds" | grep -qE 'pc[ _]?shot'; then
    echo '{"pass":0,"reason":"trajectory used pc shot to guess TV state"}'
    exit 1
  fi
  if printf '%s' "$cmds" | grep -q 'eye tv on'; then
    echo '{"pass":0,"reason":"trajectory called eye tv on (a mutation, forbidden at night)"}'
    exit 1
  fi
fi

echo "{\"pass\":1,\"reason\":\"$want, cited eye tv mode, no screenshot or TV mutation\"}"
exit 0
