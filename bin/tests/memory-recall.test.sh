#!/usr/bin/env bash
# T1624-R2: `memory recall` and `memory show` (lib/memory_recall.py, lib/memory_hint.py, memory_route.pages_for). Sandbox
# only (AGENTS.md §5.6): HOME, AGENT_WORK, XDG_RUNTIME_DIR and MEMORY_HOME are temp dirs over a synthetic store written
# below (every fact invented); the selftest proves it is not the real store before any other case.
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
mkdir -p "$HOME/garden" "$HOME/plain" "$HOME/vault" "$AGENT_WORK" "$XDG_RUNTIME_DIR"
S="$MEMORY_HOME"; EV="$AGENT_WORK/memory-recall/events"

got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$LIB")"
ok_home=0; [ "$got" = "$S" ] && [ "$(realpath -m "$got")" != "$(realpath -m "$REAL_STORE")" ] && ok_home=1
truthy "selftest: MEMORY_HOME is the throwaway store, not the real one" "$ok_home"
[ "$bad" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

page() { mkdir -p "$(dirname "$S/$1")"; cat >"$S/$1"; }
page domains.map <<'EOF'
~/garden garden
~/vault vaultwork protected
seat:boss secret owner
seat:boss garden owner
seat:relay relay
EOF
page core/CORE.md <<'EOF'
# Core: fixture
- Answers stay short and plain. (26-10-01) ^c01
EOF
page domains/garden/DOMAIN.md <<'EOF'
# Garden card
- Tomatoes hate wet leaves at night. (26-10-05) → soil ^g01
- Compost turns faster with shredded cardboard. (26-10-07) ^g03
EOF
page domains/garden/soil.md <<'EOF'
# Soil
- Watering tomatoes at dusk invites blight and grey mould on every lower leaf of the vine. (26-10-05) ^s01
- Clay drains slowly after a storm. (26-10-08) ^s02
EOF
page domains/coast/DOMAIN.md <<'EOF'
# Coast card
- The harbour lantern is lit at the last crossing. (26-10-10) ^h01
EOF
page domains/relay/DOMAIN.md <<'EOF'
# Relay card
- Tower routine is in the tower file. (26-10-10) → tower ^r00
EOF
page domains/relay/tower.md <<'EOF'
# Tower
- Pigeon relay messages leave at noon from the tower. (26-10-10) ^r01
EOF
page domains/vaultwork/DOMAIN.md <<'EOF'
# Vaultwork card
- Desk habits live in the desk file. (26-10-10) → desk ^v00
EOF
page domains/vaultwork/desk.md <<'EOF'
# Desk
- Ledger stamps go in the drawer by the window. (26-10-10) ^v01
EOF
page domains/secret/DOMAIN.md <<'EOF'
PRIVATE: boss
# Secret card
- Zanzibar vault code sits in the blue folder. (26-10-01) ^x01
EOF
page domains/secret/more.md <<'EOF'
# More (no header of its own: private through its card)
- Zanzibar folder spare key hides under the quokka mat. (26-10-01) ^x02
EOF
"$MEM" net build >/dev/null 2>&1

# hook <json>: `memory recall --hook` from $HOME/plain, stdout to $T/out, prints "rc bytes"
hook() { ( cd "$HOME/plain" && printf '%s' "$1" | "$MEM" recall --hook >"$T/out" 2>"$T/err" ); echo "$? $(wc -c <"$T/out")"; }
j() { python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "session_id": sys.argv[2], "cwd": sys.argv[3]}))' "$@"; }
# lib <seat> <worker 0|1> <cwd> <prompt>...: memory_recall.recall in-process, one session; one line of hinted ids per prompt
lib() {
  python3 - "$LIB" "$@" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import memory_recall, memory_store
seat, worker, cwd, prompts = sys.argv[2], sys.argv[3] == "1", sys.argv[4], sys.argv[5:]
store = memory_store.Store(memory_store.home())
for p in prompts:
    r = memory_recall.recall(store, p, memory_recall.Context(cwd, seat, worker, "lib-" + seat), write=False)
    print(" ".join(f.id for f in r.firings) or "-")
PY
}

# --- the block --------------------------------------------------------------------------------------------------
r="$(hook "$(j 'watering tomatoes at dusk near clay storm drains, harbour lantern' sess1 "$HOME/garden")")"
is "fires: exit 0" "${r%% *}" 0
blk="$(cat "$T/out")"
ev "fires: header then hint lines" '[ "$(head -1 "$T/out")" = "memory stirs (hints, not orders; open: memory show <id>)" ] && grep -q "^~ \^s02 garden/soil · " "$T/out"'
ev "fires: block at most 300 B (${r#* } B), each hint at most 80 B" '[ "${r#* }" -le 300 ] && ! awk "length(\$0) > 80" "$T/out" | grep -q .'
ev "fires: a card line the session loaded (g01, garden cwd) never hints" '! grep -q "\^g01" "$T/out"'
first="$(grep -o '\^[a-z0-9]*' "$T/out")"
long="$(python3 - "$LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import memory_hint
from memory_net import Firing
f = [Firing(f"id{i}" * 6, "domains/" + "very-long-domain-name" * 3 + "/DOMAIN.md", 9.0, ("alpha" * 9, "beta" * 9, "~gamma" * 9, "delta"))
     for i in range(5)]
