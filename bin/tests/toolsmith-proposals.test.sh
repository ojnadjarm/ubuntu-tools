#!/usr/bin/env bash
# TS03: linter for toolsmith proposals + BACKLOG.md against PROPOSAL-TEMPLATE.md's contract.
# Proves itself against two roots: the real tree (must be clean) and a broken fixture (must not).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL="$HERE/../../toolsmith"
FIX="$HERE/fixtures/toolsmith-proposals"
STATUSES='^(proposed|go|building|measuring|done|no-effect|regressed|dropped|blocked)$'

lint_root() { # lint_root <dir> <backlog> — prints one error per line, returns the error count
  local dir="$1" backlog="$2" errs=0 f id sc sess cls
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    for s in Problem Evidence Survey "Proposed change" "Success check" Effort Class; do
      grep -q "^## $s\$" "$f" || { echo "$f: missing section '$s'"; errs=$((errs+1)); }
    done
    # money: `$1` inside a code span is shell, not an amount — strip code spans for the $ test
    { sed 's/`[^`]*`//g' "$f" | grep -qiE '\$[0-9]|[0-9]\$'; } \
      && { echo "$f: money figure"; errs=$((errs+1)); }
    grep -qiE '\bcost\b|\bbudget\b' "$f" \
      && { echo "$f: money word"; errs=$((errs+1)); }
    awk '/^## Evidence/{f=1;next}/^## /{f=0}f' "$f" \
      | grep -qE '`[^`]+:[0-9]+[0-9,-]*`|`[^`]+/[^`]+/[^`]+/[0-9]+`' \
      || { echo "$f: Evidence has no path:line or run/task/arm/i citation"; errs=$((errs+1)); }
    sc=$(awk '/^## Success check/{f=1;next}/^## /{f=0}f' "$f")
    { grep -qE 'before:.*[0-9]' <<<"$sc" && grep -qE 'target:.*[0-9]' <<<"$sc"; } \
      || { echo "$f: Success check missing a before/target number"; errs=$((errs+1)); }
    sess=$(awk '/^## Effort/{f=1;next}/^## /{f=0}f' "$f" | grep -oE 'sessions:[[:space:]]*[^[:space:]]+' | grep -oE '[^[:space:]]+$')
    [[ "$sess" =~ ^[0-9]+$ ]] || { echo "$f: sessions '$sess' not an integer"; errs=$((errs+1)); }
    cls=$(awk '/^## Class/{f=1;next}/^## /{f=0}f' "$f" | grep -vE '^[[:space:]]*$' | head -1 | xargs)
    [[ "$cls" =~ ^(auto-ok|owner-go)(\ contract-§[0-9]+)?$ ]] || { echo "$f: Class '$cls' invalid"; errs=$((errs+1)); }
  done
  [ -f "$backlog" ] && while IFS='|' read -r _ _ id _ _ status _; do
    id=$(xargs <<<"$id"); status=$(xargs <<<"$status")
    [[ "$id" =~ ^TSP- ]] || continue
    # accept both TSP-NNN.md and TSP-NNN-<slug>.md
    { ls "$dir/$id".md >/dev/null 2>&1 || ls "$dir/$id"-*.md >/dev/null 2>&1; } \
      || { echo "$backlog: $id has no proposal file"; errs=$((errs+1)); }
    [[ "$status" =~ $STATUSES ]] || { echo "$backlog: $id status '$status' invalid"; errs=$((errs+1)); }
  done < <(grep '| TSP-' "$backlog")
  return "$errs"
}

bad=0
lint_root "$REAL/proposals" "$REAL/BACKLOG.md" >/tmp/toolsmith-lint-real.$$ 2>&1; real_errs=$?
if [ "$real_errs" = 0 ]; then echo "ok   real tree is clean"; else
  echo "FAIL real tree is clean:"; cat /tmp/toolsmith-lint-real.$$; bad=1
fi
rm -f /tmp/toolsmith-lint-real.$$

lint_root "$FIX/proposals" "$FIX/BACKLOG.md" >/tmp/toolsmith-lint-fix.$$ 2>&1; fix_errs=$?
if [ "$fix_errs" -gt 0 ]; then
  echo "ok   fixture is caught broken ($fix_errs errors):"; cat /tmp/toolsmith-lint-fix.$$
else
  echo "FAIL fixture should have failed the linter"; bad=1
fi
rm -f /tmp/toolsmith-lint-fix.$$

[ "$bad" = 0 ] && echo "all toolsmith-proposals cases pass" || echo "FAILURES"
exit "$bad"
