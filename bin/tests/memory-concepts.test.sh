#!/usr/bin/env bash
# T1624-R5: the keeper's night concepts (net/concepts.d, lib/memory_concepts.py): the `memory check` lint, the network
# reading them (paraphrase and Spanish cues, keeper gist in the hint), private rows kept out of graph.json.
# Sandbox only (AGENTS.md §5.6): HOME, AGENT_WORK, XDG_RUNTIME_DIR and MEMORY_HOME are temp dirs over a synthetic store
# written below (every fact invented); the selftest proves it is not the real store first.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
MEM="$(dirname "$here")/memory"
LIB="$(dirname "$(dirname "$here")")/lib"
REAL_STORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$LIB")"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" AGENT_WORK="$T/aw" MEMORY_HOME="$T/store" XDG_RUNTIME_DIR="$T/run" HARNESS_CONFIG=/nonexistent
unset CLAUDE_CONFIG_DIR CHAT_SEAT MEMORY_DOMAINS MEMORY_RECALL MEMORY_RECALL_DONE CLAUDE_CODE_SESSION_ID
mkdir -p "$HOME/garden" "$AGENT_WORK" "$XDG_RUNTIME_DIR"
S="$MEMORY_HOME"

got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$LIB")"
ok_home=0; [ "$got" = "$S" ] && [ "$(realpath -m "$got")" != "$(realpath -m "$REAL_STORE")" ] && ok_home=1
truthy "selftest: MEMORY_HOME is the throwaway store, not the real one" "$ok_home"
[ "$bad" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

page() { mkdir -p "$(dirname "$S/$1")"; cat >"$S/$1"; }
page domains.map <<'EOF'
~/garden garden
seat:boss secret
EOF
page core/CORE.md <<'EOF'
# Core: fixture
- Answers stay short and plain. (26-10-01) ^c01
EOF
page domains/garden/DOMAIN.md <<'EOF'
# Garden card
- Tomatoes hate wet leaves at night. (26-10-05) ^g01
- Compost turns faster with shredded cardboard. (26-10-07) ^g03
EOF
page domains/garden/soil.md <<'EOF'
# Garden soil
- Clay soil drains slowly after rain. (26-10-08) ^g05
EOF
page domains/secret/DOMAIN.md <<'EOF'
PRIVATE: boss
# Secret card
- The vault code rotates monthly. (26-10-10) ^x01
EOF
H=$'id\tgist\tconcepts\twhen\tes'
good() {
  mkdir -p "$S/net/concepts.d"
  printf '%s\n%s\n' "$H" $'c01\tterse plain replies\tbrevity, concise wording, short answer\twriting a reply, summarising\trespuesta corta, brevedad, resumen' >"$S/net/concepts.d/core.tsv"
  printf '%s\n%s\n%s\n%s\n' "$H" \
    $'g01\tkeep tomato foliage dry evenings\tdamp foliage, vine rot, evening watering\twatering after dark, mildew on vines\thojas mojadas, riego nocturno, jardín húmedo' \
    $'g03\tcardboard speeds compost\tdecomposition speed, brown material\tslow compost pile, what to add\tcompostaje, cartón triturado' \
    $'g05\tclay soil drains slowly\tsticky earth, puddles, waterlogging\tbeds stay soggy, planting after storms\tsuelo arcilloso, barro' \
    >"$S/net/concepts.d/garden.tsv"
  printf '%s\n%s\n' "$H" $'x01\tvault code rotation\tsafe combination, monthly change\topening the safe, changing the code\tcaja fuerte, combinación' \
    >"$S/net/concepts.d/private-secret.tsv"
}
lint() { "$MEM" check 2>&1 | grep "^concepts · " || true; }
fires() { python3 - "$LIB" "$1" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import memory_recall_check, memory_store
print(" ".join(f.id for f in memory_recall_check.network(memory_store.Store(memory_store.home()))(sys.argv[2])))
EOF
}

# Before any concepts file: no lint, and the paraphrase and Spanish cues stay silent.
ev "no concepts.d: the lint stays quiet (older stores unchanged)" '[ -z "$(lint)" ]'
ev "no concepts: a paraphrase cue does not reach g01" '[[ " $(fires "damp foliage rots the vines") " != *" g01 "* ]]'
ev "no concepts: a Spanish cue does not reach g01" '[[ " $(fires "las hojas mojadas y el riego nocturno") " != *" g01 "* ]]'

good
ev "valid concepts files: lint green" '[ -z "$(lint)" ]'
ev "concepts: a paraphrase cue fires g01" '[[ " $(fires "damp foliage rots the vines") " == *" g01 "* ]]'
ev "concepts: a Spanish cue fires g01" '[[ " $(fires "las hojas mojadas y el riego nocturno") " == *" g01 "* ]]'
ev "concepts: a Spanish cue typed without accents still fires g01" '[[ " $(fires "jardin humedo con hojas mojadas") " == *" g01 "* ]]'
ev "concepts: a quiet prompt stays silent" '[ -z "$(fires "what is a monad in category theory")" ]'

"$MEM" net build >/dev/null 2>&1
ev "net build: .gitignore lists the private concepts files" 'grep -qx "concepts.d/private-\*.tsv" "$S/net/.gitignore"'
ev "net build: a private row stays out of graph.json" '! grep -qiE "combinaci|caja|\"x01\"" "$S/net/graph.json"'
ev "net build: a private row reaches graph.private.json" 'grep -qi "combinacion" "$S/net/graph.private.json"'
out="$(cd "$HOME/garden" && "$MEM" recall --explain "waterlogging and puddles in the beds" 2>&1)"
ev "recall: the hint carries the keeper gist, not the line's first words" 'grep -q "\^g05 garden/soil · clay soil drains slowly" <<<"$out"'

# The lint, one fault at a time.
bad_row() { good; printf '%s\n' "$1" >>"$S/net/concepts.d/${2:-garden}.tsv"; lint; }
ev "lint: a live public id without a row" 'good; sed -i "/^g03/d" "$S/net/concepts.d/garden.tsv"; lint | grep "garden.tsv:0 · ^g03 has no concepts row" >/dev/null'
ev "lint: a wrong header" 'good; sed -i "1s/.*/id gist/" "$S/net/concepts.d/core.tsv"; lint | grep "core.tsv:1 · header is not" >/dev/null'
ev "lint: a row over 200 characters" 'bad_row "g09	long	$(printf "word%.0s, " {1..40})	x	y" | grep "characters, the limit is 200" >/dev/null'
ev "lint: a gist over 6 words" 'bad_row "g01	one two three four five six seven	a, b	c	d" | grep "gist over 6 words" >/dev/null'
ev "lint: not 5 columns" 'bad_row "g01	gist only" | grep "not 5 tab-separated columns" >/dev/null'
ev "lint: no Spanish aliases" 'bad_row "g01	a gist	a, b	c	" | grep "no concepts or no Spanish aliases" >/dev/null'
ev "lint: an id that is not live" 'bad_row "g99	a gist	a, b	c	d" | grep "\^g99 is not a live id" >/dev/null'
ev "lint: a duplicate row" 'bad_row "g01	a gist	a, b	c	d" | grep "\^g01 has a row already" >/dev/null'
ev "lint: a row in another domain's file" 'good; sed -i "/^c01/d" "$S/net/concepts.d/core.tsv"; printf "c01\ta gist\ta, b\tc\td\n" >>"$S/net/concepts.d/garden.tsv"; lint | grep "\^c01 lives in domain core, not garden" >/dev/null'
ev "lint: a PRIVATE id in a tracked file" 'good; rm "$S/net/concepts.d/private-secret.tsv"; printf "x01\ta gist\ta, b\tc\td\n" >>"$S/net/concepts.d/secret.tsv"; sed -i "1i $H" "$S/net/concepts.d/secret.tsv"; lint | grep "\^x01 is on a PRIVATE page" >/dev/null'
ev "lint: no row text printed" '! bad_row "g01	a gist	a, b	c	d" | grep -i "hojas\|foliage" >/dev/null'

exit $bad