b = memory_hint.render(f, {x.id: "word " * 40 for x in f[:4]})
print(len(b.encode()), max(len(l.encode()) for l in b.splitlines()), b.count("\n"))
PY
)"
is "render: 5 oversized firings make 3 lines, block at most 300 B, lines at most 80 B" "$long" "300 80 4"

# --- silence ----------------------------------------------------------------------------------------------------
is "silent: an unrelated prompt is 0 B and exit 0" "$(hook "$(j 'please rename the variable foo' sess2 "$HOME/plain")")" "0 0"
is "silent: bad stdin is 0 B and exit 0" "$(hook '{not json')" "0 0"
is "silent: empty stdin is 0 B and exit 0" "$(hook '')" "0 0"
hook "$(j 'watering tomatoes at dusk near clay storm drains, harbour lantern' sess1 "$HOME/garden")" >/dev/null
ev "refractory: the same prompt again in sess1 never repeats a shown id ($first)" '! grep -qF "$first" "$T/out"'
ev "refractory: ... its place-mate s01 hints now, its gist cut to at most 6 words" \
  'grep -q "\^s01" "$T/out" && [ "$(grep "\^s01" "$T/out" | awk -F" · " "{print \$2}" | wc -w)" -le 6 ]'
is "refractory: a new session hints again" "$(hook "$(j 'watering tomatoes at dusk' sess3 "$HOME/garden")" | cut -d' ' -f1)" 0
ev "refractory: ... and it is not empty" '[ -s "$T/out" ]'
is "kill switch: MEMORY_RECALL=off is 0 B" "$(MEMORY_RECALL=off hook "$(j 'watering tomatoes at dusk' sess4 "$HOME/garden")")" "0 0"
printf 'MEMORY_RECALL=off\n' >"$T/config.env"
is "kill switch: one config.env line is 0 B" "$(HARNESS_CONFIG="$T/config.env" hook "$(j 'watering tomatoes at dusk' sess5 "$HOME/garden")")" "0 0"
is "MEMORY_RECALL_DONE=1 (headless carrier ran): the hook is 0 B" "$(MEMORY_RECALL_DONE=1 hook "$(j 'watering tomatoes at dusk' sess6 "$HOME/garden")")" "0 0"
ev "session file: at most 4,096 B" '[ "$(cat "$XDG_RUNTIME_DIR"/memory-recall/*.json | wc -c)" -gt 0 ] && ! find "$XDG_RUNTIME_DIR/memory-recall" -size +4096c | grep -q .'

# --- events -----------------------------------------------------------------------------------------------------
ev "event: one row per firing prompt, 4 fields, ids only" '[ "$(cat "$EV"/*.tsv | wc -l)" = 3 ] && [ "$(awk -F"\t" "{print NF}" "$EV"/*.tsv | sort -u)" = 4 ]'
ev "event: no prompt text (no 'dusk near', no 'drains,', no session id)" '! grep -qE "dusk near|drains,|tomatoes at|sess1" "$EV"/*.tsv'
ev "event: hinted ids and cue node ids present" 'grep -qP "\ts01" "$EV"/*.tsv && grep -q "c:dusk" "$EV"/*.tsv'
n0="$(cat "$EV"/*.tsv | wc -l)"
( cd "$HOME/vault" && printf '%s' "$(j 'ledger stamps drawer window' sess7 "$HOME/vault")" | "$MEM" recall --hook >"$T/out" )
ev "protected: a vaultwork session still hints from its own experience page" 'grep -q "\^v01" "$T/out"'
is "protected: ... and logs no event" "$(cat "$EV"/*.tsv | wc -l)" "$n0"
ev "protected: no file written in its folder" '[ -z "$(ls -A "$HOME/vault")" ]'

