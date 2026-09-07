#!/usr/bin/env bash
# D05 — a transient unit that exits non-zero, left failed for the trial to find.
set -euo pipefail
systemctl --user reset-failed pcbench-fail.service 2>/dev/null || true
systemd-run --user --unit pcbench-fail sh -c 'echo pcbench boom; exit 7' >/dev/null 2>&1 || true
sleep 0.5
systemctl --user is-failed --quiet pcbench-fail.service
