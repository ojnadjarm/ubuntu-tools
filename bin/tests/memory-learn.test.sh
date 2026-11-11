#!/usr/bin/env bash
# T1624-R4: learning from use (lib/memory_learn.py, lib/memory_fold.py, the fold in `memory apply`). Sandbox only
# (AGENTS.md §5.6): HOME, AGENT_WORK, HARNESS_HOME (audit log), XDG_RUNTIME_DIR and MEMORY_HOME are temp dirs over a
# synthetic store written below (every fact invented); the selftest proves it is not the real store before any other case.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
MEM="$(dirname "$here")/memory"
LIB="$(dirname "$(dirname "$here")")/lib"
REAL_STORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$LIB")"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" AGENT_WORK="$T/aw" MEMORY_HOME="$T/store" XDG_RUNTIME_DIR="$T/run" HARNESS_HOME="$T/harness" \
       HARNESS_CONFIG=/nonexistent
unset CLAUDE_CONFIG_DIR CHAT_SEAT MEMORY_DOMAINS MEMORY_RECALL MEMORY_RECALL_DONE CLAUDE_CODE_SESSION_ID MEMORY_WORKER
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
       GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
mkdir -p "$HOME/plain" "$HOME/vault" "$AGENT_WORK" "$XDG_RUNTIME_DIR" "$HARNESS_HOME/log"
S="$MEMORY_HOME"; EV="$AGENT_WORK/memory-recall/events"; AUD="$HARNESS_HOME/log/actions.jsonl"; D=2026-01-10

got="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$LIB")"
ok_home=0; [ "$got" = "$S" ] && [ "$(realpath -m "$got")" != "$(realpath -m "$REAL_STORE")" ] && \
  [ "$(realpath -m "$AUD")" != "$(realpath -m ~/agents/log/actions.jsonl)" ] && ok_home=1
