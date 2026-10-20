#!/usr/bin/env bash
# followups in a fixture HOME: a FOLLOWUPS.md, history.md and fleet-ci logs; also its fleet-survey section.
# shellcheck disable=SC1091,SC2015,SC2154  # assert.sh sets bad
set -uo pipefail
. "$HOME/agents/bin/tests/lib/assert.sh"
FU="$HOME/agents/bin/followups"; FS="$HOME/agents/bin/fleet-survey"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FH="$W/home"; A="$FH/agents"; AW="$FH/agent-work"; F="$W/FOLLOWUPS.md"
mkdir -p "$A/bin" "$A/log/fleet-ci" "$AW"
fu() { env -u HARNESS_HOME -u AGENT_WORK HOME="$FH" "$FU" "$@"; }
d() { date -d "$1" +%F; }
md() { date -d "$1" +%m-%d; }
D3=$(d '3 days ago'); D2=$(d '2 days ago'); D1=$(d '1 day ago')

cat >"$AW/history.md" <<EOF
- $D3 T10 first: mv-encode gains a flag
- $D3 T11 cpp-hot ships
- $D3 T13 machine-inventory first pass
- $D3 T12 brief written: x
- $D2 T20 mv-encode --subs drops -shortest (T10 seed)
- $D2 T21 unrelated tool (T11 mentioned)
- $D2 T22 planner wave 9: cpp-hot again (T11)
- $D2 T13 machine-inventory second pass
- $D3 T14 grain shipped
$D2 T15 dash-less dated line
- $D2 T23 Planner wave 10: foo-bar again (T9)
EOF
cat >"$F" <<EOF
# seeds
- ~~T1: done thing~~ (done T5)
- T2: a ~~half~~ (done T5) still open part
- ~~guide x: a line~~ (done T6)
- T10: mv-encode --subs adds -shortest; fix it.
- T11: cpp-hot rebuilds vcpkg.
- T13: machine-inventory runs dpkg -S per file.
- T14 ($D3): next nightly: grain cpu_s <= 60.
- T15 ($D2): next nightly: mv-look cpu_s <= 15.
- T16 ($D3): $(md '1 day ago'): pc search-index cpu <= 1,000 s.
- T17 ($D3): $(md tomorrow): claims --help <= 60.
- T18 ($D3): live plan $(md '3 days ago') 11:00 skipped 0; bed dips 6-10 dB.
- T19: SKILL.md line for mv-x pending.
- no id here at all
- T30 ($D3): waits on 1 decision from the owner.
- T31 ($D3): build takes 12-15 s, was 10-20 %.
- T32 ($D3): typo 02-30, real date $(md '1 day ago'): x.
- T9: foo-bar is slow.
- ~~T33: old target~~ (replaced by T940)
- ~~T34: x~~ (checked T991: log (L2) clean)
- ~~T35: y~~ (shipped T5) trailing text stays open.
- (fixed by orchestrator: a note alone)
- T36 ($D3): $(LC_ALL=C date -d '1 day ago' +'%-d %b'): z.
EOF
touch "$A/log/fleet-ci/$D2.txt"

