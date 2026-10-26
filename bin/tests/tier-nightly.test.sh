#!/usr/bin/env bash
# tier-nightly on a throwaway Mooblox-shaped repo, stub npm and mci, temp state and logs: rows, red exit, Vass never run, one pass per mci log.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
. "$HOME/agents/bin/tests/lib/assert.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$T/repo/client" "$T/bin" "$T/state/moodle-harness/logs/local_a" "$T/state/moodle-harness/logs/local_v" "$T/plugins/a" "$T/envs/vass/local/v"
echo '{}' >"$T/repo/client/package.json"; git -C "$T/repo" init -q && git -C "$T/repo" add -A && git -C "$T/repo" commit -qm base
printf '#!/bin/sh\necho "npm $* in $PWD" >> "%s/calls"\ncase "$1 $2" in "run test:perf") exit "${RED_PERF:-0}";; esac\n' "$T" >"$T/bin/npm"
printf '#!/bin/sh\necho "mci $*" >> "%s/calls"\nexit "${RED_MCI:-0}"\n' "$T" >"$T/mci"
chmod +x "$T/bin/npm" "$T/mci"
L="$T/state/moodle-harness/logs"
echo "$T/plugins/a" >"$L/local_a/mci-1.log.plugin"; echo "$T/envs/vass/local/v" >"$L/local_v/mci-1.log.plugin"
echo "$T/gone" >"$L/local_a/mci-2.log.plugin"
echo '0.10 0.10 0.10 1/100 1' >"$T/loadavg"
run() { : >"$T/calls"; env PATH="$T/bin:$PATH" HOME="$T/home" XDG_STATE_HOME="$T/state" CI_UNITS= CI_LOADAVG="$T/loadavg" CI_QUIET_EVERY=1 \
  TIER_MOOBLOX="$T/repo" TIER_MCI="$T/mci" TIER_STATE="$T/st" TIER_LOGDIR="$T/log" TIER_PERF_LOCK="$T/perf.lock" TIER_NEVER="$T/envs/vass" \
  "$@" "$BIN/tier-nightly" >"$T/out" 2>&1; echo $?; }

[ "${T#/tmp/}" != "$T" ] || [ "${T#"${TMPDIR:-/tmp}"}" != "$T" ] && ok 'sandbox: temp repo, state and logs' || { nok sandbox "$T"; exit 1; }
is 'green pass: rc 0' "$(run env)" 0
is 'npm ci, npm test, perf gate in the archived client' "$(grep -c "in /tmp/.*/client$\|in ${TMPDIR:-/tmp}/.*/client$" "$T/calls") $(grep -c '^npm run test:perf' "$T/calls")" '3 1'
is 'mci full on the logged plugin only' "$(grep '^mci' "$T/calls")" "mci full $T/plugins/a"
is 'Vass plugin never run' "$(grep -c "^tier-nightly: never $T/envs/vass/local/v" "$T/out")" 1
is 'summary PASS 4/4' "$(tail -1 "$T/out")" 'tier-nightly: PASS 4/4 rows'
is 'output kept in the day log' "$(tail -1 "$T/log/$(date +%F).txt")" 'tier-nightly: PASS 4/4 rows'
is 'second pass: no mci run since the last pass' "$(run env; grep -c '^mci' "$T/calls"; grep -c 'no mci run since the last pass' "$T/out")" $'0\n0\n1'
touch "$L/local_a/mci-1.log.plugin"
is 'red perf gate: rc 1 and FAIL' "$(run env RED_PERF=1; tail -1 "$T/out")" $'1\ntier-nightly: FAIL 3/4 rows'
is 'a red row names the perf gate' "$(grep -c '^mooblox .* perf gate *1 ' "$T/out")" 1
touch "$L/local_a/mci-1.log.plugin"
is 'red mci: rc 1' "$(run env RED_MCI=1)" 1
"$BIN/tier-nightly" --bogus >/dev/null 2>&1; is 'bad argument: rc 2' $? 2
exit $bad