truthy "selftest: MEMORY_HOME and the audit log are throwaway, not the real ones" "$ok_home"
[ "$bad" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

page() { mkdir -p "$(dirname "$S/$1")"; cat >"$S/$1"; }
page domains.map <<'EOF'
~/vault vaultwork protected
seat:boss secret owner
EOF
page core/CORE.md <<'EOF'
# Core: fixture
- Answers stay short and plain. (26-10-01) ^c01
EOF
page domains/coast/DOMAIN.md <<'EOF'
# Coast card
- The harbour lantern guides the ferry home. (26-10-10) ^h01
EOF
page domains/port/DOMAIN.md <<'EOF'
# Port card
- Pier lantern and ferry horn sound together. (25-01-10) ^p01
EOF
page domains/porch/DOMAIN.md <<'EOF'
# Porch card
- Quokka mats dry on the porch rail. (26-10-01) ^q01
EOF
page domains/attic/DOMAIN.md <<'EOF'
# Attic card
- Walnut crates rest under the attic beam. (26-10-01) ^a01
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
"$MEM" net build >/dev/null 2>&1

sh12() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_recall; print(memory_recall.session_hash(sys.argv[2]))' "$LIB" "$1"; }
# hint <hh:mm> <session> <cue ids> <ids>: one event row, as `memory recall` writes it
hint() { mkdir -p "$EV"; printf '%sT%s:00+0000\t%s\t%s\t%s\n' "$D" "$1" "$(sh12 "$2")" "$3" "$4" >>"$EV/$D.tsv"; }
# audit <hh:mm> <session> <tool> <summary>: one audit-log row
audit() { python3 -c 'import json,sys; print(json.dumps({"ts": sys.argv[1], "session": sys.argv[2], "tool": sys.argv[3], "summary": sys.argv[4]}))' \
  "${D}T$1:00+0000" "$2" "$3" "$4" >>"$AUD"; }
fold() {
  python3 - "$LIB" "${D}T$1:00+0000" <<'PY'
import datetime, sys
sys.path.insert(0, sys.argv[1])
import memory_fold, memory_net, memory_store
st = memory_store.Store(memory_store.home())
memory_net.build(st)
print(memory_fold.run(st, now=datetime.datetime.strptime(sys.argv[2], memory_fold.FMT)))
PY
}
rank() { ( cd "$HOME/plain" && CHAT_SEAT=boss "$MEM" recall --json "$@" | python3 -c 'import json,sys; print(" ".join(h["id"] for h in json.load(sys.stdin)["hints"]) or "-")' ); }
row() { grep -P "^$1\t$2\t" "$S/net/links.tsv"; }

# --- opens raise the rank ----------------------------------------------------------------------------------------
is "rank: before learning the newer line leads" "$(rank lantern ferry)" "h01 p01"
for i in 1 2 3; do hint "01:0$i" "sessop$i" c:lantern,c:ferry p01; audit "01:0${i}" "sessop$i" Bash "memory show ^p01 | head"; done
out="$(fold 01:30)"
is "fold: summary line" "$out" "net · learned · 3 hints, 3 opened, 2 links grown, 0 faded"
ev "fold: 3 opens grow lantern -> p01 (count 3)" 'row c:lantern m:p01 | grep -qP "\t0\.9173\t$D\t3$"'
is "rank: 3 opens raise p01 above h01" "$(rank lantern ferry)" "p01 h01"

# --- ignores silence --------------------------------------------------------------------------------------------
is "silence: quokka porch fires before" "$(rank quokka porch)" "q01"
for i in 1 2 3 4; do hint "02:0$i" "sessig$i" c:quokka,c:porch q01; done
fold 02:30 >/dev/null
is "silence: 4 ignores in a row still fire" "$(rank quokka porch)" "q01"
hint 03:01 sessig5 c:quokka,c:porch q01
fold 03:30 >/dev/null
is "silence: the 5th ignore in a row silences it" "$(rank quokka porch)" "-"
is "silence: only those cue links: another cue still fires it" "$(rank quokka mats rail)" "q01"

# --- co-opened pair, Read as an open -----------------------------------------------------------------------------
hint 04:01 sesspair c:walnut,c:crates a01
audit 04:02 sesspair Bash "memory show a01"; audit 04:03 sesspair Bash "memory show h01"
audit 04:04 sessread Bash "memory show q01"
fold 04:30 >/dev/null
ev "co-open: a01 <-> h01 linked both ways in links.tsv" 'row m:a01 m:h01 >/dev/null && row m:h01 m:a01 >/dev/null'
ev "co-open: the link is in the built graph" 'python3 -c "import json,sys; sys.exit(\"m:h01\" not in json.load(open(sys.argv[1]))[\"links\"][\"m:a01\"])" "$S/net/graph.json"'
ev "co-open: a session with no hint teaches nothing (q01 show in sessread)" '! grep -qP "^m:q01\tm:" "$S/net/links.tsv"'
hint 05:01 sessrd c:walnut,c:beam a01
audit 05:02 sessrd Read "$S/domains/attic/DOMAIN.md"
fold 05:30 >/dev/null
ev "read: a Read of the hinted page counts as an open" 'row c:beam m:a01 | grep -qP "\t1$"'

# --- PRIVATE links stay in the ignored file ----------------------------------------------------------------------
hint 06:01 sesspriv c:vault x01; audit 06:02 sesspriv Bash "memory show x01"
fold 06:30 >/dev/null
ev "private: the x01 link is in links.private.tsv" 'grep -qP "^c:vault\tm:x01\t" "$S/net/links.private.tsv"'
ev "private: links.tsv and graph.json never name x01" '! grep -q x01 "$S/net/links.tsv" "$S/net/graph.json"'

# --- a protected session leaves no event and teaches nothing ------------------------------------------------------
( cd "$HOME/vault" && printf '%s' '{"prompt":"ledger stamps drawer window","session_id":"sessvaultxyz","cwd":"'"$HOME/vault"'"}' \
  | "$MEM" recall --hook >"$T/vout" )
is "protected: the hook still hints from its experience page" "$(grep -c '\^v01' "$T/vout")" 1
n="$(cat "$EV"/*.tsv | wc -l)"
audit 07:02 sessvaul Bash "memory show v01"
fold 07:30 >/dev/null
is "protected: no event row logged (rows stay $n)" "$(cat "$EV"/*.tsv | wc -l)" "$n"
ev "protected: no link learned for v01" '! grep -q v01 "$S/net/links.tsv" "$S/net/links.private.tsv"'

# --- nightly decay prunes under 0.05 ------------------------------------------------------------------------------
rm -rf "$EV"; : >"$AUD"
printf '# from\tto\tweight\tlast\tcount · folded through 2026-01-08T07:30:00+0000\nc:walnut\tm:a01\t0.051\t2026-01-08\t1\nc:crates\tm:a01\t0.5\t2026-01-08\t1\n' >"$S/net/links.tsv"
: >"$S/net/links.private.tsv"
out="$(fold 08:30)"
ev "decay: 0.051 after 2 nights is dropped" '! row c:walnut m:a01'
ev "decay: 0.5 after 2 nights is 0.4802" 'row c:crates m:a01 | grep -qP "\t0\.4802\t"'
is "decay: summary counts 1 faded" "$out" "net · learned · 0 hints, 0 opened, 0 links grown, 1 faded"

# --- the fold inside `memory apply` -------------------------------------------------------------------------------
rm -rf "$S/net"
git -C "$S" init -q -b main && git -C "$S" add -A && git -C "$S" commit -qm fixture
now() { date -d "$1" +%Y-%m-%dT%H:%M:%S%z; }
mkdir -p "$EV"; printf '%s\t%s\tc:walnut,c:crates\ta01\n' "$(now '-2 min')" "$(sh12 sessapp)" >>"$EV/$(date +%Y-%m-%d).tsv"
python3 -c 'import json,sys; print(json.dumps({"ts": sys.argv[1], "session": "sessapp", "tool": "Bash", "summary": "memory show a01"}))' \
  "$(now '-1 min')" >>"$AUD"
ST="$("$MEM" stage)"
"$MEM" apply "$ST" >"$T/apply.out" 2>&1; rc=$?
is "apply: green, exit 0" "$rc" 0
ev "apply: prints the learned line (1 hint, 1 opened)" 'grep -q "^net · learned · 1 hints, 1 opened, 2 links grown" "$T/apply.out"'
is "apply: git tracks links.tsv, never links.private.tsv" "$(git -C "$S" ls-files net | tr '\n' ' ')" "net/.gitignore net/links.tsv "
is "apply: the store is clean after the commit" "$(git -C "$S" status --porcelain)" ""

[ "$bad" = 0 ] && echo "all memory-learn cases pass"
exit $bad
