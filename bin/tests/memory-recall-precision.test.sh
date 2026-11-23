#!/usr/bin/env bash
# T1838: recall hints need a real second word and the conversation's support: bare numbers never count, a primed (~)
# word is never a cue path, harness text (hand-backs, task notifications) stirs nothing, and with recent owner prompts
# (the hook reads them from the transcript) a hint needs one of its words in them; a core topic line needs THETA_FAR.
# Sandbox only (AGENTS.md §5.6): HOME, AGENT_WORK, XDG_RUNTIME_DIR and MEMORY_HOME are temp dirs over a synthetic store
# (every fact invented); the selftest proves it is not the real one.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
AG="$(dirname "$(dirname "$here")")"
MEM="$AG/bin/memory"; LIB="$AG/lib"; HOOK="$AG/adapters/claude/hooks/memory-recall"
REAL_STORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$LIB")"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" AGENT_WORK="$T/aw" MEMORY_HOME="$T/store" XDG_RUNTIME_DIR="$T/run" HARNESS_CONFIG=/nonexistent
unset CLAUDE_CONFIG_DIR CHAT_SEAT MEMORY_DOMAINS MEMORY_RECALL MEMORY_RECALL_DONE CLAUDE_CODE_SESSION_ID
export MEMORY_WORKER=1
mkdir -p "$HOME/tower" "$AGENT_WORK" "$XDG_RUNTIME_DIR"
S="$MEMORY_HOME"

