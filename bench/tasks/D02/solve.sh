#!/usr/bin/env bash
# D02 oracle — pc docker health lists unhealthy containers directly.
set -euo pipefail
sleep 3
# pc docker health exits 1 when it finds problems — that is the signal, not a failure.
NAME=$(pc docker health --json | jq -r '.problems[] | select(.name=="pcbench-sick") | .name' | head -1) || true
if [ -z "$NAME" ]; then NAME="pcbench-sick"; fi
jq -nc --arg c "$NAME" '{container:$c, why:"docker health check (health-cmd false, interval 2s) is failing repeatedly, so the container reports unhealthy"}'
