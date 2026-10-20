#!/usr/bin/env bash
# Replay fixture for ~/agents/bin/sentinel-check: every fault signature the sentinel recorded in
# the 7 days to 2026-09-07 (fixtures/sentinel-check/events.tsv), driven through the real script
# with a fake $HOME, so every fix, push and escalation is a shim that only records its call.
# Asserts the decision transcript — fix chosen, fixed-by-bash, suppressed, escalated — not repairs.
# Run: bash sentinel-check.test.sh [--record FILE]
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(dirname "$here")/sentinel-check"
EVENTS="$here/fixtures/sentinel-check/events.tsv"
EXPECT="$here/fixtures/sentinel-check/expected.txt"
[ -e "$(dirname "$here")/compose-services" ] || { echo "SKIP owner data absent: $(dirname "$here")/compose-services"; exit 0; }
RECORD=""; [ "${1:-}" = --record ] && RECORD="${2:?--record needs a file}"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/agents/bin"; ST="$WORK/agents/sentinel/state"
mkdir -p "$BIN" "$ST" "$WORK/moodle-envs/shared"
printf 'name: moodle-shared\n' >"$WORK/moodle-envs/shared/docker-compose.yml"
CALLS="$WORK/calls.log"

# Shims: everything sentinel-check can reach out to. $HOME/agents/bin is first on the script's
# own PATH, so these win over the real commands.
for c in docker systemctl notify-owner agent-run sentinel-runaway sentinel-waits pc; do
  printf '#!/bin/sh\necho "%s $*" >>"$CALLS"\nexit 0\n' "$c" >"$BIN/$c"
  chmod +x "$BIN/$c"
done
# sudo passes tailscale through; tailscale refuses an `up` that drops a non-default pref, as the real one does.
printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\n[ "$1" = tailscale ] && exec "$@"\nexit 0\n' >"$BIN/sudo"
cat >"$BIN/tailscale" <<'EOF'
#!/bin/sh
echo "tailscale $*" >>"$CALLS"
case " $* " in *" --hostname=example-host --operator=agentuser --ssh "*) exit 0 ;; esac
echo "Error: changing settings via 'tailscale up' requires mentioning all non-default flags." >&2
exit 1
EOF
chmod +x "$BIN/sudo" "$BIN/tailscale"
# The real compose-services (T540): its docker calls reach the docker shim above.
ln -s "$(dirname "$here")/compose-services" "$BIN/compose-services"
cat >"$BIN/pw-metadata" <<'EOF'
#!/bin/sh
echo "pw-metadata $*" >>"$CALLS"
[ $# -le 4 ] && echo "update: id:0 key:'log.level' value:'$PW_LEVEL' type:''"
exit 0
EOF
chmod +x "$BIN/pw-metadata"
# sleep shim: records the wait and marks the tick as settled instead of sleeping.
printf '#!/bin/sh\necho "sleep $*" >>"$CALLS"\n: >"$TICK/slept"\n' >"$BIN/sleep"
chmod +x "$BIN/sleep"
# snapshot stub: first call answers "before", later ones "after" ("settled" once a sleep ran).
cat >"$BIN/status-stub" <<'EOF'
#!/bin/sh
n=$(cat "$TICK/n" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"$TICK/n"
if [ "$n" = 1 ]; then cat "$TICK/before.json"
elif [ -e "$TICK/slept" ]; then cat "$TICK/settled.json"
else cat "$TICK/after.json"; fi
EOF
chmod +x "$BIN/status-stub"

# status_json "<sec.key=value,...>" — a pc status --json document with those entries FAIL ("!" = no output).
status_json() {
  [ "$1" = '!' ] && return 0
  jq -nSc --arg s "$1" '{sections: (reduce ($s | split(",")[] | select(. != "") | split("=")) as $kv
    ({power: {battery: {state: "OK", value: "100%"}}};
     ($kv[0] | split(".")) as $k | .[$k[0]][$k[1:] | join(".")] = {state: "FAIL", value: ($kv[1:] | join("="))}))}'
}

TICKDIR="$WORK/tick"; mkdir -p "$TICKDIR"
export CALLS TICK="$TICKDIR" SENTINEL_BRIEF_CMD=false   # no brief line: every tick reads the status stub
out="$WORK/transcript.txt"
: >"$out"

