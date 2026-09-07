#!/usr/bin/env bash
set -euo pipefail
systemctl --user reset-failed pcbench-fail.service 2>/dev/null || true
if systemctl --user list-units 'pcbench-fail.service' --all --no-legend 2>/dev/null | grep -q pcbench-fail; then
  echo "pcbench-fail.service still listed" >&2
  exit 1
fi
exit 0
