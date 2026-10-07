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
RECORD=""; [ "${1:-}" = --record ] && RECORD="${2:?--record needs a file}"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/agents/bin"; ST="$WORK/agents/sentinel/state"
mkdir -p "$BIN" "$ST" "$WORK/moodle-envs/shared"
printf 'name: moodle-shared\n' >"$WORK/moodle-envs/shared/docker-compose.yml"
CALLS="$WORK/calls.log"

# Shims: everything sentinel-check can reach out to. $HOME/agents/bin is first on the script's
# own PATH, so these win over the real commands.
for c in docker systemctl notify-owner agent-run sentinel-runaway sentinel-waits; do
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
  python3 - "$1" <<'EOF'
import json, sys
sections = {"power": {"battery": {"state": "OK", "value": "100%"}}}
for item in filter(None, sys.argv[1].split(",")):
    key, _, value = item.partition("=")
    sec, _, name = key.partition(".")
    sections.setdefault(sec, {})[name] = {"state": "FAIL", "value": value}
print(json.dumps({"sections": sections}, sort_keys=True))
EOF
}

TICKDIR="$WORK/tick"; mkdir -p "$TICKDIR"
export CALLS TICK="$TICKDIR"
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
