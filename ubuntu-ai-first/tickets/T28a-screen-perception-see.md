# T28a — Screen perception in text: `pc see`, `pc wait-for`, real GTK4 coordinates

**Phase 1 · must · Model: opus · Estimated agent time: 90 min**

## Goal
An agent learns what is on the screen with one text command (`pc see`: focused window, window list, interactive UI tree with real screen coordinates, visible notifications, clipboard head — under 1 s and under 4 KB) and waits for UI changes with one blocking command (`pc wait-for`), so a screenshot becomes the exception instead of the default look.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/` (quirks.md), `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4), `~/agents/ubuntu-ai-first/qa/phase1.md` (defects D1, D4, D7, D8). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Run `~/agents/bin/baseline.sh` before touching `~/agents/bin` or `~/.claude/skills`.
- The owner watches this desktop on a TV mirror: open only gnome-calculator / gnome-text-editor for tests, close them, leave no PNGs in `/tmp`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers (measured 2026-09-05 by the architect)
- Why: one look today = `pc shot` (0.8 s, 386 KB full / 100 KB at `--scale 0.5`) **plus a second tool call** (Read, ~1400 image tokens full, ~350 at 0.5) plus a model turn to interpret pixels; `pc wait N` then repeats it. Text is one call, greppable, exact: `pc win list` 0.09 s; `pc tree gnome-calculator` 0.19 s, 75 nodes / 3.8 KB; but an unfiltered `pc tree` is 873 lines / 69 KB (the gnome-shell tree alone) — pruning is mandatory.
- **GTK4 extents, the actual fix.** `Atspi.Component.get_extents(node, CoordType.SCREEN)` returns `0,0` for GTK4 on Wayland, but `CoordType.WINDOW` returns correct window-relative coordinates: calculator button `7` → `(323,548 132x44)` inside a `1299x736` frame while window-calls `GetFrameRect` said `x=67 y=32 1299x736`, so screen = `(67+323, 32+548)`. Map an AT-SPI application to its window by frame name == window title (`Calculator`), else the focused window. That test window was maximised: **verify on a non-maximised window** that CSD shadows are not included (compare the a11y `frame` WxH with `GetFrameRect` WxH; if the frame is larger, subtract half the difference from x and y).
- window-calls (`org.gnome.Shell.Extensions.Windows`): `List`, `Details`, `GetFrameRect` work; `GetFrameBounds` throws (`get_frame_bounds is not a function`) — do not use it; the interface has **no signals**. AT-SPI events do fire (`window:activate "Calculator"` was received while opening it) but polling every 250 ms costs nothing at 0.09 s per `List`; use polling, not an event loop.
- Notifications: `org.freedesktop.Notifications` has no history API, but the gnome-shell a11y tree contains the visible banner (`label "T28 probe" (473,105 68x18)`) and the message-list history with `INT_MIN` extents while hidden. Read them from the tree with `pc tree gnome-shell`; no daemon.
- Focused widget: AT-SPI state `FOCUSED` on a node of the focused app (calculator: `text ""`). Clipboard: `timeout 1 wl-paste -n | head -c 200` (0.1 s; `wl-paste` blocks when nothing owns the clipboard).
- Code lives in `~/agents/bin/a11y_tree.py` (walker), `pc-win` (window-calls), `pc-tree`, `pc-a11y-click` (a 3-line shim into a11y_tree.py `--click`). Extend the walker; `pc-see` and `pc-wait-for` must stay thin. Chrome exposes its tree only with `ACCESSIBILITY_ENABLED=1` (T28b); `pc see` must say so instead of printing two empty frames.

## Steps
1. **Real coordinates in `a11y_tree.py`.** Per application, resolve its window frame rect once (`GetFrameRect` via the title match above). For nodes whose SCREEN extents are `0,0` use WINDOW extents + frame origin (shadow-corrected). `pc tree` prints screen coordinates for GTK4 apps; `pc tree --find` returns them; `pc a11y-click` clicks the centre when coordinates exist and keeps the `do_action(0)` fallback. Add `--interactive`: keep roles `button, toggle button, checkbox, radio button, text, entry, password text, combo box, spin button, slider, menu item, check menu item, radio menu item, page tab, tab, link, list item, tree item, heading` plus any `label` with a name; drop unnamed wrappers; mark the FOCUSED node with a leading `*`; flat output (indent ≤ 2).
2. **`pc-see [SEL] [--json] [--max-bytes N]`** (default N=4000). Sections in this order, one line each where possible:
   `focus: <id> <class> "<title>" WxH+X+Y` (or `focus: none`) · `windows:` (id, class, title; cap 15, mark focused) · `ui:` the `--interactive` tree of the focused window (or `SEL`) with screen coordinates · `notifications:` up to 3 most recent from the gnome-shell tree (banner first) · `clip: <first 100 chars, one line>`. When the app exposes fewer than 3 nodes print `ui: no accessible tree (Xwayland or Chrome without ACCESSIBILITY_ENABLED) — use pc shot`. Truncate `ui:` to fit `--max-bytes` and end with `… N more (pc tree <app>)`. Target < 1.0 s wall time. `--json` returns the same as one object.
