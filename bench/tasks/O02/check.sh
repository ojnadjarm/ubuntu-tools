#!/usr/bin/env bash
set -euo pipefail
ANSWER=${1:?answer.json}

sink=$(jq -r '.sink // ""' "$ANSWER" 2>/dev/null || echo "")
is_buds=$(jq -r 'if has("is_buds") then (.is_buds|tostring) else "" end' "$ANSWER" 2>/dev/null || echo "")

live=$(pactl get-default-sink 2>/dev/null || echo "")
live_buds=false
case "$live" in bluez_output.*) live_buds=true ;; esac

if [ "$sink" != "$live" ]; then
  echo "{\"pass\":0,\"reason\":\"sink '$sink' != live default sink '$live'\"}"
  exit 1
fi

if [ "$is_buds" != "$live_buds" ]; then
  echo "{\"pass\":0,\"reason\":\"is_buds '$is_buds' != live '$live_buds'\"}"
  exit 1
fi

echo '{"pass":1,"reason":"sink and is_buds match live default sink"}'
exit 0
