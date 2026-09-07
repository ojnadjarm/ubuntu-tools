#!/usr/bin/env bash
# Build the NEW arm: a mirror of the live tree, so both arms are presented the same way
# (same bwrap wrapper, same paths). Symlink farm — content tracks the live files.
set -euo pipefail
ARM="${1:-$HOME/agents/bench/arms/new}"
rm -rf "$ARM"; mkdir -p "$ARM/bin" "$ARM/KB" "$ARM/skills"
cp -a "$HOME/agents/bin"/. "$ARM/bin/"; rm -rf "$ARM/bin/__pycache__"
cp -a "$HOME/agents/KB"/.  "$ARM/KB/"
cp -r "$HOME/.claude/skills/desktop" "$ARM/skills/desktop"
cp "$HOME/agents/README-pc-control.md" "$ARM/README-pc-control.md"
echo "new arm built: $ARM ($(ls "$ARM/bin"/pc-* | wc -l) pc subcommands)"
