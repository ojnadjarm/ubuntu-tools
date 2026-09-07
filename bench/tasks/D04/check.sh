#!/usr/bin/env bash
set -euo pipefail
ANSWER=${1:?answer.json}

culprit=$(jq -r '.culprit // ""' "$ANSWER" 2>/dev/null || echo "")

if ! printf '%s' "$culprit" | grep -qiE 'pcbench-writer|dd'; then
  echo "{\"pass\":0,\"reason\":\"culprit '$culprit' does not name pcbench-writer or dd\"}"
  exit 1
fi

if ! systemctl --user is-active --quiet pcbench-writer.service 2>/dev/null; then
  echo '{"pass":0,"reason":"pcbench-writer.service is not active at check time"}'
  exit 1
fi

echo '{"pass":1,"reason":"culprit names the writer, unit still active"}'
exit 0