got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$LIB")"
ok_home=0; [ "$got" = "$S" ] && [ "$(realpath -m "$got")" != "$(realpath -m "$REAL_STORE")" ] && ok_home=1
truthy "selftest: MEMORY_HOME is the throwaway store, not the real one" "$ok_home"
[ "$bad" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

page() { mkdir -p "$(dirname "$S/$1")"; cat >"$S/$1"; }
page domains.map <<'EOF'
~/tower tower
EOF
page core/CORE.md <<'EOF'
# Core: fixture
- Answers stay short and plain. (26-10-01) ^c01
EOF
page domains/tower/DOMAIN.md <<'EOF'
# Tower card
- Tower notes live in topic files. (26-10-10) ^t00
EOF
page domains/tower/roadmap.md <<'EOF'
# Roadmap
- Lantern oil stays thick (thin: 2.1x smoke for -200 ml); a thick/thin sniff test is his memory call. (26-09-06) ^t73
EOF
page domains/tower/page.md <<'EOF'
# Page
- Why the phone page wins: the desktop renderer is finished as far as he cares; improve only the phone page. (26-09-15) ^t23
EOF
page domains/tower/videos.md <<'EOF'
# Videos
- The gameplay showcase is the main video: "amazing video". (26-10-27) ^t18
EOF
"$MEM" net build >/dev/null 2>&1

# ids <session|-> <recent JSON list|null> <prompt>: the ids recall hints in the tower folder, one line ("-" for silence)
ids() {
  python3 - "$LIB" "$HOME/tower" "$@" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import memory_recall, memory_store
sess = None if sys.argv[3] == "-" else sys.argv[3]
ctx = memory_recall.Context(sys.argv[2], "", True, sess, json.loads(sys.argv[4]))
r = memory_recall.recall(memory_store.Store(memory_store.home()), sys.argv[5], ctx, write=sess is not None)
print(" ".join(f.id for f in r.firings) or "-")
PY
}
LATER="Yeah let's improve that after the video finishes"

a="$(ids - null "Report: I read the last 200 owner prompts and the memory hints")"
ev "number: '200' is no cue, the report stirs no t73 (got: $a)" '! grep -qw t73 <<<"$a"'
b="$(ids - null "the thick lantern oil smoke")"
ev "topic: 'thick lantern oil smoke' still stirs t73 (got: $b)" 'grep -qw t73 <<<"$b"'

hb="$(printf 'Another Claude session sent a message:\n<agent-message from="a1">\n[Subagent hand-back] The report follows:\n  thick lantern oil smoke sniff test done\n</agent-message>')"
c="$(ids - null "$hb")"
is "harness text: a hand-back body stirs nothing" "$c" "-"
tn="$(printf '<task-notification>\n<task-id>a1</task-id>\n<result>thick lantern oil smoke sniff test done</result>\n</task-notification>')"
d="$(ids - null "$tn")"
is "harness text: a task-notification body stirs nothing" "$d" "-"

ids s1 '[]' "I am amazed how good the memory looks" >/dev/null
e="$(ids s1 '["I am amazed how good the memory looks"]' "$LATER")"
ev "primed word: 'video' + ~amaz is one path, t18 silent (got: $e)" '! grep -qw t18 <<<"$e"'
ev "support: 'improve' + 'finish' with no word of t23 in the talk, t23 silent (got: $e)" '! grep -qw t23 <<<"$e"'
f="$(ids - '["the phone page looks broken on my tailnet"]' "improve it after the renderer finishes")"
ev "support: the talk was about the phone page, t23 fires (got: $f)" 'grep -qw t23 <<<"$f"'
g="$(ids - null "improve it after the renderer finishes")"
ev "support: no talk read (first prompt, dry run), t23 fires on its two words (got: $g)" 'grep -qw t23 <<<"$g"'

# A core topic line is no session's own domain: a weak two-word match there (0.55) needs THETA_FAR like a far domain.
# Hand-built graph: the real fan cannot be grown in a small fixture.
page core/taste.md <<'EOF'
# Taste
- Kites fly at noon. (26-10-01) ^c42
EOF
page domains/tower/kites.md <<'EOF'
# Kites
- Kites fly at noon from the roof. (26-10-01) ^t42
EOF
k="$(python3 - "$LIB" "$HOME/tower" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import memory_net, memory_recall, memory_store
mem = {"c42": ["core/taste.md", -0.05, 0.5], "t42": ["domains/tower/kites.md", -0.05, 0.5]}
links = {"c:kite": {"m:c42": 1.0, "m:t42": 1.0}, "c:noon": {"m:c42": 1.0, "m:t42": 1.0}}
g = memory_net.Graph(mem, links, {"core/taste.md": ["c42"], "domains/tower/kites.md": ["t42"]})
memory_net.load = lambda store, private=False: g
r = memory_recall.recall(memory_store.Store(memory_store.home()), "kites at noon",
                         memory_recall.Context(sys.argv[2], "", True, None), write=False)
print(" ".join(f.id for f in r.firings) or "-")
PY
)"
is "core topic line: a 0.55 two-word match is silent, the same in the session's domain fires" "$k" "t42"

# The hook reads the recent owner prompts from the transcript: his prompts count, a hand-back row does not.
TP="$T/t.jsonl"
row() { python3 -c 'import json,sys; m=sys.argv[2]=="1"; print(json.dumps({"type": "user", "isMeta": m or None,
  "message": {"role": "user", "content": sys.argv[1]}}))' "$@"; }
hook() { python3 -c 'import json,sys; print(json.dumps({"hook_event_name": "UserPromptSubmit", "prompt": sys.argv[1],
  "session_id": sys.argv[2], "cwd": sys.argv[3], "transcript_path": sys.argv[4]}))' "$1" "$2" "$HOME/tower" "$TP" \
  | (cd "$HOME/tower" && "$HOOK"); }
{ row "make a cool video of how the memory works" 0; row "Another Claude session sent a message: the phone page renderer is finished" 1; } >"$TP"
h="$(hook "improve it after the renderer finishes" h1)"
ev "hook: a hand-back row is no support, t23 silent (got: ${h:-nothing})" '! grep -q "\^t23" <<<"$h"'
row "the phone page looks broken on my tailnet" 0 >>"$TP"
h="$(hook "improve it after the renderer finishes" h2)"
ev "hook: his prompt about the phone page supports t23 (got: ${h:-nothing})" 'grep -q "\^t23" <<<"$h"'

exit "$bad"
