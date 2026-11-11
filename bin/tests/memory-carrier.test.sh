#!/usr/bin/env bash
# Fixture test for the Claude memory carrier (T1599-M08): `memory install [--plan]`, the worker seat guard, the adapter's
# memory, `memory check --live`, brief-lint's Memory: warning. Fake HOME and a synthetic store copied from
# fixtures/memory-carrier (every fact invented); never the real store (the selftest proves it first). The model call is
# a stub unless MEMORY_LIVE=1, which asks haiku once through the real adapter with the fixture store.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
BIN="$(dirname "$here")"; ROOT="$(dirname "$BIN")"
REAL_STORE="$HOME/memory"; REAL_HOME="$HOME"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
H="$WORK/home"; S="$H/memory"; CFG="$H/.config/pc-harness/config.env"
mkdir -p "$H/.config/pc-harness" "$WORK/bin"
cp -r "$here/fixtures/memory-carrier/store" "$S"
printf 'PROTECTED_PROJECTS="acme"\nPROTECTED_ACME_REPOS="~/clients/acme"\n' >"$CFG"
fx() { env -i PATH="$WORK/bin:$PATH" HOME="$H" HARNESS_CONFIG="$CFG" MEMORY_HOME="$S" HARNESS_HOME="$H/agents" "$@"; }
home_of() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$ROOT/lib"; }

