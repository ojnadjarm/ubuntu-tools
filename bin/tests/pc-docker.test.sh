#!/usr/bin/env bash
# PT14: pc docker against tests/fixtures/docker (two projects, 5 services, one restarting +
# one unhealthy container) plus live checks against the real Moodle stacks and a throw-away
# container round trip for the ledger.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/docker"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

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

# 7a. recreate on a stub docker + curl (argv logged): fixture envs incl. Vass-named ones.
ENVS="$WORK/envs"; cp -r "$FIX/moodle-envs" "$ENVS"
mkdir -p "$ENVS/4.5" "$ENVS/vass-services" "$WORK/bin"
printf 'name: moodle45\n' >"$ENVS/4.5/docker-compose.yml"
printf 'name: vass-services\n' >"$ENVS/vass-services/docker-compose.yml"
cat >"$WORK/bin/docker" <<'STUB'
#!/bin/sh
echo "$*" >>"$STUB_DIR/docker.log"
case "$1 $*" in
  compose*) echo 'json-file 20m' >"$STUB_DIR/cap";;
  "inspect "*max-size*) cat "$STUB_DIR/cap" 2>/dev/null || echo 'json-file ';;
  "ps "*Ports*) echo '0.0.0.0:8052->80/tcp, [::]:8052->80/tcp, 0.0.0.0:5452->5432/tcp';;
  "ps "*"--filter label=com.docker.compose.project="*) p=${*#*project=}; echo "${p%% *}-app-1";;
  "ps "*) printf '%s\n' $STUB_OTHERS;;
esac
STUB
cat >"$WORK/bin/curl" <<'STUB'
#!/bin/sh
[ -e "$STUB_DIR/cap" ] && [ -e "$STUB_DIR/code_after" ] && exec cat "$STUB_DIR/code_after"
echo 200
STUB
cat >"$WORK/bin/wait-for" <<'STUB'
#!/bin/sh
while [ $# -gt 0 ]; do [ "$1" = --until ] && exec sh -c "$2"; shift; done
STUB
chmod +x "$WORK/bin/docker" "$WORK/bin/curl" "$WORK/bin/wait-for"
rc() { STUB_DIR=$WORK STUB_OTHERS=${OTHERS:-} PATH="$WORK/bin:$PATH" PC_ENVS="$ENVS" XDG_RUNTIME_DIR="$WORK" \
  PC_LEDGER="$WORK/rc.jsonl" "$BIN/pc-docker" recreate "$@"; }
is 'recreate dry run' "$(rc 5.2)" 'would: stack:moodle52 uncapped=1 → uncapped=0'
grep -q "^compose" "$WORK/docker.log" && nok 'dry run runs no compose' called || ok 'dry run runs no compose'
out=$(rc 5.2 --apply 2>"$WORK/err")
grep -qxF "compose -f $ENVS/5.2/docker-compose.yml up -d --force-recreate" "$WORK/docker.log" \
  && ok 'apply runs compose up -d --force-recreate in the stack dir' || nok 'apply runs compose' "$(cat "$WORK/docker.log")"
case "$(tail -1 <<<"$out")" in 'rollback: pc undo '*) ok 'apply ends with the rollback line';; *) nok 'apply ends with the rollback line' "$out";; esac
is 'ledger read-back verified' "$(jq -r 'select(.verified!=null).verified' "$WORK/rc.jsonl")" true
is 'http read-back on every port published to :80' "$(cat "$WORK/err")" 'http 8052: 200 (before 200)'
id=$(tail -1 <<<"$out" | sed -n 's/^rollback: pc undo //p')
STUB_DIR=$WORK PATH="$WORK/bin:$PATH" PC_LEDGER="$WORK/rc.jsonl" XDG_RUNTIME_DIR="$WORK" \
  "$BIN/pc-undo" "$id" --force --apply >/dev/null 2>"$WORK/undo.err"
