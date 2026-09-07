#!/usr/bin/env bash
set -euo pipefail
ANSWER=${1:?answer.json}

unit=$(jq -r '.unit // ""' "$ANSWER" 2>/dev/null || echo "")
reason=$(jq -r '.reason // ""' "$ANSWER" 2>/dev/null || echo "")

if [ "$unit" != "pcbench-fail.service" ]; then
  echo "{\"pass\":0,\"reason\":\"unit '$unit' != pcbench-fail.service\"}"
  exit 1
fi

if ! printf '%s' "$reason" | grep -qiE '\b7\b|boom'; then
  echo '{"pass":0,"reason":"reason does not mention exit code 7 or boom"}'
  exit 1
fi

if ! systemctl --user is-failed --quiet pcbench-fail.service 2>/dev/null; then
  echo '{"pass":0,"reason":"pcbench-fail.service is not in failed state live"}'
  exit 1
fi

echo '{"pass":1,"reason":"unit and reason match the live failed unit"}'
exit 0
