#!/usr/bin/env bash
# T1754-A: the spawn hooks (adapters/claude/hooks spawn-context, agent-spawn-gate, send-message-guard), their fragment
# wiring, and merge-settings.py keeping effortLevel. Stub harness/memory/spawn-gate and temp dirs only: no real store,
# gate, transcript or settings.json is read or written (the selftest proves the stubs answer).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
AG="$(dirname "$(dirname "$here")")"; HK="$AG/adapters/claude/hooks"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export XDG_RUNTIME_DIR="$T/run" HOME="$T/home"; mkdir -p "$XDG_RUNTIME_DIR" "$HOME" "$T/bin"

cat >"$T/bin/harness" <<'EOF'
#!/usr/bin/env bash
[ -n "${STUB_HARNESS_FAIL:-}" ] && exit 1
echo "Machine now: STUB"; echo "Worker rules: stub"
EOF
cat >"$T/bin/memory" <<'EOF'
#!/usr/bin/env bash
echo "$MEMORY_WORKER $*" >"$STUB_MEM_LOG"
printf '# memory: core\nCORE CARD\n\n'
for d in "${@:2}"; do printf '# memory: %s\n%s card\n' "$d" "$d"; [ -n "${STUB_MEM_BIG:-}" ] && head -c 12000 /dev/zero | tr '\0' x; echo; done
EOF
chmod +x "$T/bin/harness" "$T/bin/memory"
export SPAWN_CONTEXT_BIN="$T/bin" STUB_MEM_LOG="$T/mem.log"

TP="$T/parent.jsonl"
agent_row() { python3 -c 'import json,sys; print(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use",
  "name": "Agent", "id": sys.argv[1], "input": {"description": "fixture", "prompt": sys.argv[2], "subagent_type": "worker"}}]}}))' "$@"; }
sas() { printf '{"hook_event_name":"SubagentStart","agent_id":"%s","agent_type":"worker","transcript_path":"%s","cwd":"%s"}' "$1" "$TP" "$T"; }
ctx() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hookSpecificOutput"]["additionalContext"])' "$T/out"; }
spawn() { : >"$STUB_MEM_LOG"; echo "$1" | "$HK/spawn-context" >"$T/out"; echo $?; }

# Selftest: the hook reads the stub harness, not the real one.
agent_row tu0 "do a thing" >"$TP"
is "selftest: exit 0" "$(spawn "$(sas a0)")" 0
ev "selftest: the stub harness answers" 'ctx | grep -q "Machine now: STUB"'
[ "$bad" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

# 1. spawn-context
ev "context: no Memory: line gives the worker context only" '[ "$(ctx)" = "$(printf "Machine now: STUB\nWorker rules: stub")" ] && [ ! -s "$STUB_MEM_LOG" ]'
agent_row tu1 "$(printf 'Fix it.\nMemory: memory load alpha; memory load beta\n')" >>"$TP"
spawn "$(sas a1)" >/dev/null
ev "context: inline Memory: line loads its cards as a worker" 'grep -qx "1 load alpha beta" "$STUB_MEM_LOG" && ctx | grep -qx "alpha card" && ctx | grep -qx "beta card"'
ev "context: the core card is not printed again" '! ctx | grep -q "CORE CARD"'
printf 'Goal\nMemory: memory load gamma\n' >"$T/brief.md"
agent_row tu2 "Your brief is the file $T/brief.md. Read it whole." >>"$TP"
spawn "$(sas a2)" >/dev/null
ev "context: a brief file named in the prompt gives its Memory: cards" 'ctx | grep -q "Machine now: STUB" && ctx | grep -qx "gamma card"'
agent_row tu3 "Memory: memory load delta" >>"$TP"
STUB_MEM_BIG=1 spawn "$(sas a3)" >/dev/null
ev "context: over 10,000 characters, the machine line plus one memory load line" \
  'ctx | grep -q "Machine now: STUB" && ctx | grep -q "run \`memory load delta\`" && [ "$(ctx | wc -c)" -lt 10000 ]'
is "context: no agent_id is 0 B" "$(spawn '{"hook_event_name":"SubagentStart"}')$(wc -c <"$T/out")" "00"
agent_row tu4 "x" >>"$TP"
is "context: a failing harness is 0 B, exit 0" "$(STUB_HARNESS_FAIL=1 spawn "$(sas a4)")$(wc -c <"$T/out")" "00"
mkdir -p "$T/parent/subagents"; agent_row tu5 "Memory: memory load epsilon" >"$T/parent/subagents/agent-aplanner.jsonl"
spawn "$(sas a5)" >/dev/null
ev "context: a nested spawn finds its brief in the spawning sub-agent's transcript" 'ctx | grep -qx "epsilon card"'
is "context: bad JSON is 0 B, exit 0" "$(spawn 'nope')$(wc -c <"$T/out")" "00"

# 2. agent-spawn-gate
gate() { printf '#!/usr/bin/env bash\necho called >"%s/gate.log"\n%s\n' "$T" "$1" >"$T/gate"; chmod +x "$T/gate"; }
pre() { rm -f "$T/gate.log"; printf '{"tool_name":"Agent","tool_input":{"description":"%s","prompt":"p"}}' "$1" \
  | SPAWN_GATE_BIN="${2:-$T/gate}" "$HK/agent-spawn-gate" >"$T/out"; echo $?; }
deny() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["hookSpecificOutput"]; assert d["permissionDecision"]=="deny"; print(d["permissionDecisionReason"])' "$T/out"; }
gate 'echo "cpu busy 93 % (limit 90)"; exit 3'
is "gate: busy exits 0" "$(pre "T1 build")" 0
ev "gate: busy denies with the gate line and how to pass" 'deny | grep -q "^cpu busy 93 % (limit 90): wait" && deny | grep -qF "[light]"'
pre "T1 [light] fix" >/dev/null
ev "gate: [light] in the description passes without calling the gate" '[ ! -s "$T/out" ] && [ ! -e "$T/gate.log" ]'
gate 'exit 0'; pre "T1" >/dev/null
ev "gate: free CPU allows" '[ ! -s "$T/out" ] && [ -e "$T/gate.log" ]'
gate 'echo boom; exit 1'; pre "T1" >/dev/null
ev "gate: a failing gate allows" '[ ! -s "$T/out" ]'
pre "T1" "$T/absent" >/dev/null
ev "gate: an absent gate allows" '[ ! -s "$T/out" ]'
gate 'sleep 5; exit 3'; s=$(date +%s%N); pre "T1" >/dev/null; ms=$(( ($(date +%s%N) - s) / 1000000 ))
ev "gate: a slow gate allows in under 1 s (${ms} ms)" '[ ! -s "$T/out" ] && [ "$ms" -lt 1000 ]'

# 3. send-message-guard
S="$T/proj/sess"; mkdir -p "$S/subagents/workflows/wf_1"; : >"$S/subagents/workflows/wf_1/agent-a1b2c3d4e5f6a7b8c.jsonl"
: >"$S/subagents/agent-afedcba9876543210.jsonl"
send() { printf '{"tool_name":"SendMessage","transcript_path":"%s.jsonl","tool_input":{"to":"%s","message":"m"}}' "$S" "$1" \
  | "$HK/send-message-guard" >"$T/out"; echo $?; }
is "send: workflow agent exits 0" "$(send a1b2c3d4e5f6a7b8c)" 0
ev "send: a workflow agent is denied, the brief file named as the way out" 'deny | grep -q "brief file"'
send afedcba9876543210 >/dev/null; ev "send: a plain sub-agent is allowed" '[ ! -s "$T/out" ]'
send researcher >/dev/null; ev "send: a name is allowed" '[ ! -s "$T/out" ]'
is "send: bad JSON is 0 B, exit 0" "$(echo nope | "$HK/send-message-guard"; echo $?)" 0

# 4. fragment wiring and merge-settings.py
cat >"$T/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash"], "deny": ["Bash(x)"]}, "model": "opus", "effortLevel": "medium", "autoMode": {"on": true},
 "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "keep-me"}]}]}}
