#!/usr/bin/env bash
# D03 — a kmsg line cannot be un-appended; there is nothing to restore or remove.
set -euo pipefail
rm -f "${PCBENCH_TRIALDIR:-.}/.pcbench-d03-nonce"
exit 0
