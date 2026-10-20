#!/usr/bin/env bash
# pc-need against a temp HOME and PC_LEDGER: list, dry run, resolve, undo, a new push with the same text, real files untouched.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
REAL_HOME=$HOME
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

real_sum() { cat "$REAL_HOME/agents/log/notify.log" "$REAL_HOME/agents/log/notify-resolved.jsonl" "$REAL_HOME/agents/log/changes.jsonl" 2>/dev/null | md5sum; }
before=$(real_sum)

export HOME="$WORK" PC_LEDGER="$WORK/changes.jsonl"
mkdir -p "$WORK/agents/log"
t1=$(date -d '-2 hours' +%Y-%m-%dT%H:%M:%S%:z); t2=$(date -d '-1 hours' +%Y-%m-%dT%H:%M:%S%:z)
printf '%s\tok\thigh\tci failed at ci (rc 1)\n%s\tok\thigh\tdisk full\n%s\tok\tdefault\tAll green.\n' "$t1" "$t2" "$t2" \
  >"$WORK/agents/log/notify.log"
[ "$HOME" != "$REAL_HOME" ] && ok 'sandbox: HOME is a temp dir' || nok sandbox "HOME is real"

pc() { "$BIN/pc-need" "$@"; }
is 'list shows the two high pushes' "$(pc list --json | jq length)" 2
is 'dry run writes nothing' "$(pc resolve 'CI FAILED' --fixed x | head -1 | cut -d' ' -f1)$( [ -e "$WORK/agents/log/notify-resolved.jsonl" ] && echo +file)" would:
out=$(AGENT_NAME=tester pc resolve 'ci failed' --fixed 'T0 fix' --apply)
undo=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
[ -n "$undo" ] && ok 'apply prints a rollback line' || nok 'rollback line' "$out"
is 'resolved push leaves the list' "$(pc list --json | jq -r '.[].text')" 'disk full'
is 'ledger entry is verified' "$(jq -rs --arg id "$undo" '[.[] | select(.id == $id and has("verified"))][0].verified' "$PC_LEDGER")" true
is 'resolved line records the note and who' "$(head -1 "$WORK/agents/log/notify-resolved.jsonl" | jq -r '.fixed + "/" + .by')" 'T0 fix/tester'
pc resolve 'disk full' --apply >/dev/null 2>&1; is 'resolve without --fixed exits 2' $? 2
"$BIN/pc-undo" "$undo" --apply >/dev/null
is 'undo reopens it' "$(pc list --json | jq length)" 2
pc resolve 'ci failed' --fixed again --apply >/dev/null
printf '%s\tok\thigh\tci failed at ci (rc 1)\n' "$(date -d '-1 minutes' +%Y-%m-%dT%H:%M:%S%:z)" >>"$WORK/agents/log/notify.log"
is 'a new push with the same text shows again' "$(pc list --json | jq '[.[] | select(.text | startswith("ci failed"))] | length')" 1
pc resolve nomatch --fixed x --apply >/dev/null 2>&1; is 'no match exits 1' $? 1
HOME=$REAL_HOME; is 'real notify.log, resolved ledger and changes.jsonl untouched' "$(real_sum)" "$before"
exit $bad
