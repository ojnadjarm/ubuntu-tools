#!/usr/bin/env bash
# pcbench-sick: healthy only after a restart. The entrypoint touches /tmp/ok when /flag/second
# exists; setup starts it without the flag (-> unhealthy), then creates the flag. Nothing but a
# fresh run of the entrypoint can turn it green, so "restarted" and "healthy" are the same fact.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
C=pcbench-sick
docker rm -f "$C" >/dev/null 2>&1 || true
rm -rf "$PWD/flag"; mkdir -p "$PWD/flag"
docker run -d --name "$C" -v "$PWD/flag:/flag" \
  --health-cmd 'test -f /tmp/ok' --health-interval 2s --health-retries 1 --health-timeout 2s \
  alpine sh -c '[ -f /flag/second ] && touch /tmp/ok; sleep 600' >/dev/null
for _ in $(seq 30); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$C" 2>/dev/null)" = unhealthy ] && break
  sleep 0.5
done
[ "$(docker inspect -f '{{.State.Health.Status}}' "$C")" = unhealthy ] || {
  echo "setup: $C did not go unhealthy" >&2; exit 1; }
touch "$PWD/flag/second"
# every other container's start time, so the check can prove nothing else was restarted
st_put others "$(docker ps -a --format '{{.Names}} {{.State}} {{.CreatedAt}}' | grep -v "^$C " | sort | md5sum | cut -c1-12)"
st_put others_started "$(docker inspect -f '{{.Name}} {{.State.StartedAt}}' $(docker ps -aq) 2>/dev/null | grep -v "/$C " | sort | md5sum | cut -c1-12)"
ledger_mark
exit 0
