#!/usr/bin/env bash
# D03 — a per-trial nonce kernel-log line via /dev/kmsg, priority 3 (err).
set -euo pipefail
NONCE="pcbench$RANDOM$RANDOM"
NONCE_FILE="${PCBENCH_TRIALDIR:-.}/.pcbench-d03-nonce"
sudo -n sh -c "printf '<3>pcbench: nonce %s\n' '$NONCE' > /dev/kmsg"
printf '%s' "$NONCE" > "$NONCE_FILE"
