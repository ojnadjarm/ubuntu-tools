#!/usr/bin/env bash
# Build the NEW arm: a mirror of the live tree, so both arms are presented the same way
# (same bwrap wrapper, same paths). Symlink farm — content tracks the live files.
set -euo pipefail
SRC="${PCBENCH_SRC:-$HOME/agents}"
SRC_SKILL="${PCBENCH_SRC_SKILL:-$HOME/.claude/skills/desktop}"
ARM="${1:-$SRC/bench/arms/new}"
rm -rf "$ARM"; mkdir -p "$ARM/bin" "$ARM/KB" "$ARM/skills"
cp -a "$SRC/bin"/. "$ARM/bin/"; rm -rf "$ARM/bin/__pycache__"
cp -a "$SRC/KB"/.  "$ARM/KB/"
cp -r "$SRC_SKILL" "$ARM/skills/desktop"
cp "$SRC/README-pc-control.md" "$ARM/README-pc-control.md"
echo "new arm built: $ARM ($(ls "$ARM/bin"/pc-* | wc -l) pc subcommands)"
