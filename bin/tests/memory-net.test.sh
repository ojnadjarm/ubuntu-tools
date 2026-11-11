#!/usr/bin/env bash
# T1624-R1: the recall network core (lib/memory_cue.py, lib/memory_net.py, `memory net build|stats`, the build inside
# `memory apply`). Sandbox only (AGENTS.md §5.6): HOME, AGENT_WORK and MEMORY_HOME are temp dirs over a synthetic store
# written below (every fact invented); the selftest proves it is not the real store before any other case.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
MEM="$(dirname "$here")/memory"
LIB="$(dirname "$(dirname "$here")")/lib"
REAL_STORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$LIB")"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" AGENT_WORK="$T/aw" MEMORY_HOME="$T/store" HARNESS_CONFIG=/nonexistent
unset CLAUDE_CONFIG_DIR CHAT_SEAT MEMORY_DOMAINS
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
       GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
mkdir -p "$HOME" "$AGENT_WORK"
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
page core/ledger.md <<'EOF'
# Ledger
- 2026-10-20 · starter feeding changed · superseded ^k01 → ^k02
EOF
page domains/garden/DOMAIN.md <<'EOF'
# Garden card
- Tomatoes hate wet leaves at night. (26-10-05) → soil ^g01
- Compost turns faster with shredded cardboard. (26-10-07) ^g03
EOF
page domains/garden/soil.md <<'EOF'
# Soil
- Watering tomatoes at dusk invites blight. (26-10-05) ^s01
- Tomatoes need deep watering in july. (26-10-06) ^s03
- Clay drains slowly after a storm. (26-10-08) ^s02
EOF
page domains/kitchen/DOMAIN.md <<'EOF'
# Kitchen card
- Sourdough starter needs a daily feed of rye flour. (26-03-01) ^k01
EOF
page domains/kitchen/bread.md <<'EOF'
# Bread
- Sourdough starter now gets a weekly feed in the fridge. (26-10-20) ^k02
EOF
page domains/coast/DOMAIN.md <<'EOF'
# Coast card
- The harbour lantern is lit at the last crossing. (26-10-10) ^h01
- Ferry tickets are bought at the pier kiosk. (26-10-11) ^h02
EOF
page domains/barn/DOMAIN.md <<'EOF'
# Barn card
- Hay bales stack along the north wall. (26-10-01) ^b01
- Hay for the goats comes from the valley farm. (26-10-01) ^b02
- Wet hay gets spread out to dry. (26-10-01) ^b03
- The hay loft ladder has a loose rung. (26-10-01) ^b04
- Hay prices rise before winter. (26-10-01) ^b05
- Mice nest in old hay. (26-10-01) ^b06
EOF
page domains/secret/DOMAIN.md <<'EOF'
PRIVATE: boss
# Secret card
- Zanzibar vault code sits in the blue folder. (26-10-01) ^x01
EOF

# net <opts> -- <prompt>...: fire each prompt in one session on the built graph (private part merged);
# prints one line per prompt: `id@activation[paths]` per firing, `-` when silent.
net() {
  python3 - "$LIB" "$@" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import memory_cue, memory_net, memory_store
args = sys.argv[2:]
cut = args.index("--")
opts, prompts = args[:cut], args[cut + 1:]
g = memory_net.load(memory_store.Store(memory_store.home()), private=True)
for o in opts:
    k, _, v = o.partition("=")
    if k == "min-paths":
        memory_net.MIN_PATHS = int(v)
    elif k == "no-rivals":
        g.rivals = []
    elif k == "theta":
        i, t = v.split(":"); g.mem[i][2] = float(t)
    elif k == "move":
        i, p = v.split(":"); g.places[g.mem[i][0]].remove(i); g.mem[i][0] = p; g.places.setdefault(p, []).append(i)
session = {}
for p in prompts:
    f = memory_net.fire(g, memory_cue.cues(p, g), session)
    print(" ".join(f"{x.id}@{x.activation}[{','.join(x.path)}]" for x in f) or "-")
PY
}
ids() { sed -E "s/@[0-9.-]+//g"; }

