#!/usr/bin/env bash
# Build the OLD arm (2026-09-06 evening, reconstructed) under ~/agents/bench/arms/old/.
# bin: a copy of `pc` + symlinks to the 22 pre-PT02 subcommands and their helpers; every
# pc-* created by PT02-PT16 is absent. KB/skills: the live docs with the PT-era sections
# stripped (PLAN-PCBENCH 2.7). Nothing outside ~/agents/bench/ is written.
set -euo pipefail
SRC="${PCBENCH_SRC:-$HOME/agents}"
SRC_BIN="$SRC/bin"; SRC_KB="$SRC/KB"
SRC_SKILL="${PCBENCH_SRC_SKILL:-$HOME/.claude/skills/desktop}"
SRC_RD="$SRC/README-pc-control.md"
ARM="${1:-$SRC/bench/arms/old}"

OLD_SUBS=(a11y-click click click-text clip drag find key mode move notify open scroll see
          selftest shot spotify status tree type wait wait-for win)

rm -rf "$ARM"; mkdir -p "$ARM/bin" "$ARM/KB" "$ARM/skills"

# Real copies, never symlinks: the arm is bind-mounted *over* ~/agents/bin, so an absolute
# symlink into ~/agents/bin would resolve to itself inside the sandbox.
cp -a "$SRC_BIN"/. "$ARM/bin/"
rm -rf "$ARM/bin/__pycache__"
for f in "$ARM"/bin/pc-*; do
  s="${f##*/pc-}"; keep=0
  for o in "${OLD_SUBS[@]}"; do [ "$s" = "$o" ] && keep=1; done
  [ "$keep" = 1 ] || rm -f "$f"
done
rm -f "$ARM"/bin/pc_dbus.py "$ARM"/bin/pc_top.py "$ARM"/bin/pc_input.py   # helpers of the removed verbs

# KB: everything but pc-cli.md, which did not exist before PT15.
cp -a "$SRC_KB"/. "$ARM/KB/"
rm -f "$ARM/KB/pc-cli.md"
cp -r "$SRC_SKILL" "$ARM/skills/desktop"

python3 - "$SRC_KB/toolbox.md" "$ARM/KB/toolbox.md" "$ARM/skills/desktop/SKILL.md" \
          "$SRC_RD" "$ARM/README-pc-control.md" <<'PY'
import re, sys
tb_in, tb_out, skill, rd_in, rd_out = sys.argv[1:6]

t = open(tb_in).read()
# 2. the four layer rows added by PT02-PT16
for row in ("| kernel |", "| session |", "| services |", "| safety |"):
    t = re.sub(r"^" + re.escape(row) + r".*\n", "", t, flags=re.M)
# 2. the pc-cli.md pointer + the ledger paragraph
t = re.sub(r"\nFull reference, one row per command.*?prints `rollback: pc undo <id>` last\.\n", "", t, flags=re.S)
# 6.11
t = re.sub(r"\n11\. \*\*Mutate through `--apply`.*\Z", "\n", t, flags=re.S)
open(tb_out, "w").write(t)

s = open(skill).read()
s = re.sub(r"\nBelow the screen: `pc mutter.*?`pc help --md > ~/agents/KB/pc-cli\.md`\)\.\n", "", s, flags=re.S)
s = re.sub(r"^- \*\*Mutations need `--apply`\*\*.*\n", "", s, flags=re.M)
open(skill, "w").write(s)

r = open(rd_in).read()
r = re.sub(r"## The ledger, `pc doctor`.*?(?=## Window management)", "", r, flags=re.S)
open(rd_out, "w").write(r)
PY

{ echo "# RECONSTRUCTION.diff — live docs (new arm) -> old arm, PLAN-PCBENCH 2.7."
  echo "# Reconstructed, not historical: no pre-2026-09-07 copy of toolbox.md exists."
  diff -u "$SRC_KB/toolbox.md" "$ARM/KB/toolbox.md" || true
  diff -u "$SRC_SKILL/SKILL.md" "$ARM/skills/desktop/SKILL.md" || true
  diff -u "$SRC_RD" "$ARM/README-pc-control.md" || true
  echo "--- $SRC_KB/pc-cli.md"; echo "+++ (absent in the old arm)"
} > "$ARM/RECONSTRUCTION.diff"
echo "old arm built: $ARM ($(ls "$ARM/bin"/pc-* | wc -l) pc subcommands)"
