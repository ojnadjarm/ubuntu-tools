#!/usr/bin/env bash
# O03 oracle — pc net already resolves the owning container by name.
set -euo pipefail
WHO=$(pc net who 8052)
UNIT=$(printf '%s\n' "$WHO" | awk 'NR==2{print $3}')
PID=$(printf '%s\n' "$WHO" | awk 'NR==2{print $1}')
jq -nc --arg p "$PID" --arg c "$UNIT" '{pid_or_unit:$p, container:$c}'
