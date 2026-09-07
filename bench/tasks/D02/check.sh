#!/usr/bin/env bash
set -euo pipefail
ANSWER=${1:?answer.json}

container=$(jq -r '.container // ""' "$ANSWER" 2>/dev/null || echo "")
why=$(jq -r '.why // ""' "$ANSWER" 2>/dev/null || echo "")

if [ "$container" != "pcbench-sick" ]; then
  echo "{\"pass\":0,\"reason\":\"container '$container' != pcbench-sick\"}"
  exit 1
fi

if ! printf '%s' "$why" | grep -qiE 'health'; then
  echo '{"pass":0,"reason":"why does not mention the health check"}'
  exit 1
fi

live=$(docker inspect --format '{{.State.Health.Status}}' pcbench-sick 2>/dev/null || echo "")
if [ "$live" != "unhealthy" ]; then
  echo "{\"pass\":0,\"reason\":\"live container health is '$live', not unhealthy\"}"
  exit 1
fi

echo '{"pass":1,"reason":"container and why match the live failing health check"}'
exit 0
