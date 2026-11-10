#!/usr/bin/env bash
# T1599-M09: the keeper's verbs (memory sources, stage, apply), the 6 planted notes, a protected project read only,
# the push guard and the PRECHECK skip. Sandbox only (AGENTS.md §5.6): HOME, AGENT_WORK and MEMORY_HOME are temp dirs
# over the synthetic fixture (fixtures/memory-keeper), `gh` is a stub and origin a local bare repo. Default: the keeper's
# judgement is replayed from fixtures/memory-keeper/recorded; MEMORY_LIVE=1: one real keeper run (opus) instead.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$BIN/.." && pwd)"
FX="$BIN/tests/fixtures/memory-keeper"
REAL_HOME="$HOME"
REAL_STORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$ROOT/lib")"
CLAUDE_BIN="$(command -v claude || true)"
fail=0
t() { printf '%-74s' "memory-keeper: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }
real_state() { git -C "$REAL_STORE" status --porcelain 2>/dev/null; git -C "$REAL_STORE" rev-parse HEAD 2>/dev/null; }
real_before="$(real_state)"
tools_sum() { sha256sum "$BIN/memory" "$ROOT/lib/memory_txn.py" "$ROOT/lib/memory_sources.py" "$ROOT/memory-keeper/BRIEF.md"; }
tools_before="$(tools_sum)"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" AGENT_WORK="$T/aw" MEMORY_HOME="$T/store" HARNESS_CONFIG=/nonexistent
unset CLAUDE_CONFIG_DIR CHAT_SEAT MEMORY_DOMAINS
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
       GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
mkdir -p "$T/stub"
printf '#!/usr/bin/env bash\necho "$*" >>"%s/gh.log"\necho "${GH_VISIBILITY:-PUBLIC}"\n' "$T" >"$T/stub/gh"
chmod +x "$T/stub/gh"
export PATH="$T/stub:$PATH"
P="$HOME/.claude/projects"
TOK="gh""p_$(printf 'Q%.0s' $(seq 24))"
MARK="$(sed -n 's/^MARK = "\(.*\)"$/\1/p' "$ROOT/adapters/claude/memory-carrier")"
mem() { "$BIN/memory" "$@"; }
enc() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
writes_under() {  # writes_under <strace log> <dir>: write-opens, unlinks, renames, mkdirs that name a path under dir
  grep -F "\"$2/" "$1" | grep -cE 'O_WRONLY|O_RDWR|O_CREAT|O_TRUNC|^[0-9]+ +(unlink|unlinkat|rename|renameat|renameat2|mkdir|mkdirat)\('
}
traced() { strace -f -qq -e trace=openat,open,creat,unlink,unlinkat,rename,renameat,renameat2,mkdir,mkdirat -o "$1" "${@:2}"; }

setup() {  # a fresh fixture world: store (git), projects, the 6 notes, the owner's transcript, harbor's session notes
  rm -rf "$T/store" "$T/proj" "$HOME" "$AGENT_WORK" "$T/origin.git"
  mkdir -p "$HOME" "$AGENT_WORK/decisions"
  cp -r "$FX/store" "$T/store"
  cp -r "$FX/projects" "$T/proj"
  sed "s#@P@#$T/proj#" "$T/store/domains.map.in" >"$T/store/domains.map"
  rm "$T/store/domains.map.in"
  git -C "$T/store" init -q -b main && git -C "$T/store" add -A && git -C "$T/store" commit -q -m seed
  cp "$FX"/notes/*.md "$T/store/inbox/"
  printf 'source: agent\nseat: -\ndomain: garden\ndate: 2026-11-09T21:25:00+0100\nsession: -\ntext: The seed API key is %s\n' \
    "$TOK" >"$T/store/inbox/n6-token.md"
  mkdir -p "$P/-fixture" "$P/$(enc "$T/proj/harbor")/memory" "$P/$(enc "$HOME")/memory"
  cp "$FX/claude/transcript.jsonl" "$P/-fixture/keeper-fixture-session-1.jsonl"
  cp "$FX/claude/harbor-session-note.md" "$P/$(enc "$T/proj/harbor")/memory/notes.md"
  printf '%s\n# memory: orchestrator\nold\n' "$MARK" >"$P/$(enc "$HOME")/memory/MEMORY.md"
  git init -q --bare "$T/origin.git" && git -C "$T/store" remote add origin "$T/origin.git"
}
store_is_fixture() {  # the store `memory` resolves for MEMORY_HOME=$1 is the fixture, never the real one
  local h; h="$(MEMORY_HOME="$1" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$ROOT/lib")"
  [ "$h" = "$T/store" ] && [ "$(realpath -m "$h")" != "$(realpath -m "$REAL_STORE")" ]
}

t "selftest: the guard fails on the real store, passes on the fixture"
setup
{ ! store_is_fixture "$REAL_STORE" && store_is_fixture "$T/store" && [ "$(git -C "$T/store" log --format=%s)" = seed ]; } \
  && ok || { no "the store is not the sandbox fixture"; exit 1; }

# --- memory sources -------------------------------------------------------------------------------------------
mkdir -p "$P/$(enc "$T/proj/garden")-src/memory" "$T/store/archive/2026-11-auto-memory"
printf '# garden session\n- Node 22 builds the catalogue.\n' >"$P/$(enc "$T/proj/garden")-src/memory/build.md"
cp "$FX/claude/orchestrator-old.md" "$FX/claude/orchestrator-new.md" "$P/$(enc "$HOME")/memory/"
(cd "$P/$(enc "$HOME")/memory" && sha256sum orchestrator-old.md | sed 's#  #  archive/2026-11-auto-memory/#') \
  >"$T/store/archive/2026-11-auto-memory/SHA256SUMS"
printf '# garden ledger\n' >"$AGENT_WORK/decisions/garden.md"
printf 'not a domain\n' >"$AGENT_WORK/decisions/other.md"
ln -s "$T/store/domains/kiln/DOMAIN.md" "$AGENT_WORK/decisions/kiln.md"
traced "$T/st-sources" "$BIN/memory" sources >"$T/src.out" 2>"$T/src.err"
src_rc=$?

t "sources: 8 files (folder files, rules, 2 session notes, new orchestrator file, ledger)"
want="$(printf '%s\n' "garden	$T/proj/garden/CLAUDE.md	-" "garden	$T/proj/garden/CLAUDE.local.md	-" \
  "garden	$T/proj/garden/.claude/rules/images.md	-" "harbor	$T/proj/harbor/CLAUDE.md	protected" \
  "garden	~/.claude/projects/$(enc "$T/proj/garden")-src/memory/build.md	-" \
  "harbor	~/.claude/projects/$(enc "$T/proj/harbor")/memory/notes.md	protected" \
  "orchestrator	~/.claude/projects/$(enc "$HOME")/memory/orchestrator-new.md	-" "garden	$T/aw/decisions/garden.md	-" | sort)"
{ [ "$src_rc" = 0 ] && [ "$(sort "$T/src.out")" = "$want" ]; } && ok || no "rc $src_rc; $(diff <(sort "$T/src.out") <(echo "$want"))"

t "sources: no code file, migrated or generated file, link, or other ledger"
! grep -qE 'app\.py|README|orchestrator-old|MEMORY\.md|other\.md|kiln\.md' "$T/src.out" && ok || no "$(cat "$T/src.out")"

t "sources: --changed lists 8, after --mark 0, one edited file 1"
c1="$(mem sources --changed | wc -l)"; mem sources --mark >/dev/null; c2="$(mem sources --changed | wc -l)"
printf 'Images are AVIF.\n' >>"$T/proj/garden/.claude/rules/images.md"; c3="$(mem sources --changed)"
{ [ "$c1" = 8 ] && [ "$c2" = 0 ] && [ "$(wc -l <<<"$c3")" = 1 ] && grep -q images.md <<<"$c3"; } && ok || no "$c1 $c2 [$c3]"

t "sources: sha list in AGENT_WORK, not in the store; nothing created beside the files"
{ [ -s "$AGENT_WORK/memory-keeper/sources.tsv" ] && [ -z "$(git -C "$T/store" status --porcelain | grep -v '^?? inbox/')" ] \
  && [ "$(find "$T/proj" -newer "$T/store/domains.map" ! -path '*/rules/images.md' ! -path '*/rules' | wc -l)" = 0 ]; } \
  && ok || no "$(git -C "$T/store" status --porcelain)"

t "sources: strace shows reads under the protected project, 0 writes"
r="$(grep -F "\"$T/proj/harbor/" "$T/st-sources" | grep -c O_RDONLY)"; w="$(writes_under "$T/st-sources" "$T/proj")"
{ [ "$r" -ge 1 ] && [ "$w" = 0 ]; } && ok || no "reads $r writes $w"

# --- the keeper's run: stage, judgement (replayed or live), apply ---------------------------------------------
setup
owner_edit() {  # his own edit to a page the keeper does not touch: committed first as owner:, with a ledger line
  printf -- '- Briefs name the ticket in the title. (26-11-10) ^or02\n' >>"$T/store/domains/orchestrator/DOMAIN.md"
  printf 'or02\tdomains/orchestrator/DOMAIN.md\tlive\towner edit\n' >>"$T/store/checks/ids.d/orchestrator.tsv"
}
cp "$T/store/domains/harbor/DOMAIN.md" "$T/harbor.before"
if [ "${MEMORY_LIVE:-}" = 1 ]; then
  t "live: plan-usage --check 80 before the one live run"
  HOME="$REAL_HOME" plan-usage --check 80 >/dev/null 2>&1 && ok || { no "plan over 80 % or unreadable"; exit 1; }
  owner_edit
  mkdir -p "$T/keeper" "$HOME/.claude" "$T/bin"
  cp "$ROOT/memory-keeper/BRIEF.md" "$T/keeper/"
  ln -s "$REAL_HOME/.claude/.credentials.json" "$HOME/.claude/.credentials.json"
  printf '#!/usr/bin/env bash\nexec strace -f -qq -e trace=openat,open,creat,unlink,unlinkat,rename,renameat,renameat2,mkdir,mkdirat -o "%s/st-apply.$$" "%s" "$@"\n' \
    "$T" "$BIN/memory" >"$T/bin/memory"; chmod +x "$T/bin/memory"
  (cd "$T/keeper" && PATH="$T/bin:$PATH" CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 MEMORY_WORKER=1 timeout 1500 "$CLAUDE_BIN" -p "$(cat BRIEF.md)" \
     --model opus --permission-mode bypassPermissions --strict-mcp-config --tools Bash,Read,Edit,Write \
     --output-format json >"$T/live.json" 2>"$T/live.err")
  cat "$T"/st-apply.* >"$T/st-apply" 2>/dev/null
  jq -r '.result // empty' "$T/live.json" >"$T/apply.out"; cp "$T/keeper/REPORT.md" "$T/apply.report" 2>/dev/null
  echo "memory-keeper: live run: $(jq -r '"\(.num_turns) turns, \(.usage.input_tokens + .usage.cache_read_input_tokens + .usage.cache_creation_input_tokens) in, \(.usage.output_tokens) out, $\(.total_cost_usd)"' "$T/live.json")"
  [ -n "${MEMORY_RECORD:-}" ] && cp -r "$T/live.json" "$T/keeper" "$MEMORY_RECORD"/ 2>/dev/null
else
  S="$(mem stage)"
  t "stage: a staging copy outside the store; the store is not modified"
  { [ -d "$S" ] && [ "${S#"$AGENT_WORK"/}" != "$S" ] && cmp -s "$S/core/CORE.md" "$T/store/core/CORE.md" \
    && [ ! -e "$S/.git" ] && [ "$(git -C "$T/store" status --porcelain | grep -vc '^?? inbox/')" = 0 ]; } && ok || no "$S"
  owner_edit
  cp -r "$FX/recorded/." "$S/"
  traced "$T/st-apply" "$BIN/memory" apply "$S" >"$T/apply.out" 2>&1
  apply_rc=$?
  t "apply: green, exit 0"
  { [ "$apply_rc" = 0 ] && grep -q '^apply · green' "$T/apply.out" && [ ! -e "$S" ]; } && ok || no "rc $apply_rc: $(cat "$T/apply.out")"
fi
St="$T/store"

t "note 1 (a repeat): nothing, the card keeps one 800 px line"
[ "$(grep -c '800' "$St/domains/garden/DOMAIN.md")" = 1 ] && ok || no "$(cat "$St/domains/garden/DOMAIN.md")"

t "note 2 (his contradiction): replace, ^k02 retired, ledger superseded line"
{ ! grep -q '\^k02' "$St/core/CORE.md" && grep -qi amber "$St/core/CORE.md" \
  && grep -qi superseded "$St/core/ledger.md" && grep -qP '^k02\t[^\t]*\t(retired:|merged:)' "$St/checks/ids.tsv"; } \
  && ok || no "$(cat "$St/core/CORE.md"; tail -2 "$St/core/ledger.md"; grep k02 "$St/checks/ids.tsv")"

t "note 3 (untrusted 'always push'): held in REVIEW.md, no page says it"
{ grep -q 'n3-untrusted' "$St/REVIEW.md" && [ "$(wc -l <"$St/REVIEW.md")" -le 10 ] \
  && ! grep -rqiE 'push|without review' "$St/core" "$St/domains" --include=DOMAIN.md --include=CORE.md; } \
  && ok || no "$(cat "$St/REVIEW.md" 2>&1)"

t "note 4 (a new lesson): added to the garden card with an id"
grep -iE 'lazi|lazy' "$St/domains/garden/DOMAIN.md" | grep -q ' \^[a-z]' && ok || no "$(cat "$St/domains/garden/DOMAIN.md")"

t "note 5 (manager domain): passed to domains/kiln/inbox, card untouched"
{ grep -rqi 'whole minutes' "$St/domains/kiln/inbox/" && cmp -s "$St/domains/kiln/DOMAIN.md" "$FX/store/domains/kiln/DOMAIN.md"; } \
  && ok || no "$(ls "$St/domains/kiln/inbox/")"

t "note 6 (a token): rejected by lint, kept outside the store and its history"
{ ! grep -rqF "$TOK" "$St" --exclude-dir=.git && ! git -C "$St" log -p --all | grep -qF "$TOK" \
  && [ -f "$AGENT_WORK/memory-keeper/rejected/n6-token.md" ]; } && ok || no "$(ls "$AGENT_WORK/memory-keeper/rejected/" 2>&1)"

t "notes: 5 filed in archive/notes, the inbox is empty"
{ [ "$(ls "$St/archive/notes" | wc -l)" = 5 ] && [ -z "$(ls "$St/inbox")" ]; } && ok || no "$(ls "$St/archive/notes" "$St/inbox")"

t "protected: the harbor card gains the one way-of-working line, no client data"
added="$(diff "$T/harbor.before" "$St/domains/harbor/DOMAIN.md" | grep -c '^> - ')"
{ [ "$added" = 1 ] && grep -qiE 'test|suite' "$St/domains/harbor/DOMAIN.md" \
  && ! grep -rqiE 'harbor-example|set_field|harbor_ticket|jane|roe|HRB-1042' "$St" --exclude-dir=.git; } \
  && ok || no "added $added: $(cat "$St/domains/harbor/DOMAIN.md")"

t "protected: strace over sources and apply, 0 write-opens under the project"
w="$(writes_under "$T/st-apply" "$T/proj")"; [ -s "$T/st-apply" ] && [ "$w" = 0 ] && ok || no "writes $w"

t "memory check on the store after the run: exit 0"
mem check >"$T/check.out" 2>&1 && ok || no "$(cat "$T/check.out")"

t "his edit committed first as owner: with a ledger line; then keeper:"
{ [ "$(git -C "$St" log --format=%s | grep -c '^owner: ')" -ge 1 ] && git -C "$St" log -1 --format=%s | grep -q '^keeper: ' \
  && grep -q 'owner edit' "$St/core/ledger.md" && grep -q '\^or02' "$St/domains/orchestrator/DOMAIN.md" \
  && [ -z "$(git -C "$St" status --porcelain)" ]; } && ok || no "$(git -C "$St" log --format=%s; git -C "$St" status --porcelain)"

t "views: INDEX.md within 3,072 B, ids.tsv rebuilt, MEMORY.md regenerated"
{ [ -s "$St/INDEX.md" ] && [ "$(wc -c <"$St/INDEX.md")" -le 3072 ] && grep -qP '^k0[3-9]\tcore/CORE.md\tlive' "$St/checks/ids.tsv" \
  && grep -q 'Briefs name the ticket' "$P/$(enc "$HOME")/memory/MEMORY.md" && grep -q 'memory: index' "$P/$(enc "$HOME")/memory/MEMORY.md"; } && ok || no "$(wc -c <"$St/INDEX.md")"

t "push guard: gh reads PUBLIC, no push"
{ ! git -C "$T/origin.git" rev-parse -q --verify main >/dev/null && grep -q 'visibility' "$T/gh.log"; } \
  && ok || no "$(git -C "$T/origin.git" log --oneline 2>&1 | head -2)"

# --- deterministic apply cases (no judgement needed) -------------------------------------------------------------
t "push guard: gh reads PRIVATE, the commit reaches origin"
printf 'source: agent\nseat: -\ndomain: garden\ndate: 2026-11-10T01:00:00+0100\nsession: -\ntext: Seed names are lowercase.\n' >"$St/inbox/n7.md"
S="$(mem stage)"; GH_VISIBILITY=PRIVATE mem apply "$S" >"$T/p.out" 2>&1
{ grep -q '^push · ok' "$T/p.out" && [ "$(git -C "$T/origin.git" rev-parse main)" = "$(git -C "$St" rev-parse HEAD)" ]; } \
  && ok || no "$(cat "$T/p.out")"

t "red gate: a URL in the protected card, exit 1, nothing moves, notes stay"
printf 'source: agent\nseat: -\ndomain: garden\ndate: 2026-11-10T01:05:00+0100\nsession: -\ntext: Seeds ship in May.\n' >"$St/inbox/n8.md"
S="$(mem stage)"; head0="$(git -C "$St" rev-parse HEAD)"
printf -- '- See https://portal.harbor-example.test for the rules. (26-11-10) ^hb09\n' >>"$S/domains/harbor/DOMAIN.md"
mem apply "$S" >"$T/r.out" 2>&1; rc=$?
{ [ "$rc" = 1 ] && grep -q 'experience-only' "$T/r.out" && [ -f "$St/inbox/n8.md" ] && [ "$(git -C "$St" rev-parse HEAD)" = "$head0" ] \
  && ! grep -q hb09 "$St/domains/harbor/DOMAIN.md"; } && ok || no "rc $rc: $(cat "$T/r.out")"
rm -rf "$S" "$S.base.tsv"

t "conflict: his edit and the staging copy change one page, exit 1, his text stays"
S="$(mem stage)"
printf -- '- Seeds are sorted by colour. (26-11-10) ^gd08\n' >>"$S/domains/garden/DOMAIN.md"
printf -- '- Seeds are sorted by name. (26-11-10) ^gd09\n' >>"$St/domains/garden/DOMAIN.md"
mem apply "$S" >"$T/c.out" 2>&1; rc=$?
{ [ "$rc" = 1 ] && grep -q 'changed in the store and in the staging copy' "$T/c.out" && grep -q gd09 "$St/domains/garden/DOMAIN.md" \
  && ! grep -q gd08 "$St/domains/garden/DOMAIN.md"; } && ok || no "rc $rc: $(cat "$T/c.out")"
rm -rf "$S" "$S.base.tsv"

# --- PRECHECK: the keeper's agent.env through the real agent-run, model stubbed --------------------------------
t "PRECHECK: nothing to do, agent-run skips in under 1 s, 0 model calls"
setup
mkdir -p "$HOME/agents/bin" "$HOME/agents/memory-keeper"
cp "$BIN/agent-run" "$BIN/fleetlib.sh" "$BIN/env.sh" "$HOME/agents/bin/"
cp -r "$BIN/guards" "$HOME/agents/bin/guards"
cp "$ROOT/memory-keeper/BRIEF.md" "$ROOT/memory-keeper/agent.env" "$HOME/agents/memory-keeper/"
ln -s "$BIN/memory" "$HOME/agents/bin/memory"
for s in claude notify-owner pc sudo; do printf '#!/usr/bin/env bash\necho "%s $*" >>"$HOME/called.log"\necho "{}"\n' "$s" >"$HOME/agents/bin/$s"; done
printf '#!/usr/bin/env bash\n[ "$1" = +%%u ] && { cat "$HOME/weekday"; exit; }\nexec /usr/bin/date "$@"\n' >"$HOME/agents/bin/date"
chmod +x "$HOME/agents/bin/"*
echo 2 >"$HOME/weekday"
krun() { env -i HOME="$HOME" PATH=/usr/bin:/bin TERM=dumb HARNESS_CONFIG=/nonexistent HARNESS_HOME="$HOME/agents" \
           MEMORY_HOME="$T/store" AGENT_WORK="$AGENT_WORK" bash "$HOME/agents/bin/agent-run" memory-keeper 2>&1; }
mkdir -p "$T/inbox.off"; mv "$T/store/inbox/"*.md "$T/inbox.off/"
env HOME="$HOME" "$BIN/memory" sources --mark >/dev/null
s0=$(date +%s%N); out="$(krun)"; ms=$(( ($(date +%s%N) - s0) / 1000000 ))
{ grep -q 'skipped (PRECHECK' <<<"$out" && [ "$ms" -lt 1000 ] && [ ! -e "$HOME/called.log" ] && [ ! -e "$HOME/agents/memory-keeper/logs" ]; } \
  && { ok; echo "memory-keeper: skip took $ms ms"; } || no "$ms ms: $out"

t "PRECHECK: a note in the inbox, a changed source or Sunday each start the run"
runs=0
mv "$T/inbox.off/n4-lesson.md" "$T/store/inbox/"; krun >/dev/null; [ -e "$HOME/called.log" ] && runs=$((runs+1)); rm -f "$HOME/called.log"
mv "$T/store/inbox/n4-lesson.md" "$T/inbox.off/"
printf 'More.\n' >>"$T/proj/harbor/CLAUDE.md"; krun >/dev/null; [ -e "$HOME/called.log" ] && runs=$((runs+1)); rm -f "$HOME/called.log"
env HOME="$HOME" "$BIN/memory" sources --mark >/dev/null
echo 7 >"$HOME/weekday"; krun >/dev/null; [ -e "$HOME/called.log" ] && runs=$((runs+1))
[ "$runs" = 3 ] && ok || no "$runs of 3 started"

t "the real store and the tool files are untouched"
{ [ "$(HOME="$REAL_HOME" real_state)" = "$real_before" ] && [ "$(tools_sum)" = "$tools_before" ]; } && ok || no "real store or a tool file changed"

[ $fail = 0 ] && echo "memory-keeper.test.sh: all green" || echo "memory-keeper.test.sh: FAILURES"
exit $fail