while IFS='|' read -r label before after pw settled; do
  case "$label" in ''|'#'*) continue ;; esac
  status_json "$before" >"$TICKDIR/before.json"
  status_json "$after"  >"$TICKDIR/after.json"
  case "$settled" in '') settled=$after ;; -) settled='' ;; esac
  status_json "$settled" >"$TICKDIR/settled.json"
  rm -f "$TICKDIR/n" "$TICKDIR/slept"
  : >"$CALLS"
  PW_LEVEL="$pw" HOME="$WORK" HARNESS_ENV_LOADED=1 HARNESS_HOST=example-host USER=agentuser SENTINEL_STATUS_CMD="$BIN/status-stub" "$SCRIPT"
  rc=$?
  {
    echo "== $label rc=$rc"
    sed 's/^[0-9T:+.-]* //' "$ST/sentinel.log" 2>/dev/null
    sed "s#$WORK#\$WORK#g" "$CALLS"
    [ -e "$ST/suppressing" ] && echo "state: suppressing"
    [ -e "$ST/incident.json" ] && echo "state: incident.json written"
  } >>"$out"
  rm -f "$ST/sentinel.log" "$ST/incident.json"
done <"$EVENTS"

# --- T347-10: owner-only faults, the 2 h unit-loop push, the busy lock, the last-run stamp ----
. "$HOME/agents/bin/tests/lib/assert.sh"
tick() {  # tick <fails_before> [fails_after]: one sentinel run, calls in $CALLS, rc in $rc
  status_json "$1" >"$TICKDIR/before.json"; status_json "${2-$1}" >"$TICKDIR/after.json"; cp "$TICKDIR/after.json" "$TICKDIR/settled.json"
  rm -f "$TICKDIR/n" "$TICKDIR/slept" "$ST/last-escalation" "$ST/suppressing"; : >"$CALLS"
  PW_LEVEL=2 HOME="$WORK" HARNESS_ENV_LOADED=1 HARNESS_HOST=example-host USER=agentuser SENTINEL_STATUS_CMD="$BIN/status-stub" "$SCRIPT"
  rc=$?
}
rm -rf "$ST/tries" "$ST/last-ok" "$ST/last-run"
OWN='host.reboot_required=11 d,resources.swap=99%,host.failed_units=4,host.netdata_alerts=1 CRITICAL,agents.fleet=dark-eye-old.service inactive'
tick "$OWN"
{ [ "$rc" = 0 ] && ! grep -q 'agent-run\|notify-owner' "$CALLS"; } && ok "owner-only faults are never escalated or pushed" || nok "owner-only faults" "rc=$rc $(cat "$CALLS")"
[ -s "$ST/last-ok" ] && ok "a tick with only owner-only faults is a clean tick (last-ok)" || nok "owner-only tick writes last-ok" "no last-ok"
[ -s "$ST/last-run" ] && ok "every tick stamps last-run" || nok "last-run stamp" "missing"
tick "$OWN,network.internet=unreachable"
grep -q '^agent-run sentinel' "$CALLS" && [ "$(cut -f1 "$ST/last-escalation")" = "network.internet," ] \
  && ok "a repairable fault next to owner-only ones escalates alone" || nok "mixed escalation" "$(cat "$ST/last-escalation" 2>/dev/null)"
LOOP='agents.unit_loops=moodle45-cron.service 30 fails/h'
rm -rf "$ST/tries"; tick "$LOOP"
{ ! grep -q 'notify-owner' "$CALLS" && ! grep -q agent-run "$CALLS"; } && ok "a fresh unit loop is not pushed yet" || nok "fresh loop push" "$(cat "$CALLS")"
echo $(( $(date +%s) - 7300 )) >"$ST/tries/agents.unit_loops"
tick "$LOOP"
[ "$(grep -c 'notify-owner.*agents.unit_loops' "$CALLS")" = 1 ] && ok "a unit loop failing >= 2 h is pushed once" || nok "2 h loop push" "$(cat "$CALLS")"
tick "$LOOP"
grep -q 'notify-owner' "$CALLS" && nok "the loop push is bounded" "$(cat "$CALLS")" || ok "the loop push is bounded (no second push)"
tick ''
[ ! -e "$ST/tries/agents.unit_loops" ] && ok "a cleared loop resets its episode" || nok "loop episode reset" "tries file left"
# T350: pc status FAILs services.ssh only when ssh.service and ssh.socket are both down.
tick 'services.ssh=inactive'
grep -q '^agent-run sentinel' "$CALLS" && ok "ssh service + socket down still escalates for repair" || nok "ssh down escalation" "$(cat "$CALLS")"
tick ''
grep -q 'agent-run\|notify-owner' "$CALLS" && nok "ssh up via socket is a quiet tick" "$(cat "$CALLS")" || ok "ssh up via socket is a quiet tick"
# F08: a fault-row glob is not expanded against the cwd (the unit runs in $HOME).
mkdir -p "$WORK/cwd" && : >"$WORK/cwd/docker.x" && : >"$WORK/cwd/keepalive.x"
(cd "$WORK/cwd" && tick 'docker.moodle-shared=3/4 up' '')
grep -q '^docker compose' "$CALLS" && ! grep -q agent-run "$CALLS" \
  && ok "fault globs ignore files in the cwd" || nok "cwd glob" "$(cat "$CALLS")"
