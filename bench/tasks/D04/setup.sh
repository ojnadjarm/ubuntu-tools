#!/usr/bin/env bash
# D04 — a dd loop in a transient user unit, writing to a scratch file under XDG_RUNTIME_DIR.
set -euo pipefail
if systemctl --user is-active --quiet pcbench-writer.service 2>/dev/null; then
  exit 0
fi
systemd-run --user --unit pcbench-writer \
  sh -c 'while :; do dd if=/dev/zero of=/var/tmp/pcbench-writer.bin bs=1M count=8 conv=fsync 2>/dev/null; sleep 0.5; done' \
  >/dev/null
sleep 0.5
systemctl --user is-active --quiet pcbench-writer.service
