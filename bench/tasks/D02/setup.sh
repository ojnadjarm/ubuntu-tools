#!/usr/bin/env bash
# D02 — a bench-only container with a failing health check, never an owner service.
set -euo pipefail
if docker inspect pcbench-sick >/dev/null 2>&1; then
  exit 0
fi
docker run -d --name pcbench-sick \
  --health-cmd false --health-interval 2s --health-retries 1 \
  alpine sleep 600 >/dev/null
