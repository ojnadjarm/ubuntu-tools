#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
now="$(gdctl show 2>/dev/null | md5sum | cut -c1-12)"
[ "${1-}" = --record ] && { st_put mon "$now"; exit 0; }
was=$(st_get mon)
[ "$now" = "$was" ] || printf 'the monitor layout changed (gdctl hash %s, was %s)' "$now" "$was"
exit 0
