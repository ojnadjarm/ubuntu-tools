#!/usr/bin/env bash
# ram (T1841): note kinds, 240-char refusal, redaction, one next slot, 4,096 B overflow, parallel writers, show, close, gc.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
RAM="$BIN/ram"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export AGENT_WORK="$T/aw" XDG_RUNTIME_DIR="$T/run" HOME="$T/home" HARNESS_CONFIG="$T/config.env"
unset TASK_RAM RAM_TICKET
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
fail=0 n=0
ok() { n=$((n+1)); echo "ok - $1"; }
no() { n=$((n+1)); echo "not ok - $1"; fail=1; }
N="$AGENT_WORK/ram/T5/notes.md"

for k in fact tried decided next done; do "$RAM" note T5 "$k" "a $k line" --src lib/x.py:1; done
c=$(grep -cE '^- [0-9]{2}:[0-9]{2} (fact|tried|decided|next|done) · a \w+ line · lib/x.py:1$' "$N")
[ "$c" = 5 ] && ok "one line of each kind" || no "kinds: $c lines in $(cat "$N")"

o=$("$RAM" note T5 fact "$(printf 'x%.0s' $(seq 241))" 2>&1); rc=$?
[ $rc -ne 0 ] && grep -q 240 <<<"$o" && [ "$(grep -c '^- ' "$N")" = 5 ] && ok "241 chars refused: $o" || no "long line: rc=$rc $o"

"$RAM" note T5 fact "the key is token=abcdef123456789 here"
grep -q 'token=<redacted>' "$N" && ! grep -q abcdef123456789 "$N" && ok "secret redacted" || no "secret: $(tail -1 "$N")"

"$RAM" note T5 next "step two"
[ "$(grep -c ' next · ' "$N")" = 1 ] && grep -q ' next · step two$' "$N" && ok "next replaces next" || no "next: $(grep next "$N")"

for i in $(seq 60); do "$RAM" note T5 done "finished step $i of the long run, padded to a good length for the size test"; done
size=$(stat -c %s "$N")
[ "$size" -le 4096 ] && grep -q 'finished step 1 of' "$AGENT_WORK/ram/T5/notes.old.md" && grep -q "finished step 60 " "$N" \
  && grep -q ' tried · ' "$N" && ok "over 4,096 B: oldest done moved ($size B)" || no "overflow: $size B"
for i in $(seq 45); do "$RAM" note T5 fact "fact number $i of the long run, padded to a good length for the size test"; done
[ "$(stat -c %s "$N")" -le 4096 ] && ! grep -q ' done · ' "$N" && grep -q 'fact number 1 of' "$AGENT_WORK/ram/T5/notes.old.md" \
  && grep -q 'fact number 45 ' "$N" && ok "then the oldest fact lines" || no "fact overflow: $(cat "$N")"

for i in $(seq 20); do "$RAM" note T6 tried "writer $i" & done; wait
[ "$(grep -c ' tried · writer ' "$AGENT_WORK/ram/T6/notes.md")" = 20 ] && ok "20 writers at once, 20 lines" \
  || no "parallel: $(grep -c tried "$AGENT_WORK/ram/T6/notes.md")"

s=$("$RAM" show T5); rc=$?
first=$(sed -n 2p <<<"$s")
[ $rc = 0 ] && [ ${#s} -le 2000 ] && grep -q ' next · step two' <<<"$first" && grep -q ' decided · ' <<<"$s" \
  && grep -q ' tried · ' <<<"$s" && grep -q 'fact number 45 ' <<<"$s" && ! grep -q 'fact number 1 of' <<<"$s" \
  && ok "show: next first, decided, tried, newest facts, ${#s} chars" || no "show: rc=$rc ${#s} $s"
s=$("$RAM" show T99); rc=$?
[ $rc = 0 ] && [ -z "$s" ] && ok "show unknown ticket: nothing, exit 0" || no "show unknown: rc=$rc '$s'"

cp "$N" "$T/before.md"
"$RAM" close T5
cmp -s "$T/before.md" "$AGENT_WORK/evidence/T5/ram.md" && [ ! -e "$AGENT_WORK/ram/T5" ] && ok "close: copied to evidence, folder gone" \
  || no "close: $(ls -R "$AGENT_WORK")"

"$RAM" note T7 fact old; "$RAM" note T8 fact fresh
find "$AGENT_WORK/ram/T7" -exec touch -d '49 hours ago' {} +
find "$AGENT_WORK/ram/T8" -exec touch -d '47 hours ago' {} +
"$RAM" gc
[ ! -e "$AGENT_WORK/ram/T7" ] && [ -e "$AGENT_WORK/ram/T8" ] && [ -e "$AGENT_WORK/ram/T6" ] && ok "gc: only 48 h untouched removed" \
  || no "gc: $(ls "$AGENT_WORK/ram")"

echo "$n tests"
exit $fail
