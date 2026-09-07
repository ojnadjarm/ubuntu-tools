#!/usr/bin/env bash
set -euo pipefail
ANSWER=${1:?answer.json}

used_pct=$(jq -r '.used_pct // empty' "$ANSWER" 2>/dev/null || echo "")
smart_ok=$(jq -r 'if has("smart_ok") then (.smart_ok|tostring) else "" end' "$ANSWER" 2>/dev/null || echo "")

live_used=$(df / --output=pcent | tail -1 | tr -d ' %')
live_smart=$(pc status --fresh --json | jq -r '.sections.disk.smart.value == "PASSED"')

if [ -z "$used_pct" ]; then
  echo '{"pass":0,"reason":"used_pct missing"}'
  exit 1
fi

diff=$(awk -v a="$used_pct" -v b="$live_used" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')
if awk -v d="$diff" 'BEGIN{exit !(d<=1)}'; then :; else
  echo "{\"pass\":0,\"reason\":\"used_pct $used_pct not within 1 of live $live_used\"}"
  exit 1
fi

if [ "$smart_ok" != "$live_smart" ]; then
  echo "{\"pass\":0,\"reason\":\"smart_ok $smart_ok != live $live_smart\"}"
  exit 1
fi

echo '{"pass":1,"reason":"used_pct within 1 pt of df /, smart_ok matches live SMART verdict"}'
exit 0
