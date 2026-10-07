#!/usr/bin/env bash
# T48-L2: improve-gate classes 12 fixture proposals, imports the open TSPs into a temp queue, rejects broken queue items.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/improve-gate"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }

# 1. every fixture's expected class is its file-name prefix.
hit=0; n=0
while IFS=$'\t' read -r f cls _; do
  n=$((n+1)); want=$(basename "$f" | sed -E 's/-[0-9]+-.*//')
  [ "$cls" = "$want" ] && hit=$((hit+1)) || nok "class $(basename "$f")" "got $cls, want $want"
done < <("$BIN/improve-gate" class "$FIX"/proposals/*.md)
[ "$hit" = 12 ] && [ "$n" = 12 ] && ok "fixture proposals classed $hit/$n" || nok 'fixture proposals' "$hit/$n"

# 2. import reads the toolsmith tree and writes only into the temp queue.
out=$("$BIN/improve-gate" import --to "$WORK/q")
[ "$(tail -1 <<<"$out")" = 'imported 10' ] && ok 'imported 10 open TSPs' || nok 'import count' "$(tail -1 <<<"$out")"
cr=0; for f in "$WORK"/q/*.md; do
  grep -qE '^class: (auto|owner-go|owner-reboot)$' "$f" && grep -qE '^rollback: .+' "$f" && cr=$((cr+1))
done
[ "$cr" = 10 ] && ok "class + rollback on $cr/10" || nok 'class + rollback' "$cr/10"
"$BIN/improve-gate" check "$WORK"/q/*.md >/dev/null && ok 'imported queue passes check' || nok 'imported queue passes check' 'rc != 0'

# 3. check accepts the valid item and flags each broken one.
"$BIN/improve-gate" check "$FIX/queue/ok-valid.md" >/dev/null && ok 'valid item passes' || nok 'valid item passes' 'rc != 0'
for f in understated no-rollback refused; do
  "$BIN/improve-gate" check "$FIX/queue/bad-$f.md" >/dev/null && nok "bad-$f rejected" 'rc 0' || ok "bad-$f rejected"
done

[ "$bad" = 0 ] && echo "all improve-gate cases pass" || echo "FAILURES"
exit "$bad"
