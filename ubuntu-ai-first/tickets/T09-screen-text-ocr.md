# T09 — Find text on screen (OCR) and click it

**Phase 1 · nice · Model: opus · Estimated agent time: 60 min**

## Goal
Agents get exact pixel coordinates for visible text (`pc find "Save changes"`) and can click it in one step, instead of estimating coordinates from a screenshot.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/` (after T05), `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- `pc shot`, `pc click` exist (T07). Screen 1920x1080, dark theme (`prefer-dark`): OCR needs an inverted/thresholded pass too.
- Tesseract is not installed: `sudo apt install -y tesseract-ocr tesseract-ocr-eng tesseract-ocr-spa python3-pytesseract python3-pil` (or pipx-free system packages; prefer apt).

## Steps
1. `pc-find "text" [--all] [--region X,Y,W,H] [--json]`: take a shot, run tesseract with `image_to_data` (psm 11) on the original and on an inverted copy, merge word boxes into lines, fuzzy-match (case-insensitive, ≥ 0.85 ratio) and print centre `X Y` of the best match (all matches with `--all`). Exit 1 if not found.
2. `pc-click-text "text" [--index N]` = find + click, prints where it clicked.
3. Add `pc find` to the selftest (find "7" on the calculator) and to the `/desktop` skill: "prefer `pc click-text` for buttons/menus; fall back to coordinates for icons".

## Success check
```bash
pc open gnome-calculator && sleep 2 && pc find "9"        # prints X Y inside the calculator window
pc click-text "9" && pc click-text "+" && pc click-text "1" && pc click-text "=" && pc shot /tmp/t09.png   # Read: result 10
killall gnome-calculator
time pc find "nothing-on-screen-xyz"; echo exit=$?         # exit=1 in < 4 s
```

## Rollback
Delete `pc-find`, `pc-click-text`; `sudo apt remove tesseract-ocr`.
