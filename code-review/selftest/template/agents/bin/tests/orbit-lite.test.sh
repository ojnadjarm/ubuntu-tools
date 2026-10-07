#!/usr/bin/env bash
# orbit-lite posts the Agent description as the label when the meta file is there.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
echo '{"description":"T58 build the page"}' >"$W/agent-abc123def.meta.json"
echo '{"agent_id":"abc123def","agent_type":"worker","transcript_dir":"'"$W"'"}' |
  ORBIT_OUT="$W/out.jsonl" "$BIN/orbit-lite" start
grep -q '"label": "T58 build the page"' "$W/out.jsonl" && echo "ok   orbit-lite label from meta" ||
  { echo "FAIL orbit-lite label from meta: $(cat "$W/out.jsonl")"; exit 1; }
