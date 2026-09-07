#!/usr/bin/env bash
# PT14: pc docker against tests/fixtures/docker (two projects, 5 services, one restarting +
# one unhealthy container) plus live checks against the real Moodle stacks and a throw-away
# container round trip for the ledger.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/docker"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

# fx <args…> — pc docker against the recorded fixture (docker, two compose files).
fx() { PC_FIXTURE="$FIX" PC_ENVS="$FIX/moodle-envs" XDG_RUNTIME_DIR="$WORK" \
  PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-docker" "$@"; }

# 1. fixture: two projects, 5 services total, correct state/health rollups.
J=$(fx stacks --json)
[ -n "$J" ] && ok 'fixture stacks produces JSON' || nok 'fixture stacks produces JSON' empty
is 'two projects'            "$(jq 'length' <<<"$J")" 2
is 'five services total'     "$(jq '[.[].services[]] | length' <<<"$J")" 5
is 'moodle-shared dir'       "$(jq -r '.[] | select(.project=="moodle-shared") | .dir' <<<"$J")" "$FIX/moodle-envs/shared"
is 'moodle52 dir'            "$(jq -r '.[] | select(.project=="moodle52") | .dir' <<<"$J")" "$FIX/moodle-envs/5.2"
is 'moodle-shared is partial (one restarting)' \
  "$(jq -r '.[] | select(.project=="moodle-shared") | .state' <<<"$J")" partial
is 'moodle52 app is unhealthy' \
  "$(jq -r '.[] | select(.project=="moodle52") | .services[] | select(.service=="app") | .health' <<<"$J")" unhealthy
is 'moodle-shared listed before moodle52' "$(jq -r '.[0].project' <<<"$J")" moodle-shared

# 2. `ps` is the same data, flat.
is 'ps lists 5 containers' "$(fx ps --json | jq 'length')" 5

# 3. `health` on the fixture: one restarting + one unhealthy -> non-zero exit, both listed.
fx health --json >/dev/null; is 'health exits non-zero on fixture problems' "$?" 1
H=$(fx health --json)
is 'health finds 2 problems' "$(jq '.problems | length' <<<"$H")" 2

# 4. text mode renders (no crash), one line of header + one per service.
is 'stacks text has 6 lines (header + 5 services)' "$(fx stacks | wc -l)" 6

# 5. argument handling.
fx -h >/dev/null 2>&1; is '-h exits 0' "$?" 0
fx nosuchverb >/dev/null 2>&1; is 'unknown verb exits 2' "$?" 2
fx --nosuchflag >/dev/null 2>&1; is 'unknown option exits 2' "$?" 2
fx logs >/dev/null 2>&1; is 'logs without a container exits 2' "$?" 2
fx restart nosuchcontainer >/dev/null 2>&1; is 'restart of an unknown target exits 2' "$?" 2
grep -q '^  pc docker ' <("$BIN/pc" help) && ok 'pc help lists pc docker' || nok 'pc help lists pc docker' missing

# 6. dry runs: no ledger entry without --apply.
out=$(fx restart nosuchcontainer 2>&1)
case "$out" in *2) ;; esac
[ -e "$WORK/l.jsonl" ] && nok 'no ledger yet' 'ledger exists' || ok 'no ledger yet'

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  # 7. live: both real Moodle projects, 5 services, in one call.
  L=$(PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-docker" stacks --json)
  is 'live: two projects' "$(jq 'length' <<<"$L")" 2
  is 'live: five services' "$(jq '[.[].services[]] | length' <<<"$L")" 5

  # 8. live: health is clean tonight.
  PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-docker" health >/dev/null; is 'live health exit 0' "$?" 0

  # 9. live: a dry-run restart on a real container prints `would:` and changes nothing.
  out=$(PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-docker" restart moodle52-app-1)
  case "$out" in would:*) ok 'live dry-run restart prints would:';; *) nok 'live dry-run restart prints would:' "$out";; esac

  # 10. live: stopping the shared stack while moodle52 is up is refused.
  PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-docker" stop shared --apply >/dev/null 2>&1
  is 'stop shared --apply is refused (exit 3)' "$?" 3

  # 11. throw-away round trip: only if the alpine image is already present (no pull at night).
  if [ -n "$(docker images -q alpine 2>/dev/null)" ]; then
    docker rm -f pt14-alpine >/dev/null 2>&1
    docker run --rm -d --name pt14-alpine alpine sleep 300 >/dev/null
    live() { PC_LEDGER="$WORK/live.jsonl" "$BIN/pc-docker" "$@"; }
    out=$(live restart pt14-alpine --apply)
    id=$(printf '%s\n' "$out" | tail -1 | sed -n 's/^rollback: pc undo //p')
    [ -n "$id" ] && ok 'throw-away restart prints the rollback line' || nok 'throw-away restart prints the rollback line' "$out"
    is 'throw-away container is running after restart' "$(docker inspect -f '{{.State.Status}}' pt14-alpine)" running
    is 'the ledger entry is verified' "$(jq -r 'select(.verified!=null).verified' "$WORK/live.jsonl")" true
    docker rm -f pt14-alpine >/dev/null 2>&1
    is 'no pt14-* container survives' "$(docker ps -a --format '{{.Names}}' | grep -c pt14 || true)" 0
  else
    ok 'throw-away round trip skipped (no alpine image locally tonight)'
  fi

  # 12. exec budget: `pc docker stacks` forks only readlink, dirname, docker, and two jq
  # passes (own script exec + the `bash` shebang resolution are excluded, same as the other
  # PT baselines' "real execs" count).
  if command -v strace >/dev/null 2>&1; then
    strace -f -e trace=execve -o "$WORK/st.out" "$BIN/pc-docker" stacks >/dev/null 2>&1
    n=$(grep -E '= 0$' "$WORK/st.out" | grep -cE 'execve\("[^"]*/(readlink|dirname|jq|docker)"')
    [ "${n:-99}" -le 6 ] && ok "pc docker stacks real execs ($n) <= 6" || nok "pc docker stacks real execs" "$n > 6"
  else
    ok 'exec budget check skipped (no strace)'
  fi
else
  ok 'live checks skipped (no docker daemon)'
fi

[ $bad = 0 ] && echo 'PASS pc-docker' || echo 'FAIL pc-docker'
exit $bad