is 'undo of a recreate refuses (exit 1)' "$?" 1
grep -q 'not reversible' "$WORK/undo.err" && ok 'undo says the recreate is not reversible' || nok 'undo message' "$(cat "$WORK/undo.err")"
rm -f "$WORK/cap"; echo 000 >"$WORK/code_after"
rc 5.2 --apply >/dev/null 2>"$WORK/err"; is 'apply exits 1 when :8052 does not come back' "$?" 1
is 'failed http read-back reported' "$(cat "$WORK/err")" 'http 8052: 000 (before 200)'
rm -f "$WORK/code_after"
: >"$WORK/docker.log"
for v in 4.5 moodle45 vass-services vass; do
  rc "$v" --apply >/dev/null 2>&1; is "recreate $v refused (exit 3)" "$?" 3
done
is 'Vass refusals call no docker at all' "$(wc -c <"$WORK/docker.log")" 0
OTHERS=moodle52 rc shared --apply >/dev/null 2>&1; is 'recreate shared refused while moodle52 up' "$?" 3
grep -q "^compose" "$WORK/docker.log" && nok 'refused shared runs no compose' called || ok 'refused shared runs no compose'
case "$(OTHERS=moodle52 rc shared --force)" in would:*) ok 'recreate shared --force passes the guard';; *) nok 'shared --force' x;; esac
rc moodle52-app-1 >/dev/null 2>&1; is 'recreate of a container exits 2' "$?" 2

# 7b. idle-stop selenium on a stub docker + pgrep: busy refused, recent nothing, idle stopped + undone.
IS="$WORK/is"; mkdir -p "$IS/bin"
cat >"$IS/bin/docker" <<'STUB'
#!/bin/sh
echo "$*" >>"$IS/docker.log"
case "$*" in
  *State.Status*) cat "$IS/state";;
  *State.StartedAt*) echo "$IS_STARTED";;
  "top $2 -o pid,comm") printf 'PID COMMAND\n1 supervisord\n2 java\n3 Xvfb\n%s' "${IS_TOP:+4 $IS_TOP}";;
  top*) echo "Error response from daemon: Couldn't find PID field in ps output" >&2; exit 1;;
  logs*) since=$(printf '%s\n' "$*" | sed -n 's/.*--since \([^ ]*\).*/\1/p')
    printf '%s\n' "$since" | grep -qxE '[0-9]+[smh]' && { cat "$IS/logs"; exit 0; }
    echo 'invalid value for "since": failed to parse value as time or duration' >&2; exit 1;;
  stop*) echo exited >"$IS/state"; echo "$2";;
  start*) echo running >"$IS/state"; echo "$2";;
