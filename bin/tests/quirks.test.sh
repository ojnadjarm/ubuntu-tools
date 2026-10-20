#!/usr/bin/env bash
# T909: every top-level bullet of KB/quirks.md ends with a dated (verified|gone|unverified YYYY-MM-DD: …) tag no older than 60 days.
# Usage: quirks.test.sh [quirks.md]   (QUIRKS_TODAY=YYYY-MM-DD pins today; QUIRKS_MAX_AGE days, default 60; QUIRKS_MIN_BULLETS, default 60)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE="${1:-$HERE/../../KB/quirks.md}"
bad=0
ok() { if [ "$1" = 1 ]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad+1)); fi; }

# check <file> <today> [min]: prints "line N: <problem>" per bad bullet and "bullets N"; rc 1 on any problem or fewer than min bullets.
check() {
  local cutoff
  cutoff="$(date -d "$2 -${QUIRKS_MAX_AGE:-60} days" +%F)" || return 2
  awk -v cutoff="$cutoff" -v today="$2" -v min="${3:-0}" '
    function flush() {
      if (!start) return
      n++
      if (match(text, /\((verified|gone|unverified) [0-9]{4}-[0-9]{2}-[0-9]{2}: [^()]+\)$/)) {
        d = substr(text, RSTART, RLENGTH); sub(/^\([a-z]+ /, "", d); d = substr(d, 1, 10)
        if (d < cutoff) { printf "line %d: tag %s older than %s\n", start, d, cutoff; bad++ }
        else if (d > today) { printf "line %d: tag %s is in the future\n", start, d; bad++ }
      } else { printf "line %d: no (verified|gone|unverified <date>: ...) tag at the end\n", start; bad++ }
      start = 0
    }
    /^- / { flush(); start = NR; text = $0; sub(/[ \t]+$/, "", text); next }
    start && /^[ \t]+[^ \t]/ { t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); text = text " " t; next }
    { flush() }
    END { flush(); if (n < min) printf "only %d bullets, fewer than %d\n", n, min; printf "bullets %d\n", n; exit bad > 0 || n < min }
  ' "$1"
}

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat >"$T/pass.md" <<'EOF'
## A
- one line quirk (verified 2026-10-20: gsettings get reads flat)
- two line quirk that wraps
  onto a second line (gone 2026-09-01: tool removed)

- needs a live action (unverified 2026-10-01: needs the TV on)
Paragraph text without a tag is not a bullet.
EOF
cat >"$T/untagged.md" <<'EOF'
- tagged (verified 2026-10-20: ok)
- untagged quirk
  still untagged
EOF
cat >"$T/stale.md" <<'EOF'
- old tag (verified 2026-08-01: ok)
EOF
cat >"$T/midtag.md" <<'EOF'
- tag in the middle (verified 2026-10-20: ok)
  then more text after it
EOF
cat >"$T/undated.md" <<'EOF'
- undated (unverified: needs the TV)
EOF

out=$(check "$T/pass.md" 2026-10-20); ok "$([ $? = 0 ] && grep -qx 'bullets 3' <<<"$out" && echo 1)" "fixture: 3 tagged bullets pass"
out=$(check "$T/untagged.md" 2026-10-20); ok "$([ $? = 1 ] && grep -q '^line 2: no ' <<<"$out" && echo 1)" "fixture: untagged bullet fails"
out=$(check "$T/stale.md" 2026-10-20); ok "$([ $? = 1 ] && grep -q 'older than 2026-08-21' <<<"$out" && echo 1)" "fixture: 80-day-old tag fails"
out=$(check "$T/stale.md" 2026-09-30); ok "$([ $? = 0 ] && echo 1)" "fixture: 60-day-old tag passes"
out=$(check "$T/midtag.md" 2026-10-20); ok "$([ $? = 1 ] && echo 1)" "fixture: tag not at the bullet end fails"
out=$(check "$T/undated.md" 2026-10-20); ok "$([ $? = 1 ] && echo 1)" "fixture: undated tag fails"
: >"$T/empty.md"
out=$(check "$T/empty.md" 2026-10-20 60); ok "$([ $? = 1 ] && grep -qx 'bullets 0' <<<"$out" && echo 1)" "fixture: empty file fails the 60-bullet floor"
out=$(check "$T/pass.md" 2026-10-20 60); ok "$([ $? = 1 ] && grep -q 'only 3 bullets' <<<"$out" && echo 1)" "fixture: 3 bullets fail the 60-bullet floor"
out=$(check "$T/pass.md" 2026-10-20 3); ok "$([ $? = 0 ] && echo 1)" "fixture: 3 bullets meet a 3-bullet floor"
if [ -f "$FILE" ]; then
  awk '/^- /{n++} n>30{exit} {print}' "$FILE" >"$T/truncated.md"
  out=$(check "$T/truncated.md" "${QUIRKS_TODAY:-$(date +%F)}" 60); ok "$([ $? = 1 ] && grep -q 'fewer than 60' <<<"$out" && echo 1)" "fixture: copy truncated to 30 bullets fails the 60-bullet floor"
fi

out=$(check "$FILE" "${QUIRKS_TODAY:-$(date +%F)}" "${QUIRKS_MIN_BULLETS:-60}"); rc=$?
[ $rc = 0 ] || printf '%s\n' "$out" | sed 's/^/  /'
ok "$([ $rc = 0 ] && echo 1)" "$(basename "$FILE"): every bullet tagged within ${QUIRKS_MAX_AGE:-60} days ($(tail -1 <<<"$out"))"

[ $bad = 0 ] && echo "quirks: all passed" || echo "quirks: $bad failed"
[ $bad = 0 ]
