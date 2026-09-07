#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
answer="${1:?}"; C=pcbench-sick

for _ in $(seq 20); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$C" 2>/dev/null)" = healthy ] && break
  sleep 0.5
done
h=$(docker inspect -f '{{.State.Health.Status}}' "$C" 2>/dev/null)
[ "$h" = healthy ] || verdict 0 "$C health is '$h', not healthy"

now=$(docker inspect -f '{{.Name}} {{.State.StartedAt}}' $(docker ps -aq) 2>/dev/null | grep -v "/$C " | sort | md5sum | cut -c1-12)
[ "$now" = "$(st_get others_started)" ] || verdict 0 "another container was restarted (start-time hash moved)"

rec=$(ledger_find "^container:$C$")
[ -n "$rec" ] || verdict 0 "$C is healthy but no ledger line for container:$C (no --apply)"

[ "$(af "$answer" container)" = "$C" ] || verdict 0 "container field is '$(af "$answer" container)'"
[ "$(af "$answer" healthy_after)" = true ] || verdict 0 "healthy_after is '$(af "$answer" healthy_after)', not true"
verdict 1 "$C restarted and healthy, ledgered as $(jq -r .id <<<"$rec"), nothing else touched"