esac
STUB
cat >"$IS/bin/pgrep" <<'STUB'
#!/bin/sh
[ -n "$IS_BEHAT" ] && echo "$IS_BEHAT"
STUB
chmod +x "$IS/bin/docker" "$IS/bin/pgrep"
old=$(date -u -d '-3 hours' +%FT%T.000000000Z); recent=$(date -u -d '-10 minutes' +%FT%T.000000000Z)
noise="$recent 2026-10-21 13:49:18.270:WARN:osjs.HttpChannel:qtp-9637: /"
is_() { IS=$IS IS_STARTED=${STARTED:-$old} IS_TOP=${TOP:-} IS_BEHAT=${BEHAT:-} PATH="$IS/bin:$PATH" \
  XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/is.jsonl" "$BIN/pc-docker" idle-stop "$@"; }
reset() { echo running >"$IS/state"; printf '%s\n' "$noise" >"$IS/logs"; : >"$IS/docker.log"; }
reset; sleep 300 & spid=$!
out=$(BEHAT=$spid is_ selenium --apply 2>&1); is 'idle-stop refused while behat runs (exit 3)' "$?" 3
case "$out" in refused:*) ok 'busy prints refused:';; *) nok 'busy prints refused:' "$out";; esac
BEHAT=$$ is_ selenium >/dev/null 2>&1; is 'a bash caller naming behat is not a run' "$?" 0
kill "$spid" 2>/dev/null
TOP=chrome is_ selenium --apply >/dev/null 2>&1; is 'idle-stop refused while a browser is open' "$?" 3
grep -q '^stop' "$IS/docker.log" && nok 'refusals stop nothing' called || ok 'refusals stop nothing'
echo "$recent 07:00:26.779 INFO [RemoteSession] - Started new session 4e1d (chrome)" >>"$IS/logs"
case "$(is_ selenium --apply)" in 'nothing: moodle-shared-selenium-1 had a Selenium session 10m ago (< 2h)') ok 'recent session -> nothing:';; *) nok 'recent session' "$(is_ selenium 2>&1)";; esac
case "$(is_ selenium --after 1d --apply)" in 'nothing: '*'session 10m ago (< 1d)') ok '--after 1d sees a recent session';; *) nok '--after 1d' "$(is_ selenium --after 1d 2>&1)";; esac
reset
case "$(STARTED=$recent is_ selenium --apply)" in 'nothing: '*'started 10m ago'*) ok 'just started -> nothing:';; *) nok 'just started' x;; esac
echo exited >"$IS/state"
case "$(is_ selenium --apply)" in 'nothing: moodle-shared-selenium-1 is exited'*) ok 'stopped -> nothing:';; *) nok 'stopped' x;; esac
reset
is 'idle dry run' "$(is_ selenium)" "would: container:moodle-shared-selenium-1 running → exited
start: pc docker start moodle-shared-selenium-1 --apply"
grep -q '^stop' "$IS/docker.log" && nok 'dry run stops nothing' called || ok 'dry run stops nothing'
out=$(is_ selenium --after 1h --apply); is 'idle apply exits 0' "$?" 0
grep -qx 'stop moodle-shared-selenium-1' "$IS/docker.log" && ok 'apply stops only the selenium container' || nok 'apply stop' "$(cat "$IS/docker.log")"
case "$(tail -1 <<<"$out")" in 'rollback: pc undo '*) ok 'idle apply ends with the rollback line';; *) nok 'rollback line' "$out";; esac
is 'idle apply verified' "$(jq -r 'select(.verified!=null).verified' "$WORK/is.jsonl")" true
id=$(tail -1 <<<"$out" | sed -n 's/^rollback: pc undo //p')
IS=$IS PATH="$IS/bin:$PATH" PC_LEDGER="$WORK/is.jsonl" XDG_RUNTIME_DIR="$WORK" "$BIN/pc-undo" "$id" --apply >/dev/null 2>&1
is 'undo starts selenium again' "$(cat "$IS/state")" running
grep -qx 'start moodle-shared-selenium-1' "$IS/docker.log" && ok 'undo runs docker start' || nok 'undo start' "$(cat "$IS/docker.log")"
is_ mailhog >/dev/null 2>&1; is 'idle-stop of another container exits 2' "$?" 2
is_ selenium --after soon >/dev/null 2>&1; is 'bad --after exits 2' "$?" 2

# 7c. selenium-idle units: hourly timer; the service line runs idle-stop outside the CI window only.
U="$HOME/agents/units/selenium-idle"
is 'selenium-idle timer is hourly' "$(sed -n 's/^OnCalendar=//p' "$U.timer")" hourly
is 'refused (busy) is not a unit failure' "$(sed -n 's/^SuccessExitStatus=//p' "$U.service")" 3
line=$(sed -n "s/^ExecStart=\/bin\/sh -c '\(.*\)'$/\1/p" "$U.service")
is 'service command line' "$line" '%h/agents/bin/ci-window >/dev/null || exit 0; exec %h/agents/bin/pc docker idle-stop selenium --after 2h --apply'
body=$(printf '%s' "$line" | sed "s|%h|$HOME|g")
unit_() { IS=$IS IS_STARTED=$old IS_TOP= IS_BEHAT= PATH="$IS/bin:$PATH" XDG_RUNTIME_DIR="$WORK" \
  PC_LEDGER="$WORK/unit.jsonl" CI_UNITS= CI_WINDOW_NOW=$1 sh -c "$body"; }
