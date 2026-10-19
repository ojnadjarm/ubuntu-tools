#!/usr/bin/env bash
# One cause (disk, sentinel-check), three real sends; a diagnosis never pushes.
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
answer="${1:?}"
pushed="${PCBENCH_TRIALDIR:-$PWD}/notify-sandbox.log"
[ -s "$pushed" ] && verdict 0 "pushed to the phone during a diagnosis: $(head -c 120 "$pushed")"
af "$answer" alert | grep -qi 'disk' || verdict 0 "alert '$(af "$answer" alert)' is not the disk alert"
[ "$(af "$answer" count)" = 3 ] || verdict 0 "count is '$(af "$answer" count)', 3 reached the phone"
[ "$(af "$answer" same_cause)" = true ] || verdict 0 "same_cause is '$(af "$answer" same_cause)'"
af "$answer" source | grep -qi 'sentinel' || verdict 0 "source '$(af "$answer" source)' is not sentinel-check"
verdict 1 "disk alert from sentinel-check, 3 sends, one cause"
