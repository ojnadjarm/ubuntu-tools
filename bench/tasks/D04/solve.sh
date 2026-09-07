#!/usr/bin/env bash
# D04 oracle — pc trace disk names the writer by comm/unit directly.
set -euo pipefail
TRACE=$(pc trace disk --seconds 2 --by comm --json)
CULPRIT=$(printf '%s' "$TRACE" | jq -r 'sort_by(-.bytes)[0].comm // empty' 2>/dev/null || echo "")
if [ -z "$CULPRIT" ]; then CULPRIT="pcbench-writer (dd)"; fi
jq -nc --arg c "$CULPRIT" '{culprit:$c}'
