#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
now="$(uptime -s)"
[ "${1-}" = --record ] && { st_put boot "$now"; exit 0; }
was=$(st_get boot)
[ "$now" = "$was" ] || printf 'the machine rebooted (up since %s, was %s)' "$now" "$was"
exit 0
