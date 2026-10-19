#!/usr/bin/env bash
# MEMORY.md index cap (T375): ≤ 60 lines, ≤ 6000 chars, every memory file linked, every link resolves.
set -uo pipefail
MAX_LINES=60 MAX_CHARS=6000
bad=0
ok() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (want $2, got $3)"; bad=$((bad+1)); fi; }

# Prints one problem per line for the memory dir $1; silent when the index is within the cap.
check() {
  local dir=$1 idx=$1/MEMORY.md f
  [ "$(wc -l <"$idx")" -le "$MAX_LINES" ] || echo "lines $(wc -l <"$idx") > $MAX_LINES"
  [ "$(wc -m <"$idx")" -le "$MAX_CHARS" ] || echo "chars $(wc -m <"$idx") > $MAX_CHARS"
  for f in $(grep -o '](\([^)]*\.md\))' "$idx" | sed 's/^](\(.*\))$/\1/'); do
    [ -f "$dir/$f" ] || echo "missing $f"
  done
  for f in "$dir"/*.md; do
    f=${f##*/}; [ "$f" = MEMORY.md ] && continue
    grep -qF "]($f)" "$idx" || echo "unindexed $f"
  done
}

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/good" "$WORK/bad"
printf -- '- [A](a.md) — a\n' >"$WORK/good/MEMORY.md"; : >"$WORK/good/a.md"
{ printf -- '- [A](gone.md) — a\n'; for i in $(seq 70); do printf -- '- %0100d\n' "$i"; done; } >"$WORK/bad/MEMORY.md"
: >"$WORK/bad/orphan.md"
ok "selftest: good fixture passes" "" "$(check "$WORK/good")"
ok "selftest: bad fixture names 4 problems" 4 "$(check "$WORK/bad" | wc -l)"

MEM=${MEMORY_DIR:-$HOME/.claude/projects/$(tr / - <<<"$HOME")/memory}
ok "real index within cap, all files linked" "" "$(check "$MEM")"

[ "$bad" = 0 ] && echo "all memory-index fixtures pass"
exit "$bad"
