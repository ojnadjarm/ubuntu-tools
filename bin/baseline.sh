#!/bin/bash
# Timestamped tarball of the agent-relevant user config; keeps the last 20.
set -euo pipefail

BACKUP_DIR="$HOME/agents/backups"
STAMP=$(date +%Y-%m-%d_%H%M%S)
OUT="$BACKUP_DIR/$STAMP.tar.gz"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$BACKUP_DIR"
dconf dump / > "$STAGE/dconf.ini"

FILES=()
for p in .claude/settings.json .claude/hooks .claude/skills CLAUDE.md agents/bin; do
    [ -e "$HOME/$p" ] && FILES+=("$p")
done
for f in "$HOME"/.claude/*.md; do
    [ -e "$f" ] && FILES+=(".claude/$(basename "$f")")
done

tar czf "$OUT" -C "$HOME" "${FILES[@]}" -C "$STAGE" dconf.ini

ls -1t "$BACKUP_DIR"/*.tar.gz | tail -n +21 | xargs -r rm -f
echo "$OUT"
