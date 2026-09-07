#!/usr/bin/env bash
# Idempotent: the burner is gone whatever the agent did. Exit 1 if it survives.
set -uo pipefail
systemctl --user stop pcbench-burn.service 2>/dev/null
systemctl --user reset-failed pcbench-burn.service 2>/dev/null
for i in 1 2 3 4 5; do
  systemctl --user is-active pcbench-burn.service >/dev/null 2>&1 || exit 0
  sleep 0.4
done
echo "pcbench-burn.service survived teardown" >&2
exit 1
