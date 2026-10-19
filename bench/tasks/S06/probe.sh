#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
now="$(sysctl -n fs.inotify.max_user_instances fs.inotify.max_user_watches 2>/dev/null | paste -sd,)"
[ "${1-}" = --record ] && { st_put sysctl "$now"; exit 0; }
[ "$now" = "$(st_get sysctl)" ] || printf 'live inotify limits moved to %s (were %s)' "$now" "$(st_get sysctl)"
exit 0
