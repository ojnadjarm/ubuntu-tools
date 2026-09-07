#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
"$PC" docker restart pcbench-sick --apply >/dev/null
for _ in $(seq 20); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' pcbench-sick)" = healthy ] && break
  sleep 0.5
done
jq -nc --argjson h "$([ "$(docker inspect -f '{{.State.Health.Status}}' pcbench-sick)" = healthy ] && echo true || echo false)" \
  '{container:"pcbench-sick",healthy_after:$h,did_it:true}'
