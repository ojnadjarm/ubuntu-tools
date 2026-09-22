#!/usr/bin/env bash
# T30-t8: voice-progress against tests/fixtures/voice-progress — a stub corpus, prompt set and
# state file. The real corpus is never read and nothing is written.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$BIN/tests/fixtures/voice-progress"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

vp() {
  VOICE_CORPUS="${CORPUS:-$FIX/corpus}" VOICE_PROMPTS="$FIX/prompts.json" \
  VOICE_STATE="$FIX/state.json" "$BIN/voice-progress" "$@"
}

J=$(vp --json)

# 1. only drill takes are counted; the commands take and the unreadable file are ignored.
is 'three drill takes'   "$(jq .drill_takes <<<"$J")" 3
is 'two prompts done'    "$(jq '.prompts_done|length' <<<"$J")" 2

# 2. scoring: d01 take 1 misses "Start", take 2 is clean, d02 misses both.
is 'final-consonant takes'   "$(jq '.patterns["final-consonant"].takes' <<<"$J")" 3
is 'final-consonant targets' "$(jq '.patterns["final-consonant"].targets_heard' <<<"$J")" 6
is 'final-consonant errors'  "$(jq '.patterns["final-consonant"].errors' <<<"$J")" 3
is 'errors per 100 targets'  "$(jq '.patterns["final-consonant"].err_per_100' <<<"$J")" 50.0
is 'missed words listed'     "$(jq -c '.patterns["final-consonant"].missed' <<<"$J")" '["Start","closed","tab"]'

# 3. by day: day 1 is 1 of 4, day 2 is 2 of 2.
is 'day 1 rate' "$(jq '.patterns["final-consonant"].by_day["1"]' <<<"$J")" 25.0
is 'day 2 rate' "$(jq '.patterns["final-consonant"].by_day["2"]' <<<"$J")" 100.0

# 4. a pattern with no takes is null, not zero, and keeps its full denominator.
is 'v-b unrecorded'      "$(jq '.patterns["v-b"].err_per_100' <<<"$J")" null
is 'v-b denominator'     "$(jq '.patterns["v-b"].targets_total' <<<"$J")" 25
is 'four patterns always' "$(jq '.patterns|length' <<<"$J")" 4

# 5. the week-0 baseline travels with the report.
is 'baseline word error'  "$(jq '.baseline_week0.all' <<<"$J")" 15.6
is 'baseline no spelling' "$(jq '.baseline_week0.no_spelling' <<<"$J")" 13.4

# 6. text output: aligned table, baseline line, exit 0.
T=$(vp); is 'text exit 0' "$?" 0
is 'text has the pattern row' "$(grep -c '^final-consonant ' <<<"$T")" 2
is 'text has the baseline'    "$(grep -c 'week-0 baseline' <<<"$T")" 1
is 'text has the day header'  "$(grep -c 'by drill day' <<<"$T")" 1

# 7. an empty corpus: no drill takes, no crash, baseline still printed.
mkdir -p "$WORK/empty"
E=$(CORPUS="$WORK/empty" vp --json); is 'empty corpus exit 0' "$?" 0
is 'empty corpus takes'   "$(jq .drill_takes <<<"$E")" 0
is 'empty corpus overall' "$(jq '.overall.err_per_100' <<<"$E")" null
CORPUS="$WORK/empty" vp >"$WORK/empty.txt" 2>&1
is 'empty text exit 0'      "$?" 0
is 'empty text has baseline' "$(grep -c 'week-0 baseline' "$WORK/empty.txt")" 1
M=$(CORPUS="$WORK/missing" vp --json); is 'missing corpus dir exit 0' "$?" 0
is 'missing corpus takes' "$(jq .drill_takes <<<"$M")" 0

# 8. flags.
vp --help >/dev/null 2>&1; is '--help exit 0' "$?" 0
vp --nope >/dev/null 2>&1; is 'unknown flag exit 2' "$?" 2

# 9. read-only: the fixture corpus is untouched.
before=$(find "$FIX" -type f -newermt '-1 second' | wc -l)
vp --json >/dev/null
is 'nothing written' "$(find "$FIX" -type f -newermt '-1 second' | wc -l)" "$before"

[ "$bad" = 0 ] && printf 'PASS voice-progress\n' || printf 'FAIL voice-progress\n'
exit "$bad"
