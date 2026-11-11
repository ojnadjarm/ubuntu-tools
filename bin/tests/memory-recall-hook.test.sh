#!/usr/bin/env bash
# T1624-R6: the recall carriers. adapters/claude/hooks/memory-recall (UserPromptSubmit and SubagentStart), the fragment's
# two hook entries, and adapters/claude/run's `memory recall --file` in the system text. Sandbox only (AGENTS.md §5.6):
# HOME, AGENT_WORK, XDG_RUNTIME_DIR and MEMORY_HOME are temp dirs over an invented store; `claude` is a fake that dumps
# its argv. The selftest proves the store is not the real one before any other case.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
. "$here/lib/budget.sh"
AG="$(dirname "$(dirname "$here")")"
MEM="$AG/bin/memory"; HOOK="$AG/adapters/claude/hooks/memory-recall"
REAL_STORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$AG/lib")"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" AGENT_WORK="$T/aw" MEMORY_HOME="$T/store" XDG_RUNTIME_DIR="$T/run" HARNESS_CONFIG=/nonexistent
unset CLAUDE_CONFIG_DIR CHAT_SEAT MEMORY_DOMAINS MEMORY_RECALL MEMORY_RECALL_DONE CLAUDE_CODE_SESSION_ID
export MEMORY_WORKER=1
mkdir -p "$HOME/garden" "$HOME/plain" "$HOME/vault" "$AGENT_WORK" "$XDG_RUNTIME_DIR"
S="$MEMORY_HOME"; HL="$AGENT_WORK/memory-recall/hooks"

got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$AG/lib")"
ok_home=0; [ "$got" = "$S" ] && [ "$(realpath -m "$got")" != "$(realpath -m "$REAL_STORE")" ] && ok_home=1
truthy "selftest: MEMORY_HOME is the throwaway store, not the real one" "$ok_home"
[ "$bad" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

page() { mkdir -p "$(dirname "$S/$1")"; cat >"$S/$1"; }
page domains.map <<'EOF'
~/garden garden
~/vault vaultwork protected
EOF
page core/CORE.md <<'EOF'
# Core: fixture
- Answers stay short and plain. (26-10-01) ^c01
EOF
page domains/garden/DOMAIN.md <<'EOF'
# Garden card
- Soil notes live in the soil file. (26-10-05) → soil ^g01
EOF
page domains/garden/soil.md <<'EOF'
# Soil
- Watering tomatoes at dusk invites blight and grey mould on every lower leaf of the vine. (26-10-05) ^s01
- Clay drains slowly after a storm. (26-10-08) ^s02
EOF
page domains/vaultwork/DOMAIN.md <<'EOF'
# Vaultwork card
- Ledger stamps go in the drawer by the window. (26-10-10) ^v01
EOF
"$MEM" net build >/dev/null 2>&1

FIRE='watering tomatoes at dusk near clay storm drains'
# run <dir> <json>: the hook from <dir>, stdout to $T/out; prints "rc bytes"
run() { ( cd "$1" && printf '%s' "$2" | "$HOOK" >"$T/out" 2>"$T/err" ); echo "$? $(wc -c <"$T/out")"; }
ups() { python3 -c 'import json,sys; print(json.dumps({"hook_event_name": "UserPromptSubmit", "prompt": sys.argv[1],
  "session_id": sys.argv[2], "cwd": sys.argv[3], "source": "poll_event"}))' "$@"; }