: >"$ST/sentinel.log"
exec 8>"$ST/.lock"; flock 8
tick "$OWN"
exec 8>&-
{ [ "$rc" = 0 ] && grep -q 'lock busy' "$ST/sentinel.log"; } && ok "a busy lock is logged, not silent" || nok "busy lock log" "rc=$rc $(cat "$ST/sentinel.log")"
# TSP-044: a failed transient run-* scope >= 10 min old is reset through pc units; a young one,
# a non-transient one and a non-run unit are left alone. The systemctl stub answers read-only argv.
mv "$BIN/systemctl" "$BIN/systemctl.replay"
cat >"$BIN/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >>"$CALLS"
now=$(date +%s)
case "$*" in
  "--user list-units --state=failed --plain --no-legend")
    for u in run-old.scope run-young.scope run-static.scope fx.service; do echo "$u loaded failed failed fixture"; done;;
  "--user show run-old.scope "*)    printf 'Description=[systemd-run] bash -c balloon\nStateChangeTimestamp=@%s\nTransient=yes\n' $((now-1200));;
  "--user show run-young.scope "*)  printf 'Description=young\nStateChangeTimestamp=@%s\nTransient=yes\n' $((now-60));;
  "--user show run-static.scope "*) printf 'Description=static\nStateChangeTimestamp=@%s\nTransient=no\n' $((now-1200));;
esac
exit 0
EOF
chmod +x "$BIN/systemctl"
: >"$ST/sentinel.log"; tick ''
[ "$(grep -c '^pc units reset-failed' "$CALLS")" = 1 ] && grep -q '^pc units reset-failed run-old.scope --user --apply$' "$CALLS" \
  && ok "an old failed transient run-* scope is reset via pc units" || nok "transient reset" "$(grep '^pc ' "$CALLS")"
grep -q 'reset failed transient run-old.scope .*balloon' "$ST/sentinel.log" \
  && ok "the reset is one log line with its Description" || nok "transient reset log" "$(cat "$ST/sentinel.log")"
bad_argv=$(grep '^systemctl' "$CALLS" | grep -v -e '^systemctl --user list-units --state=failed --plain --no-legend$' \
  -e '^systemctl --user show run-[a-z]*\.scope -p Transient -p Description -p StateChangeTimestamp --timestamp=unix$')
[ -z "$bad_argv" ] && grep -q '^systemctl --user show run-old' "$CALLS" \
  && ok "selftest: the systemctl stub saw only read-only argv" || nok "systemctl argv" "${bad_argv:-no show call}"
mv "$BIN/systemctl.replay" "$BIN/systemctl"
# T510: a service behind a compose `profiles:` entry is expected only while COMPOSE_PROFILES names it.
# The docker stub answers the read-only queries; `compose config` answers the fixture's services
# (db17 only under COMPOSE_PROFILES=target), so no docker CLI or daemon is needed.
FX="$WORK/moodle-envs/fx-rehearse"; mkdir -p "$FX"
cat >"$FX/docker-compose.yml" <<'EOF'
name: fx-rehearse
services:
  db13:
    image: postgres:13
  db17:
    image: postgres:17
    profiles: [target]
  app:
    image: moodlehq/moodle-php-apache:8.3
EOF
mv "$BIN/docker" "$BIN/docker.replay"
cat >"$BIN/docker" <<EOF
#!/bin/sh
echo "docker \$*" >>"\$CALLS"
case "\$*" in
  "ps -a --filter label=com.docker.compose.project=fx-rehearse "*) echo "$FX/docker-compose.yml";;
  "compose -p fx-rehearse -f "*" config --services") case ",\${COMPOSE_PROFILES:-}," in *,target,*) echo db17;; esac; printf 'app\ndb13\n';;
  "ps --filter label=com.docker.compose.project=fx-rehearse "*) printf '%s\n' \$FX_RUNNING;;
esac
exit 0
EOF
chmod +x "$BIN/docker"
STACK='docker.fx-rehearse=2/3 up'
rm -rf "$ST/tries"; : >"$ST/sentinel.log"; rm -f "$ST/last-ok"
FX_RUNNING='db13 app' tick "$STACK"; cat "$CALLS" >>"$WORK/fx-calls"
{ [ "$rc" = 0 ] && [ -s "$ST/last-ok" ] && ! grep -q 'up -d\|agent-run\|notify-owner' "$CALLS"; } \
  && grep -q 'docker.fx-rehearse 2/3 up: only services behind an inactive profile' "$ST/sentinel.log" \
  && ok "profiles: a stopped profile service is not a fault" || nok "profile service stopped" "$(cat "$CALLS" "$ST/sentinel.log")"