out=$(fu "$F"); is "rc 0" "$?" 0
row() { grep -E "^L$1 " <<<"$out"; }
col() { row "$1" | awk -v c="$2" '{print $c}'; }
is "whole strike + done note = struck" "$(col 2 5)" struck
is "partial strike with open text stays open" "$(col 3 5)" open
is "guide line kind" "$(row 4 | awk '{print $4, $5}')" "guide line"
is "own later history line sharing a code word = shipped? by it" "$(row 5 | grep -oE 'shipped\? by T[0-9]+')" "shipped? by T20"
is "later ticket naming it without a shared code word, or a planner line: open" "$(col 6 5)" open
is "own second history line sharing a code word = shipped?" "$(row 7 | grep -oE 'shipped\? by T[0-9]+')" "shipped? by T13"
grep -qE "^L8 +T14 +$D3 +nightly wait +due nightly $D2" <<<"$out" && ok "next nightly with a later fleet-ci log = due" || nok "next nightly due" "$(row 8)"
is "next nightly with no later log: open" "$(col 9 6)" open
grep -qE "^L10 .* due $D1 " <<<"$out" && ok "named date passed = due" || nok "named date passed = due" "$(row 10)"
is "named date tomorrow: open" "$(col 11 6)" open
is "named date on the origin day and '6-10 dB' are no due dates" "$(row 12 | awk '{print $4, $5, $6}')" "seed open T18"
is "SKILL.md line = guide line" "$(row 13 | awk '{print $4, $5}')" "guide line"
is "no T-id: '-'" "$(col 14 2)" "-"
is "'1 decision' is no date" "$(row 15 | awk '{print $4, $5}')" "seed open"
is "'12-15 s' and '10-20 %' are no dates" "$(row 16 | awk '{print $4, $5}')" "seed open"
grep -qE "^L17 .* due $D1 " <<<"$out" && ok "impossible 02-30 drops only itself" || nok "impossible 02-30 drops only itself" "$(row 17)"
is "a 'Planner' (any case) line naming it is no shipped?" "$(col 18 5)" open
is "struck + only a (replaced …) note = struck" "$(col 19 5)" struck
is "struck + only a nested (checked …) note = struck" "$(col 20 5)" struck
is "struck + note + trailing text: open" "$(col 21 5)" open
is "a (note) alone with no strike: open" "$(col 22 5)" open
grep -qE "^L23 .* due $D1 " <<<"$out" && ok "'D Mon' date passed = due" || nok "'D Mon' date passed = due" "$(row 23)"
is "last line counts open/due/shipped? (struck not counted)" "$(tail -1 <<<"$out")" "12 open, 4 due, 2 shipped?"
grep -q '^L2 ' <<<"$(fu --open "$F")" && nok "--open hides struck lines" "L2 shown" || ok "--open hides struck lines"
is "--open keeps the counts line" "$(fu --open "$F" | tail -1)" "12 open, 4 due, 2 shipped?"
is "--json counts + lines" "$(fu --json "$F" | jq -c '[.open, .due, ."shipped?", .struck, (.lines | length), .lines[3].by]')" '[12,4,2,4,22,"T20"]'
fu "$W/missing.md" >/dev/null 2>&1; is "missing file rc 2" "$?" 2
mkdir -p "$AW/research/2026-10-19/T566"; cp "$F" "$AW/research/2026-10-19/T566/FOLLOWUPS.md"
is "default FILE under AGENT_WORK" "$(fu | tail -1)" "12 open, 4 due, 2 shipped?"

# fleet-survey: the section exists only when bin/followups does, and shows the counts line then due rows.
sv() { env -u HARNESS_HOME -u AGENT_WORK HOME="$FH" "$FS" "$@"; }
grep -q '^### followups' <<<"$(sv)" && nok "fleet-survey: no followups CLI, no section" "present" || ok "fleet-survey: no followups CLI, no section"
ln -s "$FU" "$A/bin/followups"
sec=$(sv --creative | awk '$0=="### followups"{f=1;next} /^###|^---/{f=0} f')
is "fleet-survey: counts line" "$(head -1 <<<"$sec")" "12 open, 4 due, 2 shipped?"
is "fleet-survey: due rows" "$(tail -n +2 <<<"$sec" | awk '{print $1, $2, $3}' | tr '\n' '|')" "L8 T14 due|L10 T16 due|L17 T32 due|L23 T36 due|"
# check: lines (T996): --checks lists them, --run judges due ones from the nightly's history rows, --apply strikes passes.
G="$W/CHECKS.md"; NL="$A/log/fleet-ci/$D2.txt"; mkdir -p "$A/state"
printf 'fleet-ci-daily %sT02:00:00+02:00\nok skills/gamedev/tests/cpp-play.test.sh 30.0\nok skills/gamedev/tests/cpp-audio.test.sh 40.0\nSKIP unchanged skills/x/tests/y.test.sh (green %s, 50 CPU s)\n' "$D2" "$D3" >"$NL"
printf '%s\t%s\t%s\t0\t1.0\t%s\n' "${D2}T01:00:00" skills/gamedev/tests/cpp-play.test.sh 30 999 \
  "${D2}T02:05:00" skills/gamedev/tests/cpp-play.test.sh 30 42.0 "${D2}T02:06:00" skills/gamedev/tests/cpp-audio.test.sh 40 150.0 \
  "${D2}T09:00:00" skills/gamedev/tests/cpp-play.test.sh 30 500 >"$A/state/test-timings-history.tsv"