r="$(run "$HOME/garden" "$(ups "$FIRE" s1 "$HOME/garden")")"
is "prompt: exit 0" "${r%% *}" 0
ev "prompt: the hint block, at most 300 B (${r#* } B)" '[ "${r#* }" -gt 0 ] && [ "${r#* }" -le 300 ] && head -1 "$T/out" | grep -q "^memory stirs"'
is "prompt: nothing on stderr" "$(wc -c <"$T/err")" 0
is "silent: an unrelated prompt is 0 B, exit 0" "$(run "$HOME/plain" "$(ups 'rename the variable foo' s2 "$HOME/plain")")" "0 0"
is "bad stdin: not JSON is 0 B, exit 0" "$(run "$HOME/plain" '{not json')" "0 0"
is "bad stdin: empty is 0 B, exit 0" "$(run "$HOME/plain" '')" "0 0"
is "bad stdin: a JSON list is 0 B, exit 0" "$(run "$HOME/plain" '[1,2]')" "0 0"
is "bad stdin: a numeric prompt is 0 B, exit 0" "$(run "$HOME/plain" '{"prompt": 7, "session_id": 3}')" "0 0"
is "broken store: MEMORY_HOME missing is 0 B, exit 0" \
  "$(MEMORY_HOME="$T/nowhere" run "$HOME/plain" "$(ups "$FIRE" s3 "$HOME/plain")")" "0 0"
is "MEMORY_RECALL_DONE=1 (headless carrier ran): the prompt hook is 0 B" \
  "$(MEMORY_RECALL_DONE=1 run "$HOME/plain" "$(ups "$FIRE" s4 "$HOME/plain")")" "0 0"

# SubagentStart: the brief is the parent transcript's pending Agent call; the block comes back as additionalContext.
TP="$T/parent.jsonl"
agent_row() { python3 -c 'import json,sys; print(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use",
  "name": "Agent", "id": sys.argv[1], "input": {"description": "fixture", "prompt": sys.argv[2], "subagent_type": sys.argv[3]}}]}}))' "$@"; }
sas() { printf '{"hook_event_name":"SubagentStart","agent_id":"%s","agent_type":"%s","transcript_path":"%s","cwd":"%s","session_id":"p1"}' \
  "$1" "$2" "$TP" "$HOME/garden"; }
{ agent_row tu1 'rename the variable foo' worker; agent_row tu2 "$FIRE" Explore; } >"$TP"
r="$(MEMORY_RECALL_DONE=1 run "$HOME/garden" "$(sas a1 Explore)")"
is "subagent: exit 0" "${r%% *}" 0
ev "subagent: additionalContext JSON holding the block of its own Agent call (same subagent_type)" \
  'python3 -c "import json,sys; d=json.load(open(sys.argv[1]))[\"hookSpecificOutput\"]; assert d[\"hookEventName\"]==\"SubagentStart\"; assert d[\"additionalContext\"].startswith(\"memory stirs\"); assert len(d[\"additionalContext\"].encode())<=300" "$T/out"'
is "subagent: the call already taken is not taken twice, the other one is silent" "$(run "$HOME/plain" "$(sas a2 worker)")" "0 0"
is "subagent: no pending Agent call is 0 B, exit 0" "$(run "$HOME/plain" "$(sas a3 worker)")" "0 0"
is "subagent: a missing transcript is 0 B, exit 0" \
  "$(run "$HOME/plain" '{"hook_event_name":"SubagentStart","agent_id":"a4","transcript_path":"/nonexistent.jsonl"}')" "0 0"

# Carrier rows: one per hook call, 5 ids-only fields, the input's source kept, no prompt text, none in a protected folder.
ev "hooks row: 5 fields each, source poll_event kept" '[ "$(cat "$HL"/*.tsv | awk -F"\t" "{print NF}" | sort -u)" = 5 ] && cut -f3 "$HL"/*.tsv | grep -qx poll_event'
ev "hooks row: SubagentStart logged with its bytes" 'awk -F"\t" "\$2==\"SubagentStart\" && \$5>0" "$HL"/*.tsv | grep -q .'
ev "hooks row: no prompt text, no session id" '! grep -qE "tomatoes|dusk|rename|\bs1\b|\bp1\b" <(cut -f2- "$HL"/*.tsv)'
n="$(cat "$HL"/*.tsv | wc -l)"
run "$HOME/vault" "$(ups 'ledger stamps drawer window' s5 "$HOME/vault")" >/dev/null
is "protected folder: no hooks row" "$(cat "$HL"/*.tsv | wc -l)" "$n"
ev "protected folder: no file written in it" '[ -z "$(ls -A "$HOME/vault")" ]'

