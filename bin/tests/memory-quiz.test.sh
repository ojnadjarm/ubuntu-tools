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

# 7. The gate module keeps its size cap.
ev "memory_check.py is at most 300 lines" '[ "$(wc -l <"$ROOT/lib/memory_check.py")" -le 300 ]'

[ "$bad" = 0 ] && echo "memory-quiz.test.sh: all green" || echo "memory-quiz.test.sh: FAILURES"
exit "$bad"