3. **`pc-wait-for`** with exactly one condition: `--window "sub"` (title/class matches an existing window), `--focus "sub"` (matches and is focused), `--text "name"` (an interactive node with that name is showing in the focused app, or in `--app SUB`), `--gone "sub"` (no window matches). Options `--timeout S` (default 15), `--see` (print `pc see` on success). Poll every 250 ms; print `ok after 1.3 s` / `timeout after 15.0 s`; exit 0 / 1; exit 2 on bad arguments. No screenshots inside.
4. **Skill + README** (`~/.claude/skills/desktop/SKILL.md`, `~/agents/README-pc-control.md`, one wording): add **Rule 0: text before pixels** — before driving any GUI, look for the CLI/D-Bus route (`gsettings`, `gdbus`, `gio`, `wpctl`, `playerctl`, `nmcli`, `xdg-open`, the app's own CLI) and use the GUI only for what has no such route; the loop becomes **`pc see` → act → `pc wait-for … --see`**; `pc shot` only when `ui:` reports no tree, when rendering/layout itself is the question, or when the tree gives no coordinates. Preference order becomes `pc see`/`pc tree` (names + coordinates) → `pc a11y-click` → `pc win` → `pc click-text`/`pc find` → coordinates read off a screenshot. Replace every `pc wait N` example with `pc wait-for`; keep the `--scale 0.5` rule for real screenshots; say that `ui:` reads document text exactly where OCR misses lines (QA D4). Keep the skill under 90 lines.
5. **`pc selftest` addition** (stay under 25 s total): after opening the calculator, `pc wait-for --focus Calculator --timeout 10`; `pc see | grep -q 'button "7"'`; `pc tree gnome-calculator --find 7` returns two positive integers; compute `7+8` by `pc click` on those coordinates plus `pc a11y-click` and read `15` via the clipboard; after `killall`, `pc wait-for --gone Calculator --timeout 5`. Report each as an `OK`/`FAIL` line like the existing ones.
6. **KB:** in `~/agents/KB/quirks.md` and the README replace the "GTK4 reports 0,0" note with the WINDOW-coordinate fact and the `GetFrameBounds` breakage; add `pc see`/`pc wait-for` to the README command list.

## Success check
```bash
pc open org.gnome.Calculator
time pc wait-for --focus Calculator --timeout 10          # ok after < 4 s, exit 0
time pc see | tee /tmp/t28-see.txt >/dev/null              # real < 1.0 s
head -3 /tmp/t28-see.txt; wc -c /tmp/t28-see.txt           # focus:/windows:/ui: … ; <= 4000 bytes
grep -c 'button "' /tmp/t28-see.txt                        # >= 20
pc tree gnome-calculator --find 7                          # "X Y" with X > 0 and Y > 0
pc click $(pc tree gnome-calculator --find 7) && pc a11y-click "+" && pc click $(pc tree gnome-calculator --find 8) && pc a11y-click "=" && sleep 0.5 && pc key ctrl+c && sleep 0.3 && pc clip get   # 15
pc win move Calculator 200 150 && sleep 0.5 && pc tree gnome-calculator --find 7   # coordinates moved by the same delta (non-maximised check)
pc notify "t28-check" && sleep 1 && pc see | grep -c t28-check     # >= 1
killall gnome-calculator; time pc wait-for --gone Calculator --timeout 5   # ok, real < 2 s
pc wait-for --window "no-such-zzz" --timeout 2; echo rc=$?          # rc=1 after ~2 s
pc see | head -1                                                     # focus: none  (or the owner's window if one is open)
time pc selftest                                                     # PASS, real < 25 s
grep -c "pc see" ~/.claude/skills/desktop/SKILL.md ~/agents/README-pc-control.md   # >= 2 each
ls /tmp/*.png 2>/dev/null | wc -l                                    # 0 new files from this ticket
```

## Rollback
Restore `~/agents/bin/{a11y_tree.py,pc-selftest}`, `~/.claude/skills/desktop/SKILL.md`, `~/agents/README-pc-control.md` and `~/agents/KB/quirks.md` from the `baseline.sh` tarball taken at the start; delete `pc-see` and `pc-wait-for`.
