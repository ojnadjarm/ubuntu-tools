#!/usr/bin/env bash
# T1827: recall hints never fire on filler words (doesn't, make sense, matter, thing) or on a weak two-word match; a
# prompt naming the real topic still stirs its memory. Sandbox only (AGENTS.md §5.6): HOME, AGENT_WORK, XDG_RUNTIME_DIR
# and MEMORY_HOME are temp dirs over a synthetic store (every fact invented); the selftest proves it is not the real one.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
MEM="$(dirname "$here")/memory"
LIB="$(dirname "$(dirname "$here")")/lib"
REAL_STORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$LIB")"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" AGENT_WORK="$T/aw" MEMORY_HOME="$T/store" XDG_RUNTIME_DIR="$T/run" HARNESS_CONFIG=/nonexistent
unset CLAUDE_CONFIG_DIR CHAT_SEAT MEMORY_DOMAINS MEMORY_RECALL MEMORY_RECALL_DONE CLAUDE_CODE_SESSION_ID MEMORY_WORKER
mkdir -p "$HOME" "$AGENT_WORK" "$XDG_RUNTIME_DIR"
S="$MEMORY_HOME"

got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$LIB")"
ok_home=0; [ "$got" = "$S" ] && [ "$(realpath -m "$got")" != "$(realpath -m "$REAL_STORE")" ] && ok_home=1
truthy "selftest: MEMORY_HOME is the throwaway store, not the real one" "$ok_home"
[ "$bad" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

page() { mkdir -p "$(dirname "$S/$1")"; cat >"$S/$1"; }
page domains.map <<'EOF'
seat:boss tower owner
EOF
page core/CORE.md <<'EOF'
# Core: fixture
- Answers stay short and plain. (26-10-01) ^c01
EOF
page core/taste.md <<'EOF'
# Taste
- "Both are related, I don't think it makes sense doing them in parallel.": one quilt shares one pattern. (26-09-27) ^c42
- Kite tails are drawn in ink, never in paint. (26-09-28) ^c43
EOF
page domains/tower/DOMAIN.md <<'EOF'
# Tower card
- Lantern rules live in the roadmap file. (26-10-10) → roadmap ^t00
EOF
page domains/tower/roadmap.md <<'EOF'
# Roadmap
- Lantern idle rate: 60 fps costs the shell a fifth of a core (30 fps half that); he said "it doesn't matter". (26-09-06) ^t75
- Pigeon relay leaves at noon from the tower roof. (26-10-10) ^t76
EOF
page domains/tower/briefs.md <<'EOF'
# Briefs
- His words (26-10-27): "adding a set of test for that doesn't make any sense". ^t74
EOF
page domains/shop/DOMAIN.md <<'EOF'
# Shop card
- Main-page modals: Kite Charts (the existing public demo video), Pigeon Post, Lantern (a static demo). (26-10-20) ^p13
- Shop copy: first person, plain, no jargon. (26-09-21) ^p04
EOF
"$MEM" net build >/dev/null 2>&1

# ids <prompt>: the ids the owner's seat would hint, one line ("-" for silence)
ids() {
  python3 - "$LIB" "$HOME" "$1" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import memory_recall, memory_store
r = memory_recall.recall(memory_store.Store(memory_store.home()), sys.argv[3],
                         memory_recall.Context(sys.argv[2], "boss", False, None), write=False)
print(" ".join(f.id for f in r.firings) or "-")
PY
}

a="$(ids "It doesn't matter the Axis I'm on, for me is just the time passing")"
ev "filler: 'doesn't matter' never stirs t75 (got: $a)" '! grep -qw t75 <<<"$a"'
b="$(ids "Still some artifacs but this is just a demo it doesn't make sense keep fixing this")"
ev "filler: 'doesn't make sense' never stirs t74 or c42 (got: $b)" '! grep -qwE "t74|c42" <<<"$b"'
d="$(ids "the lantern frame rate costs too much")"
ev "topic: 'lantern frame rate costs' still stirs t75 (got: $d)" 'grep -qw t75 <<<"$d"'
e="$(ids "the public demo video in the main page modals")"
ev "topic: 'demo video main page modals' still stirs p13 (got: $e)" 'grep -qw p13 <<<"$e"'

# The real store's weak hint: 'demo' + 'video', 2 of 6 cues, activation ~0.61 (pf13 at 0.623), on a page of another
# domain than the session's. Hand-built graph: the real fan cannot be grown in a small fixture.
weak="$(python3 - "$LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import memory_net, memory_recall
links = {"c:demo": {"m:p13": 3.758, "m:t13": 3.758}, "c:video": {"m:p13": 2.86, "m:t13": 2.86}}
links.update({"c:" + w: {f"m:z{i}": 3.0} for i, w in enumerate(["creat", "memory", "system", "work"])})
mem = {"p13": ["domains/shop/DOMAIN.md", -0.05, 0.5], "t13": ["domains/tower/DOMAIN.md", -0.05, 0.5]}
mem.update({f"z{i}": ["domains/garden/DOMAIN.md", -0.2, 0.5] for i in range(4)})
places = {}
for m, (p, _, _) in mem.items():
    places.setdefault(p, []).append(m)
g = memory_net.Graph(mem, links, places)
cues = [("c:" + w, 1 / 6) for w in ["demo", "video", "creat", "memory", "system", "work"]]
for near in (None, ("core/", "domains/tower/")):
    s = memory_recall.scope(g, {p: False for p in places}, set(), near)
    print(" ".join(f.id for f in memory_net.fire(s, cues)) or "-", end=";")
PY
)"
is "weak: a far page's 2-of-6-cue hint is silent in a session with its own domain; near and no-session ones fire" \
  "$weak" "p13 t13;t13;"

exit "$bad"
