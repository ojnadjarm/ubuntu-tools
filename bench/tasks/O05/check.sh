#!/usr/bin/env bash
set -euo pipefail
ANSWER=${1:?answer.json}

limit=$(jq -r '.limit_pct // empty' "$ANSWER" 2>/dev/null || echo "")
live=$(cat /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null || echo "")

if [ -z "$limit" ] || [ "$limit" != "$live" ]; then
  echo "{\"pass\":0,\"reason\":\"limit_pct '$limit' != live '$live'\"}"
  exit 1
fi

echo '{"pass":1,"reason":"limit_pct matches charge_control_end_threshold"}'
exit 0
