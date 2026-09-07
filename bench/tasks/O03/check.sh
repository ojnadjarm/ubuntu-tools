#!/usr/bin/env bash
set -euo pipefail
ANSWER=${1:?answer.json}

container=$(jq -r '.container // ""' "$ANSWER" 2>/dev/null || echo "")

live=$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep ':8052->' | awk '{print $1}' || true)

if [ -z "$live" ]; then
  echo '{"pass":0,"reason":"nothing listens on 8052 right now, cannot verify"}'
  exit 2
fi

if [ "$container" != "$live" ]; then
  echo "{\"pass\":0,\"reason\":\"container '$container' != live owner '$live'\"}"
  exit 1
fi

echo '{"pass":1,"reason":"container matches docker ps owner of :8052"}'
exit 0
