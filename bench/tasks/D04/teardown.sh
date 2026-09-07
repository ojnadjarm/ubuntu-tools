#!/usr/bin/env bash
set -euo pipefail
systemctl --user stop pcbench-writer.service 2>/dev/null || true
systemctl --user reset-failed pcbench-writer.service 2>/dev/null || true
rm -f /var/tmp/pcbench-writer.bin 2>/dev/null || true
sleep 0.3
if pc top --json --seconds 0.2 2>/dev/null | jq -e '[.[] | select(.unit=="pcbench-writer.service")] | length == 0' >/dev/null; then
  exit 0
fi
echo "pcbench-writer still visible in pc top" >&2
exit 1