rm -rf "$ST/tries"; FX_RUNNING='db17 app' tick "$STACK"; cat "$CALLS" >>"$WORK/fx-calls"
grep -q "^docker compose -f $FX/docker-compose.yml up -d" "$CALLS" && grep -q '^agent-run sentinel' "$CALLS" \
  && ok "profiles: a stopped normal service is still the docker.* fault" || nok "normal service stopped" "$(cat "$CALLS")"
rm -rf "$ST/tries"; COMPOSE_PROFILES=target FX_RUNNING='db13 app' tick "$STACK"; cat "$CALLS" >>"$WORK/fx-calls"
grep -q '^agent-run sentinel' "$CALLS" \
  && ok "profiles: an active COMPOSE_PROFILES makes the profile service expected" || nok "active profile" "$(cat "$CALLS")"
bad_argv=$(grep '^docker' "$WORK/fx-calls" | grep -v -e '^docker ps ' -e ' config --services$' -e ' up -d$')
[ -z "$bad_argv" ] && ok "selftest: the docker stub saw only queries and the recorded up -d" || nok "docker argv" "$bad_argv"
mv "$BIN/docker.replay" "$BIN/docker"
# T988: a FAIL=none brief line ends the tick without the full JSON.
: >"$ST/sentinel.log"; rm -f "$ST/last-ok"
SENTINEL_BRIEF_CMD="echo AC 80% orch=ok FAIL=none" tick 'services.docker=inactive'
{ [ "$rc" = 0 ] && [ ! -e "$TICKDIR/n" ] && [ -s "$ST/last-ok" ] && ! grep -q '^sudo\|agent-run' "$CALLS"; } \
  && ok "brief FAIL=none: clean tick, no JSON read, no fix" || nok "brief gate" "rc=$rc n=$(cat "$TICKDIR/n" 2>/dev/null) $(cat "$CALLS")"
# T988: --profile runs the read path only: no fix, push, escalation or state write, CPU ms per step.
rm -rf "$ST/tries"; status_json 'services.docker=inactive,agents.unit_loops=x 30 fails/h' >"$TICKDIR/before.json"
cp "$TICKDIR/before.json" "$TICKDIR/after.json"; rm -f "$TICKDIR/n"; : >"$CALLS"
state_before=$(find "$ST" -printf '%p %s %T@\n' | sort)
prof=$(PW_LEVEL=5 HOME="$WORK" HARNESS_ENV_LOADED=1 SENTINEL_STATUS_CMD="$BIN/status-stub" "$SCRIPT" --profile); rc=$?
{ [ "$rc" = 0 ] && [ "$(find "$ST" -printf '%p %s %T@\n' | sort)" = "$state_before" ]; } \
  && ok "--profile writes no state" || nok "--profile state" "rc=$rc"
bad_calls=$(grep -v -e '^sentinel-runaway --dry-run$' -e '^sentinel-waits --dry-run$' -e '^pw-metadata -n settings 0 log.level$' \
  -e '^systemctl --user list-units ' "$CALLS")
[ -z "$bad_calls" ] && grep -q '^sentinel-runaway --dry-run$' "$CALLS" \
  && ok "--profile calls no fix (dry-run helpers only)" || nok "--profile calls" "$bad_calls"
for s in runaway waits transient pipewire status total; do
  grep -qE "^$s +[0-9]+ ms" <<<"$prof" || { nok "--profile step $s" "$prof"; continue 2; }
done
ok "--profile prints CPU ms per step"
"$SCRIPT" --bogus >/dev/null 2>&1; [ $? = 2 ] && ok "an unknown flag is rc 2" || nok "unknown flag" "not rc 2"
[ "$bad" = 0 ] || { echo "sentinel-check: FAIL — T347-10 cases" >&2; exit 1; }

if [ -n "$RECORD" ]; then cp "$out" "$RECORD"; echo "recorded $RECORD"; exit 0; fi
if [ ! -r "$EXPECT" ]; then
  echo "sentinel-check.test.sh: no $EXPECT — record it with --record $EXPECT" >&2; exit 2
fi
if diff -u "$EXPECT" "$out"; then
  echo "sentinel-check: replay of $(grep -cvE '^#|^$' "$EVENTS") recorded events matches"
  exit 0
fi
echo "sentinel-check: FAIL — replay decisions differ from $EXPECT" >&2
exit 1