EOF
python3 "$AG/adapters/claude/merge-settings.py" install "$T/settings.json" "$AG/adapters/claude/settings.fragment.json" '$HOME/agents' >/dev/null
ev "fragment: SubagentStart spawn-context, PreToolUse Agent and SendMessage hooks wired" 'python3 - "$T/settings.json" <<'"'"'EOF'"'"'
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]
cmds = lambda ev, m=None: [x["command"] for g in h[ev] if m is None or g.get("matcher") == m for x in g["hooks"]]
assert "$HOME/agents/adapters/claude/hooks/spawn-context" in cmds("SubagentStart")
assert cmds("PreToolUse", "Agent") == ["$HOME/agents/adapters/claude/hooks/agent-spawn-gate"]
assert cmds("PreToolUse", "SendMessage") == ["$HOME/agents/adapters/claude/hooks/send-message-guard"]
assert h["Stop"][0]["hooks"][0]["command"] == "keep-me"
EOF'
python3 -c 'import json,sys; f=json.load(open(sys.argv[1])); f.update(effortLevel="high", model="fable", autoMode={"on": False}); json.dump(f, open(sys.argv[2], "w"))' \
  "$AG/adapters/claude/settings.fragment.json" "$T/frag.json"
python3 "$AG/adapters/claude/merge-settings.py" install "$T/settings.json" "$T/frag.json" '$HOME/agents' >/dev/null
ev "merge: effortLevel medium, model, autoMode and allow rules survive a fragment that says otherwise" 'python3 -c "
import json,sys; s=json.load(open(sys.argv[1]))
assert s[\"effortLevel\"]==\"medium\" and s[\"model\"]==\"opus\" and s[\"autoMode\"]=={\"on\": True} and s[\"permissions\"][\"allow\"]==[\"Bash\"]" "$T/settings.json"'
is "merge: a second merge is no change" \
  "$(python3 "$AG/adapters/claude/merge-settings.py" install "$T/settings.json" "$AG/adapters/claude/settings.fragment.json" '$HOME/agents')" "no changes"

# 5. the recall-hint legend
ev "legend: the hint block header says hints, not orders, and memory show <id>" \
  'python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import memory_hint as h; assert \"hints, not orders\" in h.HEADER and \"memory show <id>\" in h.HEADER" "$AG/lib"'

exit $bad
