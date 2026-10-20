#!/usr/bin/env bash
# T269: a keepalive fault gets at most SENTINEL_TRIES bash repairs in a row, then one push, and the
# count resets once it clears. Sandboxed (FLEET §5.6): fake $HOME, every outside command is a shim.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(dirname "$here")/sentinel-check"
. "$HOME/agents/bin/tests/lib/assert.sh"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/agents/bin"; ST="$WORK/agents/sentinel/state"; CALLS="$WORK/calls.log"
mkdir -p "$BIN" "$ST" "$WORK/moodle-envs/4.5"
printf 'name: moodle45\n' >"$WORK/moodle-envs/4.5/docker-compose.yml"
for c in docker systemctl notify-owner agent-run sentinel-runaway sentinel-waits sleep pw-metadata; do
  printf '#!/bin/sh\necho "%s $*" >>"%s"\nexit 0\n' "$c" "$CALLS" >"$BIN/$c"; chmod +x "$BIN/$c"
done
printf '#!/bin/sh\ncat "%s/status.json"\n' "$WORK" >"$BIN/status-stub"; chmod +x "$BIN/status-stub"
down='{"sections":{"keepalive":{"vass-frontend.service":{"state":"FAIL","value":"failed"},"http-moodle45":{"state":"FAIL","value":"502"}}}}'
up='{"sections":{"keepalive":{"vass-frontend.service":{"state":"OK","value":"active"}}}}'
tick() { HOME="$WORK" HARNESS_ENV_LOADED=1 SENTINEL_STATUS_CMD="$BIN/status-stub" SENTINEL_TRIES=3 "$SCRIPT"; }

# selftest: the shims win over the real commands on the script's PATH.
[ "$(PATH="$BIN:$PATH" command -v systemctl)" = "$BIN/systemctl" ] && ok "selftest: systemctl is a shim" \
  || { nok "selftest" "systemctl not shadowed"; exit 1; }

echo "$down" >"$WORK/status.json"
for _ in 1 2 3 4 5; do tick; done
is "unit restarted 3 times" "$(grep -c 'systemctl --user restart vass-frontend.service' "$CALLS")" 3
is "4.5 stack restarted 3 times" "$(grep -c 'docker compose -f .*/4.5/docker-compose.yml restart' "$CALLS")" 3
is "one push per fault after the cap" "$(grep -c '^notify-owner .*repairs' "$CALLS")" 2

echo "$up" >"$WORK/status.json"; tick
is "counters reset once healthy" "$(find "$ST/tries" -type f | wc -l)" 0
echo "$down" >"$WORK/status.json"; : >"$CALLS"; tick
is "repairs resume after a clear" "$(grep -c 'systemctl --user restart vass-frontend.service' "$CALLS")" 1
exit $bad
