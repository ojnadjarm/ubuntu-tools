#!/bin/bash
# Timestamped tarball of the agent-relevant user config; keeps the last 20 of its own YYYY-MM-DD_HHMMSS.tar.gz.
# Env: HARNESS_CONTEXT_DIR (context dir, default ~/.claude), BASELINE_DIR (output dir, default ~/agents/backups).
case "${1:-}" in -h|--help) awk 'NR>1&&/^#/{sub(/^# ?/,"");print;next}NR>1{exit}' "$0"; exit 0 ;; esac
set -euo pipefail

BACKUP_DIR="${BASELINE_DIR:-$HOME/agents/backups}"
CTX="${HARNESS_CONTEXT_DIR:-$HOME/.claude}"
CTX_PARENT=$(dirname "$CTX"); CTX_NAME=$(basename "$CTX")
STAMP=$(date +%Y-%m-%d_%H%M%S)
OUT="$BACKUP_DIR/$STAMP.tar.gz"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$BACKUP_DIR"
STAGED=()
if ! command -v dconf >/dev/null; then
    why="no dconf command"
elif dconf dump / > "$STAGE/dconf.ini" 2>/dev/null; then
    STAGED+=(dconf.ini)
else
    why="dconf dump rc $?"
fi
if [ -n "${why:-}" ]; then
    echo "baseline: dconf: skipped ($why)" >&2
    echo "dconf: skipped ($why)" >"$STAGE/MANIFEST"
    STAGED+=(MANIFEST)
fi

FILES=()
for p in CLAUDE.md agents/ORCHESTRATOR.md agents/bin; do
    [ -e "$HOME/$p" ] && FILES+=("$p")
done
CTX_FILES=()
for p in settings.json hooks skills; do
    [ -e "$CTX/$p" ] && CTX_FILES+=("$CTX_NAME/$p")
done
for f in "$CTX"/*.md; do
    [ -e "$f" ] && CTX_FILES+=("$CTX_NAME/$(basename "$f")")
done

ARGS=()
[ ${#FILES[@]} -gt 0 ] && ARGS+=(-C "$HOME" "${FILES[@]}")
[ ${#CTX_FILES[@]} -gt 0 ] && ARGS+=(-C "$CTX_PARENT" "${CTX_FILES[@]}")
[ ${#STAGED[@]} -gt 0 ] && ARGS+=(-C "$STAGE" "${STAGED[@]}")
tar czf "$OUT" "${ARGS[@]}"

find "$BACKUP_DIR" -maxdepth 1 -type f -regextype posix-extended \
    -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}\.tar\.gz' -printf '%f\n' \
    | sort -r | tail -n +21 | while read -r f; do rm -f "$BACKUP_DIR/$f"; done
echo "$OUT"