# Selftest: the store under test is the fixture copy in the fake HOME, never the real store.
got=$(fx bash -c "$(declare -f home_of); ROOT='$ROOT'; home_of")
ok_home=0; [ "$got" = "$S" ] && [ "$(realpath -m "$got")" != "$(realpath -m "$REAL_STORE")" ] && [ "$H" != "$REAL_HOME" ] && ok_home=1
truthy "selftest: MEMORY_HOME and HOME are the fixture, not the real ones" "$ok_home"
[ "$bad" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

# Stub CLI: `claude [-p] -- cmd ...` runs cmd as its child, so the carrier sees a claude ancestor with or without -p.
printf '#!/usr/bin/env bash\nwhile [ "${1:-}" != -- ]; do shift; done; shift; "$@"\n' >"$WORK/bin/claude"
chmod +x "$WORK/bin/claude"; ln -s "$BIN/memory" "$WORK/bin/memory"

# The fake HOME: the fleet include, git projects, a plain folder, two protected ones, rostered agents, an old MEMORY.md.
printf '# home\n<!-- pc-harness: the fleet contract -->\n@~/agents/AGENTS.md\n\n## more\n' >"$H/CLAUDE.md"
mkdir -p "$H/proj/zebra/sub" "$H/proj/plain" "$H/proj/locked" "$H/clients/acme" "$H/agents"/{herd-po,drover,idle,preset}
for g in proj/zebra proj/locked clients/acme; do git -C "$H/$g" init -q; done
printf 'SCHEDULE="*-*-* 03:00"\nMODEL=haiku\n' >"$H/agents/herd-po/agent.env"
printf 'SCHEDULE=hourly\n' >"$H/agents/drover/agent.env"
printf 'MODEL=haiku\n' >"$H/agents/idle/agent.env"
printf 'SCHEDULE=daily\nMEMORY_DOMAINS=plain\n' >"$H/agents/preset/agent.env"
MEMDIR="$H/.claude/projects/$(printf '%s' "$H" | sed 's/[^A-Za-z0-9]/-/g')/memory"
mkdir -p "$MEMDIR"; printf 'old hand notes\n' >"$MEMDIR/MEMORY.md"
printf '{"projects": {"%s": {"hasClaudeMdExternalIncludesApproved": true}}}\n' "$H/proj/zebra" >"$H/.claude.json"
snap() { (cd "$WORK" && find home -type f ! -path '*/.git/objects/*' ! -path '*/.git/logs/*' -exec sha256sum {} + | sort); }

# 1. --plan writes nothing and says what it would write.
before=$(snap); out=$(fx "$BIN/memory" install --plan); rc=$?
is "install --plan: rc 0" "$rc" 0
is "install --plan: 0 files changed" "$(diff <(echo "$before") <(snap) | grep -c '^[<>]')" 0
ev "install --plan: prints would: lines" '[ "$(grep -c "^would: " <<<"$out")" -ge 8 ]'

# 2. install writes the carriers, skips protected and missing folders, lists what it skipped.
touch "$WORK/stamp"; sleep 1
out=$(fx "$BIN/memory" install); rc=$?
is "install: rc 0" "$rc" 0
is "core line sits right after the @AGENTS.md line" "$(grep -A1 '^@~/agents/AGENTS.md$' "$H/CLAUDE.md" | tail -1)" "@~/memory/core/CORE.md"
is "zebra stub imports its card" "$(cat "$H/proj/zebra/CLAUDE.local.md")" "@~/memory/domains/zebra/DOMAIN.md"
is "nested sub stub imports its own card" "$(cat "$H/proj/zebra/sub/CLAUDE.local.md")" "@~/memory/domains/quokka/DOMAIN.md"
is "plain (no git) stub written" "$(cat "$H/proj/plain/CLAUDE.local.md")" "@~/memory/domains/plain/DOMAIN.md"
is "stubs hidden from git: exclude line once, git status clean" \
  "$(grep -cx 'CLAUDE.local.md' "$H/proj/zebra/.git/info/exclude") $(git -C "$H/proj/zebra" status --porcelain | wc -l)" "1 0"
is "protected folders (map flag, matcher) get 0 files" "$(find "$H/proj/locked" "$H/clients/acme" -newer "$WORK/stamp" -type f | wc -l)" 0
ev "protected and missing folders are listed" 'grep -qx "skipped (protected): ~/proj/locked" <<<"$out" && grep -qx "skipped (protected): ~/clients/acme" <<<"$out" && grep -qx "skipped (missing): ~/proj/gone" <<<"$out"'
mem=$(cat "$MEMDIR/MEMORY.md")
ev "MEMORY.md: owner card + index, PRIVATE card left out, within 200 lines" \
  'grep -q "06:40" <<<"$mem" && grep -q "stripes, fence" <<<"$mem" && ! grep -q marmalade <<<"$mem" && ! grep -q "\^b01" <<<"$mem" && [ "$(wc -l <<<"$mem")" -le 200 ]'
ev "the old MEMORY.md is archived word for word first" 'grep -rqx "old hand notes" "$S/archive/2026-11-auto-memory/"'
is "rostered agent.env get their routed domains" \
  "$(tail -1 "$H/agents/herd-po/agent.env") | $(tail -1 "$H/agents/drover/agent.env")" "export MEMORY_DOMAINS=zebra | export MEMORY_DOMAINS=herd"
is "unrostered and preset agent.env untouched" "$(cat "$H/agents/idle/agent.env" "$H/agents/preset/agent.env" | md5sum)" \
  "$(printf 'MODEL=haiku\nSCHEDULE=daily\nMEMORY_DOMAINS=plain\n' | md5sum)"
ev "every write is printed" '[ "$(grep -c "^wrote " <<<"$out")" = 11 ]'
todo=$(fx "$BIN/owner-todo" list)
ev "one owner-todo names the unapproved folders, not the approved one" \
  '[ "$(grep -c "memory imports" <<<"$todo")" = 1 ] && grep -q "~/proj/plain" <<<"$todo" && ! grep -q "~/proj/zebra," <<<"$todo"'

# 3. Idempotent: a second install changes no file and files no second todo.
after=$(snap); out=$(fx "$BIN/memory" install); rc=$?
is "install twice = the same files" "$rc $(diff <(echo "$after") <(snap) | grep -c '^[<>]')" "0 0"
ev "second install says no changes" 'grep -qx "memory install: no changes" <<<"$out" && ! grep -q "^wrote" <<<"$out"'
is "still one owner-todo" "$(fx "$BIN/owner-todo" list | grep -c 'memory imports')" 1

# 4. Worker seat guard: an inherited owner seat counts only outside a worker (no `claude -p` ancestor, no marker).
ld() { fx CHAT_SEAT=boss "$@" 2>/dev/null; }
ev "owner session (interactive claude) loads its PRIVATE card" 'ld claude -- memory load vault | grep -q marmalade'
ev "headless claude -p child: PRIVATE card not loaded" '! ld claude -p -- memory load vault | grep -q marmalade'
ev "MEMORY_WORKER marker: PRIVATE card not loaded" '! ld MEMORY_WORKER=1 claude -- memory load vault | grep -q marmalade'
n1=$(ld claude -- memory note "synthetic owner note" --quote "boss said so"); n2=$(ld claude -p -- memory note "synthetic worker note" --quote "boss said so")
is "notes: owner session stamped owner, worker stamped untrusted" \
  "$(grep '^source:' "$S/$n1") | $(grep '^source:' "$S/$n2")" "source: owner | source: untrusted"
rm -f "$S/$n1" "$S/$n2"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >"$HOME/args.log"; env >"$HOME/env.log"\n' >"$WORK/bin/stubclaude"
mkdir -p "$WORK/abin"; cp "$WORK/bin/stubclaude" "$WORK/abin/claude"; chmod +x "$WORK/abin/claude"; ln -s "$BIN/memory" "$WORK/abin/memory"
printf 'go\n' >"$WORK/p.md"
(cd "$H/proj/zebra" && env -i PATH="$WORK/abin:/usr/bin:/bin" HOME="$H" HARNESS_CONFIG="$CFG" MEMORY_HOME="$S" CHAT_SEAT=boss \
  MEMORY_DOMAINS=vault PROMPT_FILE="$WORK/p.md" MODEL=m RAW_OUT="$WORK/raw" META_OUT="$WORK/meta" bash "$ROOT/adapters/claude/run" >/dev/null 2>&1)
ev "adapter run: marked worker, gets core + its folder's card, never the owner's PRIVATE card" \
  'grep -qx MEMORY_WORKER=1 "$H/env.log" && grep -q Pemberton "$H/args.log" && grep -q "teal" "$H/args.log" && ! grep -q marmalade "$H/args.log"'

# 5. memory check --live: the seam gets 5 questions; the stub answers each with what the carrier loads (memory load).
# A core question only a topic page answers (not in `memory load`) is never drawn.
printf -- '- The mascot snacks on figs at dusk. ^c04\n' >"$S/core/garden.md"
printf 'c04\tWhat does the mascot snack on?\tfigs\n' >>"$S/checks/questions.d/core.tsv"
cat >"$WORK/bin/quiz-stub" <<'EOS'
#!/usr/bin/env bash
cat >"$HOME/quiz-prompt.txt"; m=$(memory load | tr '\n' ' ')
for i in 1 2 3 4 5; do echo "$i: $m"; done
EOS
chmod +x "$WORK/bin/quiz-stub"
out=$(fx MEMORY_QUIZ_CMD=quiz-stub "$BIN/memory" check --live --domains zebra); rc=$?
ev "--live (stub): prints 5/5, rc 0" '[ "$rc" = 0 ] && grep -qx "live · 5/5" <<<"$out"'
ev "--live: the seam got 5 numbered questions, none private" \
  '[ "$(grep -cE "^[1-5]: .+\?$" "$H/quiz-prompt.txt")" = 5 ] && ! grep -q vault "$H/quiz-prompt.txt"'
ev "--live: approval reported per project" 'grep -qx "approval · ~/proj/zebra · yes" <<<"$out" && grep -qx "approval · ~/proj/plain · no" <<<"$out"'
out=$(fx MEMORY_QUIZ_CMD='cat >/dev/null; echo "1: no idea"' "$BIN/memory" check --live --domains zebra); rc=$?
ev "--live: wrong answers give 0/5, rc 1, each miss named" '[ "$rc" = 1 ] && grep -qx "live · 0/5" <<<"$out" && [ "$(grep -c "missing:" <<<"$out")" = 5 ]'
out=$(fx MEMORY_QUIZ_CMD=quiz-stub "$BIN/memory" check --live); rc=$?
ev "--live: core only has 3 questions: rc 1, said so" '[ "$rc" = 1 ] && grep -q "only 3 questions" <<<"$out"'
ev "--live: the topic-page question is not drawn" '! grep -q snack "$H/quiz-prompt.txt"'
cat >"$WORK/bin/quiz-noload" <<'EOS'
#!/usr/bin/env bash
cat >/dev/null; m=$(MEMORY_HOME="$HOME/nowhere" memory load 2>/dev/null | tr '\n' ' ')
for i in 1 2 3 4 5; do echo "$i: $m"; done
EOS
chmod +x "$WORK/bin/quiz-noload"
out=$(fx MEMORY_QUIZ_CMD=quiz-noload "$BIN/memory" check --live --domains zebra 2>/dev/null); rc=$?
ev "--live: the carrier's load fails -> red (rc 1, 0/5)" '[ "$rc" = 1 ] && grep -qx "live · 0/5" <<<"$out"'
cat >"$WORK/bin/quiz-flaky" <<'EOS'
#!/usr/bin/env bash
cat >/dev/null; n=$(cat "$HOME/flaky.n" 2>/dev/null || echo 0); echo $((n + 1)) >"$HOME/flaky.n"
m=$(memory load | tr '\n' ' '); [[ " $FLAKY_WRONG " == *" $n "* ]] && m=""
for i in 1 2 3 4 5; do echo "$i: $m"; done
EOS
chmod +x "$WORK/bin/quiz-flaky"
out=$(fx MEMORY_QUIZ_CMD=quiz-flaky FLAKY_WRONG=0 "$BIN/memory" check --live --domains zebra 2>/dev/null); rc=$?
is "--live: majority of 3 (wrong, right, right) -> green" "$rc $(grep -x 'live · 5/5' <<<"$out") $(cat "$H/flaky.n")" "0 live · 5/5 3"
rm -f "$H/flaky.n"; out=$(fx MEMORY_QUIZ_CMD=quiz-flaky FLAKY_WRONG="0 1" "$BIN/memory" check --live --domains zebra 2>/dev/null); rc=$?
is "--live: majority of 3 (wrong, wrong, right) -> red" "$rc $(grep -x 'live · 0/5' <<<"$out") $(cat "$H/flaky.n")" "1 live · 0/5 3"
if [ "${MEMORY_LIVE:-}" = 1 ]; then
  out=$(cd "$WORK" && MEMORY_HOME="$S" "$BIN/memory" check --live --domains zebra); rc=$?
  ev "MEMORY_LIVE=1: one real haiku run through the adapter prints 5/5" '[ "$rc" = 0 ] && grep -qx "live · 5/5" <<<"$out"' || echo "$out"
fi

# 6. brief-lint: a brief naming a domains.map project folder and no Memory: line warns; rc unchanged.
bl() { printf '# %s\nClaims on FILE-CLAIMS, test changes none. Report: max 5 lines.\n%s\nCHECK: true\n' "$1" "$2" >"$WORK/$1.md"
       fx "$BIN/brief-lint" "$WORK/$1.md"; }
out=$(bl B1 'Edit ~/proj/zebra/src/a.py.'); rc=$?
ev "brief-lint: project named, no Memory: line -> WARN, rc 0" \
  '[ "$rc" = 0 ] && grep -q "^WARN .*B1.md: names the zebra project but has no \`Memory:\` line; add \`Memory: memory load zebra\`" <<<"$out"'
out=$(bl B2 $'Edit ~/proj/zebra/src/a.py.\nMemory: memory load zebra'); ev "brief-lint: Memory: line present -> quiet" '! grep -q WARN <<<"$out"'
out=$(bl B3 'See ~/agents/FILE-CLAIMS.md and ~/proj/zebra-two/x.'); ev "brief-lint: harness folder and look-alike paths -> quiet" '! grep -q WARN <<<"$out"'

# 7. A served build (a folder holding the `sites publish` stamp build.json) gets no stub and asks no approval.
mkdir -p "$H/sites/blog"; printf '{"commit":"abc"}\n' >"$H/sites/blog/build.json"; printf '~/sites/blog  zebra\n' >>"$S/domains.map"
out=$(fx "$BIN/memory" install); rc=$?
ev "install: served build skipped, no stub, rc 0" \
  '[ "$rc" = 0 ] && grep -qx "skipped (served build): ~/sites/blog" <<<"$out" && [ ! -e "$H/sites/blog/CLAUDE.local.md" ]'
out=$(fx MEMORY_QUIZ_CMD=quiz-stub "$BIN/memory" check --live --domains zebra 2>/dev/null)
ev "--live: no approval line for the served build" '! grep -q "sites/blog" <<<"$out"'

[ "$bad" = 0 ] && echo "memory-carrier.test.sh: all green" || echo "memory-carrier.test.sh: FAILURES"
exit "$bad"