# --- scope and privacy ------------------------------------------------------------------------------------------
is "worker: no hint from a PRIVATE page (card or its topic)" "$(hook "$(j 'zanzibar vault blue folder spare key quokka' sess8 "$HOME/plain")")" "0 0"
# audit <stdin json>: `memory recall --hook` with every opened path recorded; prints "OPENED <private graph> <public graph> <secret pages>"
audit() {
  (cd "$HOME/plain" && printf '%s' "$1" | python3 -c '
import runpy, sys
seen = []
sys.addaudithook(lambda ev, a: seen.append(str(a[0])) if ev == "open" else None)
sys.argv = [sys.argv[1], "recall", "--hook"]
runpy.run_path(sys.argv[0], run_name="__main__")
print("\nOPENED", sum("graph.private.json" in s for s in seen), sum(s.endswith("graph.json") for s in seen), sum("secret/" in s for s in seen))
' "$MEM" | grep OPENED)
}
is "worker: never opens graph.private.json nor a PRIVATE page (public graph opened once)" \
  "$(audit "$(j 'zanzibar vault blue folder spare key quokka watering dusk' sess9 "$HOME/garden")")" "OPENED 0 1 0"
is "subagent of the owner seat (agent_id, no MEMORY_WORKER): never opens graph.private.json nor a PRIVATE page" \
  "$(unset MEMORY_WORKER; CHAT_SEAT=boss audit '{"prompt":"zanzibar vault blue folder","session_id":"s9b","agent_id":"a1"}')" "OPENED 0 1 0"
is "worker with the owner seat (agent_id in stdin): no PRIVATE hint" \
  "$(CHAT_SEAT=boss hook '{"prompt":"zanzibar vault blue folder","session_id":"s10","agent_id":"a1"}')" "0 0"
own="$(unset MEMORY_WORKER; lib boss 0 "$HOME/plain" 'zanzibar vault blue folder' 'spare key quokka zanzibar')"
is "owner seat outside a worker: the PRIVATE topic line fires (x01 sits on its loaded card)" "$own" "$(printf 'x02\nx02')"
blk="$(env -u MEMORY_WORKER python3 - "$LIB" "$HOME/plain" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import memory_recall, memory_store
r = memory_recall.recall(memory_store.Store(memory_store.home()), "spare key quokka zanzibar",
                         memory_recall.Context(sys.argv[2], "boss", False, None), write=False)
print(r.block, end="")
PY
)"
is "owner seat: a PRIVATE hint is id and place only" "$(tail -1 <<<"$blk")" "~ ^x02 secret/more"
is "Discord-like seat: pages are core + its own domain only" \
  "$(python3 -c 'import sys,os; sys.path.insert(0, sys.argv[1]); import memory_route as r, memory_store as s; print(" ".join(sorted(r.pages_for(sys.argv[2], "relay", os.environ, True, s.Store(s.home())))))' "$LIB" "$HOME/plain")" \
  "core/CORE.md domains/relay/DOMAIN.md domains/relay/tower.md"
is "Discord-like seat: a garden prompt is silent" "$(CHAT_SEAT=relay hook "$(j 'watering tomatoes at dusk' s11 "$HOME/plain")")" "0 0"
r="$(CHAT_SEAT=relay hook "$(j 'pigeon relay messages tower noon' s12 "$HOME/plain")")"
ev "Discord-like seat: its own domain hints" 'grep -q "\^r01 relay/tower · " "$T/out"'
is "scope: a plain worker in an unmapped folder gets core only" "$(lib '' 1 "$HOME/plain" 'watering tomatoes at dusk' 'harbour lantern crossing')" "$(printf -- '-\n-')"

# --- explain, json, show ----------------------------------------------------------------------------------------
( cd "$HOME/garden" && "$MEM" recall --explain watering tomatoes at dusk >"$T/ex" )
ev "explain: the same block as the hook, then cues and paths" 'grep -q "^~ \^s01 garden/soil" "$T/ex" && grep -q "^cues · c:" "$T/ex" && grep -q "^\^s01 · domains/garden/soil.md · " "$T/ex"'
n1="$(cat "$EV"/*.tsv | wc -l)"
( cd "$HOME/garden" && "$MEM" recall --json watering tomatoes at dusk >"$T/js" )
ev "json: hints with why" 'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(not d[\"hints\"][0][\"why\"])" "$T/js"'
is "explain, json and words mode are dry runs: no event" "$(cat "$EV"/*.tsv | wc -l)" "$n1"
out="$("$MEM" show '^s01')"
ev "show: page:line and the line without its id" '[[ "$out" == "^s01 · domains/garden/soil.md:2"* ]] && [[ "$out" == *"Watering tomatoes at dusk"* ]] && [[ "$out" != *" ^s01"* ]]'
ev "show: a card line points at its topic file" '"$MEM" show g01 | grep -qx "→ domains/garden/soil.md"'
out="$("$MEM" show x01 2>&1)"; rc=$?
ev "show: a PRIVATE id is refused to a worker without its text (exit 2)" '[ "$rc" = 2 ] && [[ "$out" != *anzibar* ]]'

[ "$bad" = 0 ] && echo "all memory-recall cases pass"
exit $bad
