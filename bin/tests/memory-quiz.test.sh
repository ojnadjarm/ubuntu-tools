#!/usr/bin/env bash
# Fixture test for the memory quiz (T1599-M07): `memory check --quiz [--changed]`, the merged views, the baseline gate.
# Fake HOME and a synthetic store copied from fixtures/memory-quiz (every fact invented); never the real store (the
# selftest proves it first). The model is a stub (MEMORY_QUIZ_CMD) that answers from the page text, never a real model.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
BIN="$(dirname "$here")"; ROOT="$(dirname "$BIN")"; FX="$here/fixtures/memory-quiz"
REAL_STORE="$HOME/memory"; REAL_HOME="$HOME"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
H="$WORK/home"; S="$H/memory"; LOG="$WORK/asked.log"
mkdir -p "$H"; cp -r "$FX/store" "$S"; : >"$LOG"
fx() { env -i PATH="$PATH" HOME="$H" MEMORY_HOME="$S" MEMORY_QUIZ_CMD="$FX/stub-model" QUIZ_LOG="$LOG" "$@"; }
home_of() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$ROOT/lib"; }

# Selftest: the store under test is the fixture copy in the fake HOME, never the real store.
got=$(fx bash -c "$(declare -f home_of); ROOT='$ROOT'; home_of")
ok_home=0; [ "$got" = "$S" ] && [ "$(realpath -m "$got")" != "$(realpath -m "$REAL_STORE")" ] && [ "$H" != "$REAL_HOME" ] && ok_home=1
truthy "selftest: MEMORY_HOME and HOME are the fixture, not the real ones" "$ok_home"
[ "$bad" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

g() { git -C "$S" -c user.name=fixture -c user.email=fixture@example.invalid "$@" >/dev/null; }
asked() { wc -l <"$LOG" | tr -d ' '; }
quiz() { : >"$LOG"; out=$(fx "$BIN/memory" check --quiz "$@" 2>"$WORK/err"); rc=$?; err=$(cat "$WORK/err"); }

# 1. The merged views: public questions only (private-* stay where they are), every id row.
fx python3 "$ROOT/lib/memory_quiz.py" merge >/dev/null
eq "merge: questions.tsv = header + 6 public questions" 7 "$(wc -l <"$S/checks/questions.tsv" | tr -d ' ')"
ev "merge: no private question in the view" '! grep -q marmalade "$S/checks/questions.tsv"'
eq "merge: ids.tsv = header + 7 ids" 8 "$(wc -l <"$S/checks/ids.tsv" | tr -d ' ')"
ev "merge: an id row gets its page from ids.d" 'grep -qP "\tcore/lore.md\tc101\t" "$S/checks/questions.tsv"'
g init -q; g add -A; g commit -qm fixture

# 2. Plain `memory check` never asks the model.
out=$(fx "$BIN/memory" check 2>&1); rc=$?
ev "plain check: exit 0, no question asked" '[ "$rc" = 0 ] && [ "$(asked)" = 0 ]' || echo "$out"

# 3. First full run: every question asked (private included), all green, baseline written.
quiz
ev "full run: exit 0, 7 asked, 7/7 green" '[ "$rc" = 0 ] && [ "$(asked)" = 7 ] && grep -qx "quiz · 7/7 green" <<<"$err"' || echo "$out$err"
eq "full run: baseline has 7 green rows" 7 "$(grep -cP '^\w+\t1\t' "$S/checks/quiz-baseline.tsv")"
ev "full run: the topic file reaches the model, the ledger does not" 'grep -q "release lighthouse" "$LOG" && ! grep -q obsidian-moth "$LOG"'
cp "$S/checks/quiz-baseline.tsv" "$WORK/base.0"

# 4. One line removed (its id retired, so only the quiz can see the loss): exactly its question turns red, the gate fails.
sed -i '/\^z101$/d' "$S/domains/zebra/stripes.md"
printf 'z101\tdomains/zebra/stripes.md\tretired:fixture\tzebra.md\n' >>"$S/checks/ids.tsv"
out=$(fx "$BIN/memory" check 2>&1); rc=$?
ev "line removed: the other checkers stay green" '[ "$rc" = 0 ]' || echo "$out"
quiz
ev "line removed: exit 1, exactly 1 finding" '[ "$rc" = 1 ] && [ "$(grep -c . <<<"$out")" = 1 ]' || echo "$out$err"
ev "line removed: the finding is that page and that question" \
  'grep -qx "quiz · domains/zebra/stripes.md:0 · [0-9a-f]\{10\}: green in the baseline, red now (missing: gravel, north)" <<<"$out"' || echo "$out"
ev "line removed: 6/7 green, baseline left as it was" 'grep -qx "quiz · 6/7 green" <<<"$err" && cmp -s "$WORK/base.0" "$S/checks/quiz-baseline.tsv"'

# 5. A question already red in the baseline that stays red does not fail the gate (it guards loss, not style).
sed -i -E 's#^([0-9a-f]+)\t1\t(domains/zebra/stripes\.md)#\1\t0\t\2#' "$S/checks/quiz-baseline.tsv"
quiz
ev "known red: exit 0, reported on stderr" '[ "$rc" = 0 ] && grep -q "^quiz · red · domains/zebra/stripes.md · " <<<"$err"' || echo "$out$err"

# 6. --changed asks only the questions of pages that changed since HEAD (here: the zebra card).
cp "$FX/store/domains/zebra/stripes.md" "$S/domains/zebra/stripes.md"; g add -A; g commit -qm restore
printf -- '- The herd sleeps at dusk. (26-03-06) ^z03\n' >>"$S/domains/zebra/DOMAIN.md"
quiz --changed
ev "--changed: exit 0, only the 2 zebra card questions asked" \
  '[ "$rc" = 0 ] && [ "$(asked)" = 2 ] && grep -q "lead zebra" "$LOG" && grep -q "fence" "$LOG"' || { echo "$out$err"; cat "$LOG"; }
eq "--changed: the baseline keeps all 7 rows" 7 "$(tail -n +2 "$S/checks/quiz-baseline.tsv" | grep -c .)"

# 8. The vote (T1599-M07c): a red is re-asked twice and stays red only when most of the 3 asks fail; tokens are reported.
quizx() { : >"$LOG"; rm -f "$LOG.drop"; out=$(fx env "$@" "$BIN/memory" check --quiz 2>"$WORK/err"); rc=$?; err=$(cat "$WORK/err"); }
times() { grep -c "$1" "$LOG"; }
quiz
ev "vote: an all-green run asks 3 calls once, no re-ask, reports the tokens" \
  'grep -qx "quiz · 0 re-asked 2x · first 3 calls, 300 in / 30 out tokens · re-asks 0 calls, 0 in / 0 out tokens" <<<"$err"' || echo "$err"
cp "$S/checks/quiz-baseline.tsv" "$WORK/base.1"
quizx QUIZ_DROP=saffron QUIZ_DROP_N=1
ev "vote: a noisy model failing 1 of 3 asks: green, exit 0, asked 3 times" \
  '[ "$rc" = 0 ] && grep -qx "quiz · 7/7 green" <<<"$err" && [ "$(times lighthouse)" = 3 ]' || echo "$out$err"
ev "vote: the re-asks are counted apart" 'grep -q "^quiz · 1 re-asked 2x · first 3 calls, .* · re-asks 2 calls, 200 in / 20 out tokens$" <<<"$err"' || echo "$err"
quizx QUIZ_DROP=saffron QUIZ_DROP_N=2
ev "vote: failing 2 of 3 asks with saffron still loaded is brittle: exit 0, no finding, a brittle line" \
  '[ "$rc" = 0 ] && [ -z "$out" ] && grep -q "^quiz · brittle · core/lore.md · c101" <<<"$err"' || echo "$out$err"
sed -i '/\^z101$/d' "$S/domains/zebra/stripes.md"
quizx
ev "vote: a removed lesson is red 3 of 3: exit 1, asked 3 times" \
  '[ "$rc" = 1 ] && grep -q "missing: gravel, north" <<<"$out" && [ "$(times "which side")" = 3 ]' || echo "$out$err"
cp "$FX/store/domains/zebra/stripes.md" "$S/domains/zebra/stripes.md"

# 9. --changed and the baseline's page_sha/row_sha: an unchanged git-ignored private page is skipped, an edited row re-asked.
printf 'domains/vault/\n' >"$S/.gitignore"; git -C "$S" rm -rq --cached domains/vault; g add -A; g commit -qm ignore-vault
ev "--changed: the vault page is git-ignored" 'git -C "$S" check-ignore -q domains/vault/DOMAIN.md'
quiz
quiz --changed
ev "--changed: an unchanged private page is not asked (0 asked, exit 0)" '[ "$rc" = 0 ] && [ "$(asked)" = 0 ]' || { echo "$out$err"; cat "$LOG"; }
printf -- '- The vault door is oak. (26-04-02) ^v02\n' >>"$S/domains/vault/DOMAIN.md"
quiz --changed
ev "--changed: an edited private page is asked again (1 asked)" '[ "$rc" = 0 ] && [ "$(asked)" = 1 ] && grep -q "vault combination" "$LOG"' || cat "$LOG"
sed -i 's/\tPemberton\t/\tpemberton\t/' "$S/checks/questions.d/core.tsv"; fx python3 "$ROOT/lib/memory_quiz.py" merge >/dev/null
quiz --changed
ev "--changed: a row edited on an unchanged page is asked again (1 asked)" '[ "$rc" = 0 ] && [ "$(asked)" = 1 ] && grep -q mascot "$LOG"' || cat "$LOG"

# 10. The quiz of a staging copy (T1726): the model's `memory load` reads the staged store, so a fact only on the staged
# core card is answered while MEMORY_HOME still names the live store.
ST="$WORK/staging"; cp -r "$S" "$ST"; rm -rf "$ST/.git"
printf -- '- The fleet kettle is copper. (26-04-03) ^c09\n' >>"$ST/core/CORE.md"
printf 'c09\tWhat is the fleet kettle made of?\tcopper\tkettle.md\n' >>"$ST/checks/questions.d/core.tsv"
fx env MEMORY_HOME="$ST" python3 "$ROOT/lib/memory_quiz.py" merge >/dev/null
: >"$LOG"
fx python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_check, memory_quiz, memory_store; memory_quiz.check(memory_store.Store(sys.argv[2]), {})' \
  "$ROOT/lib" "$ST" 2>"$WORK/err"
ev "staged quiz: the staged core line is answered, 8/8 green" 'grep -qx "quiz · 8/8 green" "$WORK/err" && grep -q kettle "$LOG"' || cat "$WORK/err"

# 11. A must cell "a|b" (T1768) passes on either word; ";" still needs every word.
OR="$WORK/or"; cp -r "$S" "$OR"; rm -rf "$OR/.git"
printf 'c01\tIs the mascot Pemberton or Bobbington?\tBobbington|Pemberton\tor.md\n' >>"$OR/checks/questions.d/core.tsv"
printf 'c02\tAre deploys on Thursday and Fridayx?\tThursday;Fridayx\tor.md\n' >>"$OR/checks/questions.d/core.tsv"
fx env MEMORY_HOME="$OR" python3 "$ROOT/lib/memory_quiz.py" merge >/dev/null
fx python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_check, memory_quiz, memory_store; memory_quiz.check(memory_store.Store(sys.argv[2]), {})' \
  "$ROOT/lib" "$OR" 2>"$WORK/err"
ev "or cell: a|b is green on one word, a;b red on one missing word" \
  'grep -qx "quiz · 8/9 green" "$WORK/err" && grep -q "^quiz · red · core/CORE.md · c02$" "$WORK/err" && ! grep -q "· c01$" "$WORK/err"' || cat "$WORK/err"

# 12. Independent re-asks (T1769): the first ask stays chunked, each red row is re-asked alone, one question per call.
# A model that misses saffron and Thursday whenever it gets more than one question answers both when asked alone.
CH="$WORK/chunky"; CALLS="$WORK/calls"
cat >"$CH" <<EOF
#!/usr/bin/env bash
p=\$(cat); n=\$(sed -n '/<questions>/,/<\/questions>/p' <<<"\$p" | grep -c '^[0-9]*: ')
echo "\$n" >>"$CALLS"
if [ "\$n" -gt 1 ]; then "$FX/stub-model" <<<"\$p" | sed -E 's/saffron|thursday//Ig'; else "$FX/stub-model" <<<"\$p"; fi
EOF
chmod +x "$CH"; : >"$CALLS"
quizx MEMORY_QUIZ_CMD="$CH"
ev "independent re-asks: chunk-only misses are green, exit 0, 7/7" '[ "$rc" = 0 ] && grep -qx "quiz · 7/7 green" <<<"$err"' || echo "$out$err"
ev "independent re-asks: 3 chunked first calls, then 2 reds x 2 re-asks, 1 question each" \
  '[ "$(head -3 "$CALLS" | sort -n | tr "\n" " ")" = "1 3 3 " ] && [ "$(tail -n +4 "$CALLS" | tr "\n" " ")" = "1 1 1 1 " ]' || cat "$CALLS"
ev "independent re-asks: the re-ask calls are counted" 'grep -q "^quiz · 2 re-asked 2x · first 3 calls, .* · re-asks 4 calls, 400 in / 40 out tokens$" <<<"$err"' || echo "$err"

# 13. The gate rule (T1772): a vote-red row blocks only when a must word is gone from the text the quiz loads for it;
# with every must word (any "|" word) still loaded it is brittle: a stderr line, exit 0. Green rows stay green.
GR="$WORK/gate"; cp -r "$S" "$GR"; rm -rf "$GR/.git"
printf 'c101\tWhich paint is on the lighthouse?\tsaffron|vermilion\tor.md\n' >>"$GR/checks/questions.d/core.tsv"
gq() { : >"$LOG"; rm -f "$LOG.drop"; out=$(fx env MEMORY_HOME="$GR" "$@" "$BIN/memory" check --quiz 2>"$WORK/err"); rc=$?; err=$(cat "$WORK/err"); }
fx env MEMORY_HOME="$GR" python3 "$ROOT/lib/memory_quiz.py" merge >/dev/null
gq
ev "gate: baseline run green, 8/8" '[ "$rc" = 0 ] && grep -qx "quiz · 8/8 green" <<<"$err"' || echo "$out$err"
gq QUIZ_DROP=saffron QUIZ_DROP_N=99
ev "gate (b): red by vote, must words loaded (a|b too): exit 0, no finding, 2 brittle lines" \
  '[ "$rc" = 0 ] && [ -z "$out" ] && [ "$(grep -c "^quiz · brittle · core/lore.md · c101" <<<"$err")" = 2 ]' || echo "$out$err"
ev "gate (c): the green rows stay green, nothing else brittle or red" \
  'grep -qx "quiz · 6/8 green" <<<"$err" && [ "$(grep -c "^quiz · \(brittle\|red\) · " <<<"$err")" = 2 ]' || echo "$err"
sed -i 's/gravel path/stone path/' "$GR/domains/zebra/stripes.md"
gq
ev "gate (a): a reword cuts a must word: red by vote and missing from the loaded text, exit 1, 1 finding" \
  '[ "$rc" = 1 ] && [ "$(grep -c . <<<"$out")" = 1 ] && grep -q "missing: gravel" <<<"$out" && ! grep -q "brittle · domains/zebra" <<<"$err"' || echo "$out$err"

# 7. The gate module keeps its size cap.
ev "memory_check.py is at most 300 lines" '[ "$(wc -l <"$ROOT/lib/memory_check.py")" -le 300 ]'

[ "$bad" = 0 ] && echo "memory-quiz.test.sh: all green" || echo "memory-quiz.test.sh: FAILURES"
exit "$bad"
