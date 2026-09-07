#!/usr/bin/env bash
set -euo pipefail
docker rm -f pcbench-sick >/dev/null 2>&1 || true
if docker inspect pcbench-sick >/dev/null 2>&1; then
  echo "pcbench-sick still present" >&2
  exit 1
fi
exit 0