# --- build and stats ---------------------------------------------------------------------------------------------
before="$("$MEM" net stats 2>&1)"
out="$("$MEM" net build 2>&1)"; rc=$?
is "net build: exit 0" "$rc" 0
ev "net build: 16 public and 1 private memories" '[[ "$out" == *"16 public and 1 private"* ]]'
ev "net build: graph.json and graph.private.json written" '[ -s "$S/net/graph.json" ] && [ -s "$S/net/graph.private.json" ]'
ev "net/.gitignore names both graph files" 'grep -qx graph.json "$S/net/.gitignore" && grep -qx graph.private.json "$S/net/.gitignore"'
ev "graph.json: no PRIVATE word or id" '! grep -qiE "zanzibar|x01" "$S/net/graph.json"'
ev "graph.private.json: the PRIVATE memory and its word" 'grep -q "\"x01\"" "$S/net/graph.private.json" && grep -q zanzibar "$S/net/graph.private.json"'
after="$("$MEM" net stats 2>&1)"
is "stats: the built public graph equals the one compiled without PRIVATE pages" "${after#*graph.json · }" "${before#*not built yet) · }"
ev "stats: memories 16, places, links printed" '[[ "$after" == *"memories 16 · places 7 · concept-memory "* ]]'

# --- the dynamic ---------------------------------------------------------------------------------------------------
is "threshold: a 2-path cue fires" "$(net -- 'watering at dusk' | ids)" "s01[dusk,water]"
is "threshold: the same cue under a raised threshold stays silent" "$(net theta=s01:99 -- 'watering at dusk')" "-"
is "2-path rule: one rare word is silent" "$(net -- 'blight')" "-"
is "2-path rule: the same word fires with the rule at 1 path (it is above threshold)" "$(net min-paths=1 -- 'blight' | ids)" "s01[blight]"
is "place inhibition: two 2-path lines in one place, one hint" "$(net -- 'watering tomatoes' | ids | wc -w)" 1
is "place inhibition: moved apart, both fire" "$(net move=s03:domains/garden/other.md -- 'watering tomatoes' | ids | wc -w)" 2
is "rival inhibition: of the old line and its replacement only the new one fires" "$(net -- 'sourdough starter feed' | ids)" \
  "k02[feed,sourdough,starter]"
is "rival inhibition: without the rival link both fire" "$(net no-rivals -- 'sourdough starter feed' | ids)" \
  "k02[feed,sourdough,starter] k01[feed,sourdough,starter]"
is "priming: lantern alone is silent" "$(net -- 'lantern')" "-"
is "priming: lantern fires after a harbour prompt in the same session" "$(net -- 'harbour weather' 'lantern' | ids)" \
  "$(printf -- '-\nh01[lantern,~harbour]')"
is "priming: an unrelated prompt does not prime" "$(net -- 'compost weather' 'lantern' | ids | tail -1)" "-"
is "priming: the trace alone never fires (no cue in this prompt)" "$(net -- 'sourdough starter feed' q | tail -1)" "-"
is "priming: the trace fades after 5 quiet prompts" "$(net -- 'harbour weather' q q q q q 'lantern' | tail -1)" "-"
w="$(python3 -c 'import json,sys; l=json.load(open(sys.argv[1]))["links"]; print(l["c:hay"]["m:b01"] < l["c:bale"]["m:b01"])' "$S/net/graph.json")"
is "fan effect: a word on 6 memories links weaker than a word on 1" "$w" True
a1="$(net -- 'hay north' | sed -E 's/.*@([0-9.]+).*/\1/')"; a2="$(net -- 'bale north' | sed -E 's/.*@([0-9.]+).*/\1/')"
ev "fan effect: two rare cues light b01 more than a common and a rare one ($a2 > $a1)" \
  'python3 -c "import sys; sys.exit(not $a2 > $a1)"'

# --- the build inside `memory apply` ------------------------------------------------------------------------------
rm -rf "$S/net"
git -C "$S" init -q -b main && git -C "$S" add -A && git -C "$S" commit -qm fixture
ST="$("$MEM" stage)"
"$MEM" apply "$ST" >"$T/apply.out" 2>&1; rc=$?
is "apply: green, exit 0" "$rc" 0
ev "apply: graph built in the store" '[ -s "$S/net/graph.json" ] && [ -s "$S/net/graph.private.json" ]'
is "apply: git tracks net/.gitignore only, never a graph file" "$(git -C "$S" ls-files net)" "net/.gitignore"
is "apply: the store is clean after the commit" "$(git -C "$S" status --porcelain)" ""

[ "$bad" = 0 ] && echo "all memory-net cases pass"
exit $bad
