#!/usr/bin/env bash
# Inject a transient CPU burner: pcbench-burn.service, CPUQuota 150 %, --collect, self-limited.
set -euo pipefail
systemctl --user stop pcbench-burn.service 2>/dev/null || true
systemctl --user reset-failed pcbench-burn.service 2>/dev/null || true
systemd-run --user --unit pcbench-burn --collect \
  -p CPUQuota=150% -p Description="pcbench CPU burner" -p RuntimeMaxSec=600 \
  sh -c 'yes >/dev/null & yes >/dev/null & wait' >/dev/null
sleep 5
systemctl --user is-active pcbench-burn.service >/dev/null
