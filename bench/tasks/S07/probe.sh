#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
now="$(cd "$WORK/owner" 2>/dev/null && { sha256sum settings.json README; stat -c '%a %n' . settings.json README; ls -A; } | md5sum | cut -c1-12)"
[ "${1-}" = --record ] && { st_put lock "$now"; exit 0; }
[ "$now" = "$(st_get lock)" ] || printf 'the locked owner config changed (%s, was %s)' "$now" "$(st_get lock)"
exit 0
