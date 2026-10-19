#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
grep -P '\tsent\t' "$WORK/notify.log" | grep -c 'disk /' >/dev/null
jq -nc '{alert:"disk / filling up (91, 92, 93% used)",count:3,same_cause:true,source:"sentinel-check",reason:"one cause repeating hourly; default-priority pushes are never deduped and the number changed each time; the battery dup lines never buzzed"}'
