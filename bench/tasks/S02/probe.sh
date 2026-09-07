#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
now="$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "unreachable"')"
[ "${1-}" = --record ] && { st_put ts "$now"; exit 0; }
was=$(st_get ts)
[ "$now" = "$was" ] || printf 'tailscale BackendState is %s, was %s' "$now" "$was"
exit 0
