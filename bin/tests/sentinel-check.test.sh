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
for c in sudo tailscale docker systemctl notify-owner agent-run sentinel-runaway; do
  printf '#!/bin/sh\necho "%s $*" >>"$CALLS"\nexit 0\n' "$c" >"$BIN/$c"
  chmod +x "$BIN/$c"
done
cat >"$BIN/pw-metadata" <<'EOF'
#!/bin/sh
echo "pw-metadata $*" >>"$CALLS"
[ $# -le 4 ] && echo "update: id:0 key:'log.level' value:'$PW_LEVEL' type:''"
exit 0
EOF
chmod +x "$BIN/pw-metadata"
# snapshot stub: first call of a tick answers "before", any later one (--fresh) "after".
cat >"$BIN/status-stub" <<'EOF'
#!/bin/sh
n=$(cat "$TICK/n" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"$TICK/n"
[ "$n" = 1 ] && cat "$TICK/before.json" || cat "$TICK/after.json"
EOF
chmod +x "$BIN/status-stub"

# status_json "<sec.key=value,...>" — a pc status --json document with those entries FAIL.
status_json() {
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

while IFS='|' read -r label before after pw; do
  case "$label" in ''|'#'*) continue ;; esac
  status_json "$before" >"$TICKDIR/before.json"
  status_json "$after"  >"$TICKDIR/after.json"
  rm -f "$TICKDIR/n"
  : >"$CALLS"
  PW_LEVEL="$pw" HOME="$WORK" SENTINEL_STATUS_CMD="$BIN/status-stub" "$SCRIPT"
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