# Cold-process wall time: p95 over 50 runs of a firing prompt (fresh session each, so it really fires).
p95="$(for i in $(seq 50); do
  j="$(ups "$FIRE" "t$i" "$HOME/garden")"
  a=$(date +%s%N); printf '%s' "$j" | ( cd "$HOME/garden" && "$HOOK" >/dev/null ); b=$(date +%s%N)
  echo $(( (b - a) / 1000000 ))
done | sort -n | sed -n 48p)"
lim="$(awk -v b="$(budget 0.08)" 'BEGIN{printf "%d", b*1000}')"
ev "speed: p95 ${p95} ms over 50 cold runs (limit 80 ms, load-scaled ${lim})" '[ "$p95" -le "$lim" ]'

# The fragment: one UserPromptSubmit entry and a SubagentStart entry beside orbit-hook, both this script, timeout 2.
echo '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "keep-me"}]}]}}' >"$T/settings.json"
python3 "$AG/adapters/claude/merge-settings.py" install "$T/settings.json" "$AG/adapters/claude/settings.fragment.json" '$HOME/agents' >/dev/null
ev "fragment: UserPromptSubmit and SubagentStart carry the hook (timeout 2), orbit-hook and Stop kept" 'python3 - "$T/settings.json" <<'"'"'EOF'"'"'
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]
cmd = "$HOME/agents/adapters/claude/hooks/memory-recall"
mine = lambda ev: [x for g in h[ev] for x in g["hooks"] if x["command"] == cmd]
assert [x["timeout"] for x in mine("UserPromptSubmit")] == [2] and [x["timeout"] for x in mine("SubagentStart")] == [2]
assert any("orbit-hook start" in x["command"] for g in h["SubagentStart"] for x in g["hooks"])
assert h["Stop"][0]["hooks"][0]["command"] == "keep-me"
EOF'
is "fragment: a second merge is no change" \
  "$(python3 "$AG/adapters/claude/merge-settings.py" install "$T/settings.json" "$AG/adapters/claude/settings.fragment.json" '$HOME/agents')" "no changes"

# Headless: adapters/claude/run puts `memory recall --file` after `memory load` in the system text, and marks the run done.
mkdir -p "$T/bin" "$T/hl"
cat >"$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
{ printf '%s\0' "$@"; printf 'DONE=%s\0' "${MEMORY_RECALL_DONE:-}"; } >"$FAKE_ARGS"
echo '{"type":"result","result":"ok","usage":{}}'
EOF
chmod +x "$T/bin/claude"
printf 'Please look at %s.\n' "$FIRE" >"$T/hl/prompt.md"
( cd "$T/hl" && PATH="$T/bin:$AG/bin:$PATH" FAKE_ARGS="$T/args" MEMORY_DOMAINS=garden PROMPT_FILE="$T/hl/prompt.md" MODEL=fixture \
  RAW_OUT="$T/hl/raw.json" META_OUT="$T/hl/meta.json" "$AG/adapters/claude/run" >/dev/null 2>&1 )
sysp="$(python3 -c 'import sys; a=open(sys.argv[1],"rb").read().split(b"\0"); print(a[a.index(b"--append-system-prompt")+1].decode())' "$T/args" 2>/dev/null)"
ev "headless: the system text holds the memory card, then the hint block" \
  'printf "%s" "$sysp" | grep -q "^# Garden card" && printf "%s" "$sysp" | grep -q "^memory stirs" && [ "$(printf "%s" "$sysp" | grep -n "^memory stirs" | cut -d: -f1)" -gt "$(printf "%s" "$sysp" | grep -n "^# Garden card" | cut -d: -f1)" ]'
ev "headless: claude runs with MEMORY_RECALL_DONE=1 (the prompt hook stays silent there)" 'grep -qa "DONE=1" "$T/args"'
ev "headless: the hint lines are at most 300 B" '[ "$(printf "%s" "$sysp" | sed -n "/^memory stirs/,\$p" | wc -c)" -le 301 ]'

[ "$bad" = 0 ] && echo "all memory-recall-hook cases pass"
exit $bad
