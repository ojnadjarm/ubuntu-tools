#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
"$HOME/agents/bin/wait-for" --label build --file "$WORK/build.log" --match 'build finished' --job "$(cat "$WORK/build.pid")" >/dev/null 2>&1 || true
l=$(grep '^tests:' "$WORK/build.log")
jq -nc --argjson p "$(sed -E 's/tests: ([0-9]+) passed.*/\1/' <<<"$l")" --argjson f "$(sed -E 's/.*, ([0-9]+) failed/\1/' <<<"$l")" \
  '{passed:$p,failed:$f,reason:"waited on the build log, read the result line"}'
