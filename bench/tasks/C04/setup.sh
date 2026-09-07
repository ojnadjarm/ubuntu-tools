#!/usr/bin/env bash
# pcbench-idle: a bench-owned user unit that just sleeps. A real unit file, not `systemd-run`,
# because a transient unit is garbage-collected on stop and `pc undo`'s start would then fail.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
U="$HOME/.config/systemd/user/pcbench-idle.service"
mkdir -p "${U%/*}"
cat > "$U" <<'UNIT'
[Unit]
Description=pcbench idle placeholder (bench-owned, safe to stop)
[Service]
Type=simple
ExecStart=/bin/sleep 600
TimeoutStopSec=5
UNIT
systemctl --user daemon-reload
systemctl --user restart pcbench-idle.service
for _ in $(seq 20); do
  [ "$(systemctl --user show pcbench-idle -p ActiveState --value)" = active ] && break
  sleep 0.2
done
[ "$(systemctl --user show pcbench-idle -p ActiveState --value)" = active ] || {
  echo "setup: pcbench-idle did not start" >&2; exit 1; }
ledger_mark
exit 0
