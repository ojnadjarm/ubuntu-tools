# T10 — Accessibility tree dump (`pc tree`)

**Phase 1 · nice · Model: opus · Estimated agent time: 60 min**

## Goal
Agents can read the semantic UI tree (roles, names, positions) of GTK/Chrome windows via AT-SPI, like Playwright's snapshot but for the desktop, and act on elements by name.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/` (after T05), `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- `gir1.2-atspi-2.0` and `python3-gi` are installed (`from gi.repository import Atspi` works). `org.gnome.desktop.interface toolkit-accessibility` is `false`: setting it `true` turns AT-SPI on for GTK apps; Chrome needs `--force-renderer-accessibility` or the env `ACCESSIBILITY_ENABLED=1` to expose its tree.
- Risk: accessibility slightly slows Chrome. Acceptable; note it in the KB quirks.

## Steps
1. `gsettings set org.gnome.desktop.interface toolkit-accessibility true` (also in the dconf profile from T02).
2. `pc-tree [app-substring] [--depth N] [--json]`: walk the Atspi desktop, print role, name, and extents for visible/showing nodes only; cap output at ~300 lines by default; `--find "name"` prints the centre coordinates of the first match (role optional `--role push button`).
3. `pc-a11y-click "name" [--role R]`: tree find + `pc click`; fall back to `Atspi.Action` `do_action(0)` when extents are empty.
4. Document in `/desktop` skill: order of preference `pc win` → `pc tree` → `pc find` (OCR) → raw coordinates.

## Success check
```bash
gsettings get org.gnome.desktop.interface toolkit-accessibility   # true
pc open gnome-calculator && sleep 2 && pc tree calculator | grep -c "push button"   # > 10
pc a11y-click "7" && pc a11y-click "+" && pc a11y-click "2" && pc a11y-click "=" && pc shot /tmp/t10.png   # Read: 9
killall gnome-calculator
```

## Rollback
`gsettings reset org.gnome.desktop.interface toolkit-accessibility`; delete `pc-tree`, `pc-a11y-click`.
