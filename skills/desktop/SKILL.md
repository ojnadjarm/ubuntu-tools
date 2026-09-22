---
name: desktop
description: Drive this machine's physical GNOME desktop with the `pc` CLI - screenshots, pointer, keyboard, clipboard, launching apps. Use when a task needs the real screen (a native app, the owner's browser profile, a dialog, "look at my screen", "click that") rather than a headless browser. Not for web scraping or web app testing - use the Playwright MCP for those.
---

# Desktop control (`pc`)

Ubuntu 26.04, GNOME 50, Wayland, 1366x768. `pc` lives in `~/agents/bin` (on PATH); `-h` prints any usage.

## Rule 0: text before pixels
Before driving any GUI, look for the CLI/D-Bus route (`gsettings`, `gdbus`, `gio`, `wpctl`, `playerctl`, `nmcli`,
the app's own CLI) and use the GUI only for what has no such route.

## The loop: `pc see` → act → `pc wait-for … --see`
1. `pc see` — focused window, window list, interactive UI tree with screen coordinates, notifications, clipboard.
2. Act (`pc a11y-click`, `pc click`, `pc type`, `pc key`, …).
3. `pc wait-for --text "Save" --see` (or `--window`/`--focus`/`--gone`) — blocks until the UI changed, then prints
   the digest. Never assume an action landed — always read back.

## What a look costs
| look | time | what you pay |
|---|---|---|
| `pc see` | ~1 s | <=4 KB of text, greppable and exact — the default |
| `pc shot --scale 0.5` | ~1 s | + a Read of ~350 tokens, not greppable |
| `pc shot --diff` | ~1.5 s | one line: `unchanged` / `changed bbox=X,Y,W,H` (`--changed-only` also writes a crop) |
| `pc find` | ~2 s | a screenshot + 1.2 s OCR, fuzzy — last resort |

**One screenshot per task is normal; one per step is a smell.** Reach for `pc shot` only when `ui:` reports no tree,
when rendering or layout itself is the question, or when the tree gives no coordinates.

## Subcommands
```
pc shot [out] [--scale F] [--region X,Y,W,H] [--diff [PREV]] [--changed-only] [--quiet]   prints "path WxH NKB"
pc click X Y [left|right|middle] [--double]        absolute move + click
pc move X Y | pc drag X1 Y1 X2 Y2 | pc scroll up|down [N] [--at X Y]   pointer
pc win list|focus|move|resize|close|minimize|maximize|wait   window management (see below)
pc type [--force] "text"                           layout-independent typing ("\n"=Enter, "\t"=Tab)
pc key [--force] ctrl+l | Return | shift+Print     key chords
pc clip get | pc clip set "text"                   clipboard
pc open <url|file|app.desktop>                     launch, returns immediately
pc notify "msg" [title]                            on-screen notification
pc see [SEL] [--json] [--max-bytes N]              text digest of the screen — start here
pc wait-for --window|--focus|--text|--gone SUB [--timeout S] [--see]   block until the UI changes
pc wait S [shot args]                              sleep, then screenshot
pc find "text" [--all] [--region X,Y,W,H] [--json]   OCR the screen; prints centre X Y (exit 1 if absent)
pc click-text "text" [--index N] [--region ...]    find + click; prints where it clicked
pc mode [agent|human|status]                       desktop profile (default: status)
pc spotify status|play|pause|toggle|next|prev|vol N|seek S|open URI|output SINK|search Q|library
pc status [--brief|--json|--check]   machine health      pc selftest   PASS/FAIL end-to-end (~20 s)
```

## Spotify
**Never screenshot Spotify** — it is Electron with no AT-SPI tree; every control goes through `pc spotify`
(MPRIS + PipeWire): `status [--json]`, `play|pause|toggle|next|prev`, `vol 0-100`, `seek <s|+s|-s>`,
`open <uri|url>`, `output earbuds|speakers|tv|<sink>`, `search <q>`, `library`. `search`, `library` and
starting a specific URI need the Web API — without `~/agents/secrets/spotify.env` they exit 2 with the setup steps.

## Rules
- **Screenshots.** Always `--scale 0.5` (halves the tokens; multiply what you read by 2); `--region X,Y,W,H` is
  full-resolution. `--diff` compares with the previous capture to the same path (`<out>.prev.png`, always the full
  frame; `--changed-only` writes the crop to `<out>.crop.png`), masking `--ignore X,Y,W,H` (default the top bar).
- **Focus before typing.** `pc win focus <sel>` raises the window *and clicks inside it*: a window reported focused
  on map still drops keystrokes until a real click. `pc type`/`pc key` exit 2 when focus is wrong (`--force` bypasses).
- **Modal dialogs.** A GTK4 "Save Changes?" prompt is *not* a window, so `pc win list` never shows it. `pc see`
  prints a `modal:` line with its buttons and narrows `ui:` to the dialog; `pc type`/`pc key` exit 2 while one is
  up. Answer it by name: `pc a11y-click "Discard"`.
- **Agent mode** (`pc mode`, T28c): animations are off, so windows appear at once — always wait on the condition
  (`pc wait-for --focus Calculator`), never on the clock; there is one workspace, so every `pc win list` row is on
  screen; `pc mode human` hands the desktop back to the owner (stock GNOME) and `pc mode agent` takes it back.
- **Typing into an editor:** `pc open <scratch file>`, never bare `gnome-text-editor` — it restores the owner's
  tabs and your `pc type` lands in their buffer.
- **`killall <name>`, never `pkill -f`** (it kills your session). **Never touch the tmux session `claude`**; never reboot unasked.
- **OCR is the last resort.** `pc find "x" --all --json` lists every match; click one with `pc click-text "x"
  --index N`. Matching is fuzzy, so read document text from `pc see` (`ui:`), not `pc find`.
- **`warn: <app> not answering AT-SPI`** in `pc see` means that application was dropped from the tree because it
  stopped replying on the a11y bus; everything else in the digest is complete.
- If nothing responds: `pc status --check`, `lockcheck.sh`; gotchas in `~/agents/README-pc-control.md`.

## Windows (T08, `pc win`)
```
pc win list [--json] | focused | focus <sel> [--no-click] | close|minimize|maximize <sel>
pc win move <sel> X Y | resize <sel> W H | wait "<title-sub>" [secs] | verify
```
- `<sel>` is a window id or a case-insensitive substring of the title or `wm_class`; the first match wins.
- Backed by the GNOME extension `window-calls@domandoman.xyz` (`wmctrl`/`xdotool` see nothing on Wayland);
  `resize` keeps the position, move/resize are clamped to the work area.

## Semantic UI tree (T10, AT-SPI)
```
pc tree [app-sub] [--depth N] [--json] [--max N] [--interactive] [--find "name" [--role R]]
pc a11y-click "name" [--role R] [--app SUB]        click an element by its accessible name
```
- **Prefer names over pixels.** Order of preference: `pc see`/`pc tree` (names *and* coordinates) → `pc a11y-click`
  → `pc win` → `pc click-text`/`pc find` → coordinates off a screenshot. Fall back only when a level finds nothing.
- `pc tree` takes the **AT-SPI application name**, not the `pc win` selector: `gnome-text-editor`, not
  `org.gnome.TextEditor` (`pc tree | grep ^application` lists them); prefer `--max` over `--depth`.
- GTK4 and Chrome report window-relative extents, so `pc tree` adds the window origin and prints **real screen
  coordinates**; `pc tree --find "7"` gives an `X Y` for `pc click`. `pc a11y-click` falls back to the AT-SPI action.
- Roles are AT-SPI names: `button` (alias "push button"), `toggle button`, `label`, `text`, `frame`; `text`/`entry`
  and document nodes print their content (first 120 chars), so read document text there, not with OCR. Chrome gets
  `--force-renderer-accessibility` from its desktop-file override, so `pc open <url>` yields a real tree.
