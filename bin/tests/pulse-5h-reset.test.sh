#!/usr/bin/env bash
# pulse-5h-reset: one pulse per window reset, none while plan-usage only has a past (cached) reset time.
# Fixture-only (FLEET §5.6): plan-usage and orchestrator-pulse are PATH stubs; the selftest proves the real pulse is unreachable.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P5="$(dirname "$here")/pulse-5h-reset"
. "$HOME/agents/bin/tests/lib/assert.sh"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stubs"
printf '#!/bin/sh\nprintf "{\\"5h\\": {\\"resets_at\\": \\"%%s\\"}}" "$(cat "$WORK/reset")"\n' >"$WORK/stubs/plan-usage"
printf '#!/bin/sh\necho pulse >>"$WORK/pulses"\n' >"$WORK/stubs/orchestrator-pulse"
chmod +x "$WORK/stubs/"*
export WORK PATH="$WORK/stubs:$PATH" PULSE5H_STATE="$WORK/state"
[ "$(command -v orchestrator-pulse)" = "$WORK/stubs/orchestrator-pulse" ] || { echo 'FAIL selftest: real orchestrator-pulse reachable'; exit 1; }
pulses() { cat "$WORK/pulses" 2>/dev/null | wc -l; }

date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%S+00:00 >"$WORK/reset"
cp "$WORK/reset" "$WORK/state"
for _ in 1 2 3 4; do "$P5"; done
[ "$(pulses)" -eq 1 ] && ok 'a past reset that plan-usage keeps returning pulses once, not every run' \
  || nok 'a past reset that plan-usage keeps returning pulses once, not every run' "$(pulses) pulses"

rm -f "$WORK/pulses"
date -u -d '+3 hour' +%Y-%m-%dT%H:%M:%S+00:00 >"$WORK/reset"
"$P5"; "$P5"
[ "$(pulses)" -eq 0 ] && ok 'a future reset does not pulse' || nok 'a future reset does not pulse' "$(pulses) pulses"
[ "$(cat "$WORK/state")" = "$(cat "$WORK/reset")" ] && ok 'the future reset is saved' || nok 'the future reset is saved' "$(cat "$WORK/state")"
rm -f "$WORK/pulses" "$WORK/state"
printf '#!/bin/sh\necho "{\\"5h\\": {\\"pct\\": null, \\"resets_at\\": null}}"\n' >"$WORK/stubs/plan-usage"
out=$("$P5"); rc=$?
[ "$rc" -eq 0 ] && [ "$(pulses)" -eq 0 ] && [ ! -e "$WORK/state" ] && ok 'a null 5h window neither pulses nor saves state' \
  || nok 'a null 5h window neither pulses nor saves state' "rc $rc, $(pulses) pulses"
printf '%s' "$out" | grep -q 'no future 5h resets_at' && ok 'a null 5h window logs one line' || nok 'a null 5h window logs one line' "out: $out"
exit $bad
