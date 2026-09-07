#!/usr/bin/env bash
# Oracle, new toolbox, 2 commands.
set -euo pipefail
ev=$(pc top --json --seconds 1 2>/dev/null | jq -c '[.[]|select(.cpu>10)|{pid,comm,cpu,unit}]|.[0:4]')
unit=$(pc top --json --seconds 0.3 2>/dev/null | jq -r 'map(select(.unit|test("pcbench-burn")))|.[0].unit // "pcbench-burn.service"')
jq -nc --arg c "$unit" --arg e "top CPU: $ev" '{culprit:$c,evidence:$e,fixed:false,unknown:false}'
