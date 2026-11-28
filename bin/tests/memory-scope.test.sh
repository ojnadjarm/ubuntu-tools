#!/usr/bin/env bash
# Fixture test for note scope and the core gate (T2054): a note carries where it was said and files narrow; a card line
# keeps his words out of the rule; a new core line needs a warrant. Fake HOME, synthetic store, never the real store.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
MEM="$(dirname "$here")/memory"
LIB="$(dirname "$(dirname "$here")")/lib"
REAL_STORE="$HOME/memory"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
H="$WORK/home"; S="$WORK/store"
mkdir -p "$H/.config/pc-harness" "$H/proj/zebra"
: >"$H/.config/pc-harness/config.env"
fx() { env -i PATH="$PATH" HOME="$H" HARNESS_CONFIG="$H/.config/pc-harness/config.env" MEMORY_HOME="$S" "$@"; }
home_of() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$LIB"; }

got=$(fx bash -c "$(declare -f home_of); LIB='$LIB'; home_of")
ok_home=0; [ "$got" = "$S" ] && [ "$(realpath -m "$got")" != "$(realpath -m "$REAL_STORE")" ] && ok_home=1
truthy "selftest: MEMORY_HOME resolves to the fixture store, not the real one" "$ok_home"
[ "$bad" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

mkdir -p "$S"/{core,inbox,archive,checks/ids.d} "$S/domains"/{zebra,quokka}
printf 'seat:boss quokka owner\n~/proj/zebra zebra\n' >"$S/domains.map"
printf -- '- Answer in two lines. (26-01-02) ^c01\n- He said "never paint the moon at night please". (26-01-02) ^c02\n' >"$S/core/CORE.md"
printf -- '- Zebras keep 7 stripes. (26-03-04) ^z01\n' >"$S/domains/zebra/DOMAIN.md"
printf -- '- Quokkas smile. ^q01\n' >"$S/domains/quokka/DOMAIN.md"
printf 'id\tpage\tstate\tsource\nc01\tcore/CORE.md\tlive\towner 26-01-02\nc02\tcore/CORE.md\tlive\towner 26-01-02\n' >"$S/checks/ids.d/core.tsv"
printf 'id\tpage\tstate\tsource\nz01\tdomains/zebra/DOMAIN.md\tlive\tagent 26-03-04\n' >"$S/checks/ids.d/zebra.tsv"
cp -r "$S" "$WORK/before"
last() { ls -t "$S"/inbox/*.md | head -1; }

# note: where it was said (task, folder and seat domains) is stamped; scope is narrowest unless --core.
(cd "$H/proj/zebra" && fx "$MEM" note --task T77 "stripes dry slowly" >/dev/null)
ev "note: task stamped" 'grep -qx "task: T77" "$(last)"'
ev "note: where = the folder's domain" 'grep -qx "where: zebra" "$(last)"'
ev "note: scope narrowest by default" 'grep -qx "scope: narrowest" "$(last)"'
(cd "$H" && fx "$MEM" note "no task here" >/dev/null)
ev "note: no task, no routed domain = -" 'grep -qx "task: -" "$(last)" && grep -qx "where: -" "$(last)"'
n=$(ls "$S"/inbox/*.md | wc -l)
(cd "$H/proj/zebra" && fx "$MEM" note --core "every zebra lesson is general" 2>"$WORK/err"); rc=$?
ev "note: --core from an agent refused (exit 2)" '[ "$rc" = 2 ] && grep -q "general" "$WORK/err"'
is "note: the refusal writes nothing" "$(ls "$S"/inbox/*.md | wc -l)" "$n"
(cd "$H" && fx env CHAT_SEAT=boss "$MEM" note --core "he wants calm words everywhere" --quote "calm words everywhere" >/dev/null)
ev "note: --core with his quote from his seat = scope core" 'grep -qx "scope: core" "$(last)" && grep -qx "source: owner" "$(last)"'
ev "note: --core and --domain together refused" '! (cd "$H" && fx env CHAT_SEAT=boss "$MEM" note --core --domain zebra "x" --quote "x" 2>/dev/null)'

chk() { fx "$MEM" check core domains --before "$WORK/before" 2>&1; }
# card-quotes: a new or changed card line quoting 4+ words; the old quoted line and a short trigger phrase pass.
out=$(chk); is "clean: no finding" "$out" ""
printf -- '- Zebras graze "when he says go" only. (26-03-05) ^z02\n' >>"$S/domains/zebra/DOMAIN.md"
printf 'z02\tdomains/zebra/DOMAIN.md\tlive\tagent 26-03-05\n' >>"$S/checks/ids.d/zebra.tsv"
out=$(chk); ev "card-quotes: a new line quoting 4 words is a finding" 'printf "%s\n" "$out" | grep -qE "^card-quotes · domains/zebra/DOMAIN\.md:2 · "'
sed -i 's/"when he says go"/on his "go"/' "$S/domains/zebra/DOMAIN.md"
out=$(chk); is "card-quotes: a short quoted trigger passes" "$out" ""
mkdir -p "$S/domains/vault"; printf 'PRIVATE: boss\n- He keeps "the purse in the oak chest" shut. (26-03-05) ^v01\n' >"$S/domains/vault/DOMAIN.md"
out=$(chk); is "card-quotes: a PRIVATE card with no before side (git-ignored) is not new" "$out" ""
rm -rf "$S/domains/vault"

# core-reach: a new core id needs `general`, `replaces ^cN` or 3 domains merged into it.
printf -- '- Zebras need shade at noon. (26-03-06) ^c03\n' >>"$S/core/CORE.md"
printf 'c03\tcore/CORE.md\tlive\tagent 26-03-06\n' >>"$S/checks/ids.d/core.tsv"
out=$(chk); ev "core-reach: a new core id from one domain is a finding" 'printf "%s\n" "$out" | grep -qE "^core-reach · core/CORE\.md:3 · \^c03"'
sed -i 's/^c03\tcore\/CORE.md\tlive\tagent 26-03-06$/c03\tcore\/CORE.md\tlive\towner 26-03-06 general/' "$S/checks/ids.d/core.tsv"
out=$(chk); is "core-reach: his general word passes" "$out" ""
sed -i 's/owner 26-03-06 general$/agent 26-03-06/' "$S/checks/ids.d/core.tsv"
printf 'z03\tdomains/zebra/DOMAIN.md\tmerged:c03\tagent\nq03\tdomains/quokka/DOMAIN.md\tmerged:c03\tagent\n' >>"$S/checks/ids.d/zebra.tsv"
out=$(chk); ev "core-reach: 2 domains merged is still a finding" 'printf "%s\n" "$out" | grep -q "^core-reach"'
printf 'id\tpage\tstate\tsource\nk03\tdomains/kiwi/DOMAIN.md\tmerged:c03\tagent\n' >"$S/checks/ids.d/kiwi.tsv"
out=$(chk); is "core-reach: 3 domains merged passes" "$out" ""
sed -i '/\^c02$/d' "$S/core/CORE.md"; printf -- '- Paint the moon only by day. (26-03-07) ^c04\n' >>"$S/core/CORE.md"
printf 'c04\tcore/CORE.md\tlive\towner 26-03-07\n' >>"$S/checks/ids.d/core.tsv"
sed -i 's/^c02\tcore\/CORE.md\tlive\t/c02\tcore\/CORE.md\tretired:superseded 26-03-07 by ^c04\t/' "$S/checks/ids.d/core.tsv"
fx python3 "$LIB/memory_quiz.py" merge >/dev/null
out=$(chk); is "core-reach: his newer word superseding a core line passes" "$out" ""

[ "$bad" = 0 ] && echo "all memory-scope cases pass"
exit $bad
