#!/usr/bin/env bash
# T1624-R3: `memory check --recall` (lib/memory_recall_check.py) and `memory net build` following recall's privacy rule
# (memory_route.seats_of). Sandbox only (AGENTS.md §5.6): HOME, AGENT_WORK, XDG_RUNTIME_DIR and MEMORY_HOME are temp dirs
# over a synthetic store written below (every fact invented); the selftest proves it is not the real store first.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
MEM="$(dirname "$here")/memory"
LIB="$(dirname "$(dirname "$here")")/lib"
REAL_STORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$LIB")"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" AGENT_WORK="$T/aw" MEMORY_HOME="$T/store" XDG_RUNTIME_DIR="$T/run" HARNESS_CONFIG=/nonexistent
unset CLAUDE_CONFIG_DIR CHAT_SEAT MEMORY_DOMAINS MEMORY_RECALL MEMORY_RECALL_DONE CLAUDE_CODE_SESSION_ID
export MEMORY_WORKER=1
mkdir -p "$HOME" "$AGENT_WORK" "$XDG_RUNTIME_DIR"
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
page domains/coast/DOMAIN.md <<'EOF'
# Coast card
- The harbour lantern is lit at the last crossing. (26-10-10) ^h01
EOF
page domains/secret/DOMAIN.md <<'EOF'
PRIVATE: boss
# Secret card
- The vault code rotates monthly. (26-10-10) ^x01
EOF
page domains/secret/notes.md <<'EOF'
# Notes, no PRIVATE line of their own
- Quokka sightings cluster near the marmalade shed. (26-10-11) ^x02
EOF
mkdir -p "$S/checks/cues.d"
printf 'key\tdomain\tpage\tid\tquestion\tmust\tsource\n' >"$S/checks/questions.tsv"
cat >>"$S/checks/questions.tsv" <<'EOF'
q1	coast	domains/coast/DOMAIN.md	h01	Which lantern stays at the harbour?	crossing	fixture
q2	garden	domains/garden/DOMAIN.md	g03	What makes compost turn faster?	cardboard	fixture
q3	secret	domains/secret/notes.md	x02	Where do quokka sightings cluster?	shed	fixture
EOF
printf 'kind\tid\tcue\nquiet\t\twhat is a monad\nparaphrase\tg01\tdamp foliage after dark ruins the vines\n' >"$S/checks/cues.d/recall.tsv"

# Build follows recall's privacy rule: a page under a PRIVATE card is private even without its own PRIVATE line.
"$MEM" net build >/dev/null 2>&1
ev "net build: a page under a PRIVATE card stays out of graph.json (id and word)" '! grep -qiE "\"x02\"|quokka|marmalade" "$S/net/graph.json"'
ev "net build: that page goes to graph.private.json" 'grep -q "\"x02\"" "$S/net/graph.private.json" && grep -qi quokka "$S/net/graph.private.json"'

# The check: the table, the cues it counts, and the red lines.
out="$("$MEM" check --recall 2>&1)"
ev "check --recall: the section 6 table (6 metric rows)" '[ "$(grep -cE "^recall · (recall hit|hard-cue hit|false hints|wrong hints|bytes mean/max|ms p95 in process) · " <<<"$out")" = 6 ]'
ev "check --recall: a quiz cue aimed at a PRIVATE page is not counted (4 cues)" 'grep -q "^recall · ship gate · .* · 4 cues$" <<<"$out"'
ev "check --recall: both live quiz cues green before" '! grep -qE "^red · (q1|q2)$" <<<"$out"'
ev "check --recall: no cue text printed" '! grep -qiE "monad|harbour|foliage" <<<"$out"'
before="$(grep '^red · ' <<<"$out" | sort)"

python3 - "$S/net/graph.json" <<'EOF'
import json, sys
p = sys.argv[1]
g = json.load(open(p))
del g["links"]["c:lantern"]["m:h01"]
json.dump(g, open(p, "w"))
EOF
out2="$("$MEM" check --recall 2>&1)"
after="$(grep '^red · ' <<<"$out2" | sort)"
want="$(printf '%s\n%s\n' "$before" "red · q1" | grep -v '^$' | sort)"
is "a removed link (lantern -> h01) turns exactly its cue red" "$after" "$want"

exit $bad
