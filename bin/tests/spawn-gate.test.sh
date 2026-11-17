#!/usr/bin/env bash
# T1754-B D183 bin/spawn-gate: CPU busy % from two /proc/stat samples; fixture stat files only, no load run.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$BIN/tests/lib/assert.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
# stat <file> <user> <idle>: an aggregate cpu line (user nice system idle iowait irq softirq steal).
stat() { printf 'cpu  %s 0 0 %s 0 0 0 0 0 0\ncpu0 1 0 0 1 0 0 0 0 0 0\n' "$2" "$3" >"$1"; }
stat "$W/a" 1000 1000
stat "$W/busy" 1950 1050      # +950 busy, +50 idle: 95 %
stat "$W/calm" 1200 1800      # +200 busy, +800 idle: 20 %
stat "$W/edge" 1900 1100      # +900 busy, +100 idle: 90 %
gate() { SPAWN_GATE_STAT1="$W/a" SPAWN_GATE_STAT2="$W/$1" "$BIN/spawn-gate" "${@:2}"; }

out=$(gate calm); is 'calm: exit 0' "$?" 0
is 'calm: one line, busy and limit' "$out" 'cpu busy 20 % (limit 90)'
out=$(gate busy); is 'busy: exit 3' "$?" 3
is 'busy: one line' "$out" 'cpu busy 95 % (limit 90)'
gate edge >/dev/null; is 'at the limit: exit 3' "$?" 3
out=$(gate calm --limit 15); is '--limit 15 over 20 %: exit 3' "$?" 3
is '--limit shows in the line' "$out" 'cpu busy 20 % (limit 15)'
out=$(SPAWN_GATE=off gate busy); is 'SPAWN_GATE=off: exit 0 even when busy' "$?" 0
case "$out" in *SPAWN_GATE=off*) ok 'SPAWN_GATE=off: says so';; *) nok 'SPAWN_GATE=off: says so' "$out";; esac
gate calm --limit x >/dev/null 2>&1; is 'bad --limit: exit 2' "$?" 2
out=$("$BIN/spawn-gate"); rc=$?
[[ $out =~ ^cpu\ busy\ [0-9]+\ %\ \(limit\ 90\)$ && ( $rc = 0 || $rc = 3 ) ]] && ok 'live /proc/stat: one line, exit 0 or 3' \
  || nok 'live /proc/stat' "$rc $out"
exit $bad
