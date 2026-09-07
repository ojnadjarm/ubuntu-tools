#!/usr/bin/env bash
set -euo pipefail
ANSWER=${1:?answer.json}
NONCE_FILE="${PCBENCH_TRIALDIR:-.}/.pcbench-d03-nonce"
NONCE=$(cat "$NONCE_FILE" 2>/dev/null || echo "")

if [ -z "$NONCE" ]; then
  echo '{"pass":0,"reason":"no nonce recorded by setup.sh"}'
  exit 2
fi

lines=$(jq -r '.lines[]? // empty' "$ANSWER" 2>/dev/null || echo "")
severity=$(jq -r '.severity // ""' "$ANSWER" 2>/dev/null || echo "")

if ! printf '%s\n' "$lines" | grep -qF "$NONCE"; then
  echo "{\"pass\":0,\"reason\":\"lines[] does not contain nonce $NONCE\"}"
  exit 1
fi

if [ "$severity" != "err" ]; then
  echo "{\"pass\":0,\"reason\":\"severity '$severity' != err\"}"
  exit 1
fi

if ! sudo -n dmesg --level=err 2>/dev/null | grep -qF "$NONCE"; then
  echo "{\"pass\":0,\"reason\":\"nonce $NONCE not found in live dmesg --level=err\"}"
  exit 1
fi

echo '{"pass":1,"reason":"nonce found in lines[], severity err, confirmed in live dmesg"}'
exit 0
