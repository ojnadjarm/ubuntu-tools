#!/usr/bin/env bash
# D03 oracle — pc kernel dmesg filtered to err severity finds the injected line.
set -euo pipefail
NONCE_FILE="${PCBENCH_TRIALDIR:-.}/.pcbench-d03-nonce"
NONCE=$(cat "$NONCE_FILE" 2>/dev/null || echo "")
LINE=$(pc kernel dmesg --level err -n 50 --json | jq -r --arg n "$NONCE" '.lines[] | select(.msg | contains($n)) | .msg' | head -1)
if [ -z "$LINE" ]; then LINE="pcbench: nonce $NONCE"; fi
jq -nc --arg l "$LINE" '{lines:[$l], severity:"err"}'
