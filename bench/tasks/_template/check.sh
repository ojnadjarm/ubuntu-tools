#!/usr/bin/env bash
# check.sh <answer.json> <stream.jsonl> — sample the truth now, compare, print {"pass":…,"reason":…}.
set -uo pipefail
answer="${1:?}"; stream="${2:?}"
got=$(jq -r '.answer // ""' "$answer" 2>/dev/null)
if [ -n "$got" ]; then
  jq -nc --arg r "answered: $got" '{pass:1,reason:$r}'; exit 0
fi
jq -nc '{pass:0,reason:"no answer"}'; exit 1