reset; unit_ 01:10 >/dev/null 2>&1; is 'in the CI window the service exits 0' "$?" 0
grep -q '^stop' "$IS/docker.log" && nok 'in the CI window nothing is stopped' called || ok 'in the CI window nothing is stopped'
reset; out=$(unit_ 14:00 2>&1); is 'outside the window the service exits 0' "$?" 0
grep -qx 'stop moodle-shared-selenium-1' "$IS/docker.log" && ok 'outside the window idle selenium is stopped' || nok 'unit stop' "$out"
# 7d. the real refusal under systemd: a throw-away transient unit with the unit's SuccessExitStatus.
if systemctl --user show-environment >/dev/null 2>&1; then
  reset; out=$(systemd-run --user --wait --collect --unit="pt14-selenium-idle-$$" \
    -p SuccessExitStatus="$(sed -n 's/^SuccessExitStatus=//p' "$U.service")" -E IS="$IS" -E IS_STARTED="$old" \
    -E IS_TOP=chrome -E PATH="$IS/bin:$PATH" -E XDG_RUNTIME_DIR="$WORK" -E PC_LEDGER="$WORK/unit.jsonl" \
    -E CI_UNITS= -E CI_WINDOW_NOW=14:00 /bin/sh -c "$body" 2>&1)
  is 'systemd: a busy refusal finishes as success' "$?" 0
  grep -q 'status=3/' <<<"$out" && ok 'systemd: the refusal exited 3' || nok 'systemd: exit 3' "$out"
  grep -q '^stop' "$IS/docker.log" && nok 'systemd: a refusal stops nothing' called || ok 'systemd: a refusal stops nothing'
else
  ok 'systemd refusal case skipped (no user manager)'
fi

# 7e. stopping the shared stack while moodle52 is up is refused, on the stub docker (never the live stack).
: >"$WORK/docker.log"
STUB=$WORK/bin; STUB_DIR=$WORK STUB_OTHERS='moodle52 moodle-shared' PC_ENVS="$ENVS" XDG_RUNTIME_DIR="$WORK" \
  PC_LEDGER="$WORK/st.jsonl" PATH="$STUB:$PATH" "$BIN/pc-docker" stop shared --apply >/dev/null 2>&1
is 'stopping the shared stack with --apply is refused (exit 3)' "$?" 3
grep -q '^ps ' "$WORK/docker.log" && ok 'refusal read the stub docker' || nok 'refusal read the stub docker' "$(cat "$WORK/docker.log")"
is 'refused stop makes no mutating docker call' "$(grep -cE '^(compose|stop|rm|restart|kill)' "$WORK/docker.log")" 0

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  # 7. live: every compose project and service docker reports, in one call.
  L=$(PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-docker" stacks --json)
  labels=$(docker ps -a --format '{{.Label "com.docker.compose.project"}}' | grep -v '^$')
  is 'live: every compose project' "$(jq 'length' <<<"$L")" "$(sort -u <<<"$labels" | wc -l)"
  is 'live: every compose service' "$(jq '[.[].services[]] | length' <<<"$L")" "$(wc -l <<<"$labels")"

  # 8. live: health is clean tonight.
  PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-docker" health >/dev/null; is 'live health exit 0' "$?" 0

  # 9. live: a dry-run restart on a real container prints `would:` and changes nothing.
  out=$(PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-docker" restart moodle52-app-1)
  case "$out" in would:*) ok 'live dry-run restart prints would:';; *) nok 'live dry-run restart prints would:' "$out";; esac

  # 9b. live: a dry-run recreate reads the real log caps and changes nothing.
  out=$(PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-docker" recreate 5.2)
  case "$out" in 'would: stack:moodle52 uncapped='*) ok 'live dry-run recreate prints would:';; *) nok 'live dry-run recreate' "$out";; esac

  # 11. throw-away round trip: only if the alpine image is already present (no pull at night).
  if [ -n "$(docker images -q alpine 2>/dev/null)" ]; then
    docker rm -f pt14-alpine >/dev/null 2>&1
    docker run --rm -d --init --name pt14-alpine alpine sleep 300 >/dev/null
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
