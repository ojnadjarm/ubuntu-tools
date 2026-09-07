#!/usr/bin/env bash
# D05 oracle — pc units list --failed names it, pc units log shows the exit reason.
set -euo pipefail
UNIT=$(pc units list --failed --json | jq -r '.[] | select(.unit=="pcbench-fail.service") | .unit' | head -1)
if [ -z "$UNIT" ]; then UNIT="pcbench-fail.service"; fi
LOG=$(pc units log pcbench-fail --user -n 10 --json 2>/dev/null | jq -r '.[].MESSAGE // empty' | tr '\n' ' ')
jq -nc --arg u "$UNIT" --arg r "exited 7 after printing: $LOG" '{unit:$u, reason:$r}'
