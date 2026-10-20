#!/usr/bin/env bash
# ticket-id on a fixture AGENT_WORK only: briefs, history, evidence, research and backlogs in a mktemp dir.
# shellcheck disable=SC1091,SC2154  # assert.sh sets bad
set -uo pipefail
. "$HOME/agents/bin/tests/lib/assert.sh"
TI="$HOME/agents/bin/ticket-id"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
AW="$W/aw"; B="$AW/briefs"; R="$AW/research/2026-10-19"
mkdir -p "$B" "$AW/evidence/T10" "$AW/evidence/T12" "$R/T5" "$R/T40" "$R/T60"
tid() { AGENT_WORK="$AW" "$TI" "$@"; }

printf '# T5 backlog wave 3: 3 tickets\n\n## 1. T10 First item\n## 2. T11 Second item\n## 3. Third item\n' >"$R/T5/BACKLOG.md"
printf '# T40 BACKLOG: harness wave (T41..T42)\n## T41 · dot heading\n' >"$R/T40/BACKLOG.md"
echo "# T60 backlog wave 4: 1 ticket" >"$R/T60/BACKLOG.md"
echo "# T61 — wave 4 #1 (from $R/T60/BACKLOG.md)" >"$B/T61-item.md"
echo "# T61 report: done" >"$B/T61-report.md"
echo "# T11 — client ticket ABC-1 (hand-numbered)" >"$B/T11-client.md"
echo "# T5 — planner wave 3" >"$B/T5-planner.md"
printf -- '- 2026-10-20 T10 (wave 3 #1): shipped\n- 2026-10-20 T12 (w3 #3): shipped\n- 2026-10-20 T5 planner: T10..T30 drafted\n' >"$AW/history.md"

is "next: above the highest id in any source (history range T30)" "$(tid next)" "T62"
echo "- 2026-10-20 T70 x" >>"$AW/history.md"
is "next -n 3: consecutive" "$(tid next -n 3 | tr '\n' ' ')" "T71 T72 T73 "
mkdir "$R/T90"; is "next: research dir counts" "$(tid next)" "T91"
mkdir "$AW/evidence/T95"; is "next: evidence dir counts" "$(tid next)" "T96"
printf '## 9. T120 Late\n' >>"$R/T5/BACKLOG.md"; is "next: backlog heading counts" "$(tid next)" "T121"
is "next: nothing written without --reserve" "$(ls "$B" | grep -c '^T12[1-9]')" 0

out=$(tid check T11); rc=$?
is "check double: rc 1" "$rc" 1
grep -qE '^backlog +T5#2 ' <<<"$out" && ok "check lists the backlog item" || nok "check lists the backlog item" "$out"
grep -qE '^brief +brief +~?.*T11-client\.md$' <<<"$out" && ok "check lists the brief" || nok "check lists the brief" "$out"
is "check double: summary" "$(tail -1 <<<"$out")" "T11: 2 uses, double use (2 owners: T5#2, brief)"

out=$(tid check T10); rc=$?
is "check one owner: rc 0" "$rc" 0
is "check one owner: backlog + history tag + evidence" "$(tail -1 <<<"$out")" "T10: 3 uses, one owner (T5#1)"
grep -qE '^history +T5#1 ' <<<"$out" && ok "history (wave N #k) tag maps to the item" || nok "history tag maps" "$out"
out=$(tid check T12); is "w3 #3 short tag maps too" "$(tail -1 <<<"$out")" "T12: 2 uses, one owner (T5#3)"
out=$(tid check T61); is "an unmapped report beside a mapped brief counts as a second owner" "$?:$(tail -1 <<<"$out")" "1:T61: 2 uses, double use (2 owners: T60#1, brief)"
out=$(tid check T41); is "dot heading: planner:T<n> owner" "$(tail -1 <<<"$out")" "T41: 1 uses, one owner (T40:T41)"
out=$(tid check 999); is "unused id: rc 0" "$?:$(tail -1 <<<"$out")" "0:T999: 0 uses, unused"
is "dups lists only the double uses" "$(tid dups | sed -E 's/ +/ /g' | tr '\n' '|')" "T11 T5#2, brief|T61 T60#1, brief|"

r=$(tid next -n 2 --reserve wave9 | tr '\n' ' ')
is "reserve: prints the ids" "$r" "T121 T122 "
is "reserve: stub briefs written" "$(head -1 "$B/T122-wave9.md" | sed 's/ ([0-9-]*)$//')" "# T122 — reserved by ticket-id: wave9"
is "reserve: next sees the stubs" "$(tid next)" "T123"
out=$(tid check T121); is "reserved stub: no owner, rc 0" "$?:$(tail -1 <<<"$out")" "0:T121: 1 uses, one owner (-)"
for i in 1 2 3 4 5 6; do tid next -n 3 --reserve "par$i" >"$W/par$i" & done; wait
all=$(cat "$W"/par[1-6])
is "parallel reserves: 18 ids" "$(wc -l <<<"$all")" 18
is "parallel reserves: all distinct" "$(sort -u <<<"$all" | wc -l)" 18
is "parallel reserves: one stub each" "$(ls "$B" | grep -c -- '-par[1-6]\.md$')" 18
is "parallel reserves: T123..T140" "$(sort -V <<<"$all" | sed -n '1p;$p' | tr '\n' ' ')" "T123 T140 "

is "plain next warns on stderr" "$(tid next 2>&1 >/dev/null)" "ticket-id: not reserved; parallel planners use --reserve SLUG"
echo "- 2026-10-20 T141 typo T14100 in a line" >>"$AW/history.md"
is "next: a typo jump > 100 is skipped" "$(tid next 2>/dev/null)" "T142"
tid next 2>&1 >/dev/null | grep -q 'skipped T14100' && ok "next: names the skipped typo" || nok "next: names the skipped typo" "$(tid next 2>&1)"
echo "- 2026-10-20 T150 real" >>"$AW/history.md"; is "next: a small gap still counts" "$(tid next 2>/dev/null)" "T151"
f139=$(ls "$B" | grep '^T139-'); f140=$(ls "$B" | grep '^T140-')
echo "real brief" >>"$B/$f139"
tid release T139 >/dev/null 2>&1; is "release: a stub with a body stays (rc 1)" "$?:$(ls "$B" | grep -c '^T139-')" "1:1"
out=$(tid release T140); is "release: rc 0, names the stub" "$?:$(basename "$out")" "0:$f140"
[ ! -e "$B/$f140" ] && ok "release: unused stub deleted" || nok "release: unused stub deleted" "$f140"
tid release T61 >/dev/null 2>&1; is "release: a real brief is never deleted" "$?:$(ls "$B" | grep -c '^T61-')" "1:2"
tid next --reserve 'Bad Slug' >/dev/null 2>&1; is "bad slug: rc 2" "$?" 2
tid check foo >/dev/null 2>&1; is "bad id: rc 2" "$?" 2
tid next -n 0 >/dev/null 2>&1; is "-n 0: rc 2" "$?" 2
is "empty AGENT_WORK: T1" "$(AGENT_WORK="$W/none" "$TI" next)" "T1"
[ ! -e "$W/none" ] && ok "empty AGENT_WORK: next writes nothing" || nok "empty AGENT_WORK: next writes nothing" "created"
"$TI" --help >/dev/null; is "--help: rc 0" "$?" 0
exit "$bad"