cat >"$G" <<EOF
# checks
- T40 ($D3): next nightly: cpp-play cpu_s <= 60. check: \`le \$(cpu '/cpp-play\.') 60\`
- T41 ($D3): next nightly: cpp-audio cpu_s <= 60. check: \`le \$(cpu '/cpp-audio\.') 60\`
- T42 ($D3): next nightly: a slow check. check: \`sleep 37.913; true\`
- T43 ($D3): next nightly: no row for it. check: \`le \$(cpu '/cpp-none\.') 60\`
- T44 ($D3): $(md tomorrow): not due yet. check: \`true\`
- T45 ($D3): a seed whose check names a date and a flag. check: \`grep -q --fixed-strings 12-25 /dev/null\`
- ~~T46: done~~ (passed $D1 by followups --run)
- T47 ($D3): next nightly: skips. check: \`ge \$(grep -c '^SKIP unchanged' "\$NIGHTLY") 1 && newer "\$NIGHTLY" $D3\`
EOF
is "--checks lists unstruck lines with a check" "$(fu --checks "$G" | awk '{print $1}' | tr '\n' ' ')" "L2 L3 L4 L5 L6 L7 L9 "
is "a check's dates and code words do not classify the line" "$(fu "$G" | grep '^L7 ' | awk '{print $4, $5}')" "seed open"
is "the check is not part of the row text" "$(fu --json "$G" | jq -r '.lines[0] | [.text, .check, .runnable] | join("|")')" "T40 ($D3): next nightly: cpp-play cpu_s <= 60.|le \$(cpu '/cpp-play\\.') 60|true"
sum0=$(sha1sum <"$G"); t0=$(date +%s)
run=$(FOLLOWUPS_TIMEOUT=1 fu --run "$G"); rc=$?
is "--run rc 1 when a check fails" "$rc" 1
is "--run judges only due lines" "$(awk '/^L/{print $1, $2, $3}' <<<"$run" | tr '\n' '|')" "L2 T40 pass|L3 T41 fail|L4 T42 error|L5 T43 error|L9 T47 pass|"
grep -qE '^L2 .* 42\.0 <= 60$' <<<"$run" && ok "pass row: first nightly-pass history row only, comparison printed" || nok "pass row" "$run"
grep -qE '^L3 .* 150\.0 > 60$' <<<"$run" && ok "fail row prints the failed comparison" || nok "fail row" "$run"
grep -qE '^L4 .* timeout 1 s$' <<<"$run" && ok "a check over FOLLOWUPS_TIMEOUT is an error" || nok "timeout row" "$run"
grep -qE '^L5 .* le: no number \(60\)$' <<<"$run" && ok "no history row = error, not pass" || nok "no row = error" "$run"
is "--run summary" "$(tail -1 <<<"$run")" "2 pass, 1 fail, 2 error"
(( $(date +%s) - t0 < 8 )) && ok "the timed-out check does not hold --run" || nok "timeout holds --run" "$(( $(date +%s) - t0 )) s"
is "--run without --apply writes nothing" "$(sha1sum <"$G")" "$sum0"
is "--line runs that line, due or not" "$(fu --run --line 6 "$G" | head -1 | awk '{print $1, $3}')" "L6 pass"
fu --run --line 8 "$G" >/dev/null 2>&1; is "--line on a line with no check: rc 2" "$?" 2
fu --apply "$G" >/dev/null 2>&1; is "--apply without --run: rc 2" "$?" 2
FOLLOWUPS_TIMEOUT=1 fu --run --apply "$G" >/dev/null
is "--apply strikes passing lines whole" "$(sed -n 2p "$G")" "- ~~T40 ($D3): next nightly: cpp-play cpu_s <= 60. check: \`le \$(cpu '/cpp-play\\.') 60\`~~ (passed $(d today) by followups --run)"
is "--apply leaves fail/error lines" "$(sed -n 3,5p "$G" | grep -c '~~')" 0
is "struck by --run = struck; --checks drops them" "$(fu "$G" | grep -E '^L(2|9) ' | awk '{print $5}' | tr '\n' ' ')$(fu --checks "$G" | grep -cE '^L(2|9) ')" "struck struck 0"
exit "$bad"
