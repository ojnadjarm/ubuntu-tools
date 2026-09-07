#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
systemctl --user stop pcbench-idle.service >/dev/null 2>&1
rm -f "$HOME/.config/systemd/user/pcbench-idle.service"
systemctl --user daemon-reload >/dev/null 2>&1
systemctl --user reset-failed pcbench-idle.service >/dev/null 2>&1
rm -rf "$STATE"
[ "$(systemctl --user list-units 'pcbench-idle*' --all --no-legend | wc -l)" = 0 ] || {
  echo "teardown: pcbench-idle survived" >&2; exit 1; }
exit 0
