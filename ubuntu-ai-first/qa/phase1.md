# Phase 1 QA report — 2026-09-05

Independent verification of T07–T10 (desktop control v2) by the QA agent. T11 skipped by owner
decision, so it is out of scope. Every command below was re-run by QA; tests went beyond the
tickets' own Success checks (fault injection, geometry read-back against pixels, robustness under
concurrent window motion). Screen 1366x768, lid closed, on AC, desktop unlocked, QA the only agent.

## Verdict

| Ticket | Success check | Goal met | Verdict |
|---|---|---|---|
| T07 pc-cli-input | PASS (except the Chrome step, D5) | PASS | **PASS with defects** (D2, D3, D6) |
| T08 wayland-window-management | PASS | partial | **PASS with defect** (D1 — HIGH) |
| T09 screen-text-ocr | PASS | partial | **PASS with defects** (D3, D4) |
| T10 a11y-tree | PASS (with the documented `push button` caveat) | PASS | **PASS with defect** (D7) |
| T11 owner-view-rdp | — | — | skipped by owner |

## Evidence

### T07 — PASS with defects
- `pc selftest` → **PASS three times** (start, middle, end of the QA run), `real 0m10.9s` each,
  well under the ticket's 20 s. All six lines OK: `type+key+clip: 7+8 = 15`, `shot`, `win`, `find`,
  `pointer: move`, `pointer: scroll`. Exit 0. It cleans up its own calculator and text editor.
- **Every subcommand prints usage on `-h` and exits 0**: `shot click move drag scroll type key clip
  open notify wait find click-text tree a11y-click win status selftest` — 18/18, each first line
  starts `usage: pc <sub> …`.
- Unknown subcommand: `pc bogus-sub` → `pc: unknown command 'bogus-sub' (try: pc help)`, **exit 127**.
  `pc help` → exit 0, lists all 18.
- `pc shot /tmp/a.png --scale 0.5` → `683 x 384` PNG (half of 1366x768). `--region X,Y,W,H` crops in
  full-resolution pixels (verified against window geometry three times).
- `pc clip set "qa-clip-check-42"` → `pc clip get` returns it. `pc notify`, `pc wait 1 <shot args>`,
  `pc drag`, `pc scroll` all exit 0.
- Failure paths: `pc find` no args → exit 2 + usage; `pc scroll sideways` → exit 2; `pc clip bogus`
  → exit 2. (`pc key` and `pc win` with no args print usage and exit **0** — see D6.)
- `pc type` refuses with **exit 2** and a clear message when no window is focused (verified after
  minimising the only window: `pc win focused` → exit 1, `pc type "x"` → exit 2). `--force` → exit 0.
- Wrappers `screenshot.sh`/`click.sh`/`type.sh`/`key.sh` are 3-line `exec … pc <sub>` shims and work
  (`./screenshot.sh /tmp/qa-wrap.png` produced a 144 KB PNG). Note `type.sh` now inherits the focus
  guard, so it is not strictly "no behaviour change" as T07 step 2 asked — acceptable and safer.
- `~/.claude/skills/desktop/SKILL.md` exists (78 lines), `~/agents/README-pc-control.md` updated.
- `bash -n` clean on `pc` and all 17 `pc-*` shell scripts; `python3 -m py_compile` clean on `pc-win`,
  `a11y_tree.py`, `ocr_find.py`, `portal_shot.py`, `rd_type.py`.
- **`pc open` children survive the calling shell** — the T10 note is NOT reproducible:
  `bash -c 'pc open gnome-calculator; exit 0'` → calculator alive 4 s later and listed by `pc win list`;
  `setsid bash -c 'pc open gnome-text-editor; kill -9 $$'` → editor survived too. `pc-open` uses
  `setsid`, which is why. The note can be dropped from the docs.

### T08 — PASS with defect D1 (HIGH)
- Extension: `gnome-extensions info window-calls@domandoman.xyz` → `Version: 21`, `Enabled: Yes`,
  `State: ACTIVE`, path `~/.local/share/gnome-shell/extensions/…`. `metadata.json` `shell-version`
  `['45'…'50']` vs `GNOME Shell 50.1` — compatible.
  **It will come back at the next login**: `dconf read /org/gnome/shell/enabled-extensions` →
  `['window-calls@domandoman.xyz']` (user db, not a live-only state) and
  `org.gnome.shell disable-user-extensions` → `false`.
- **Geometry read-back verified against pixels**, not just against the API: `pc win move` to
  `100,100` / `400,300` / `0,0` / `1300,700` → `pc win list` reported `+100+100`, `+400+300`, `+0+0`
  and `+1291+693` (clamped to the work area — correct). `pc win resize 300 700` → `360x700` (width
  clamped to the app's minimum). A screenshot then showed the calculator at exactly 200,100 sized
  360x700, matching the table.
- `maximize` → `1299x736+67+32` (the work area); `minimize` → `"minimized": true` in `--json`;
  `focus` restores it.
- Failure paths all non-zero: `pc win focus|move|close "no-such-window-zzz"` → `pc win: no window
  matching …`, exit 1; `pc win move 999999 10 10` → exit 1; `pc win wait "no-such-window-qq" 3` →
  exit 1 in `real 0m3.2s` (honours the timeout).
- Robustness: while a background loop moved a window every 200 ms for 8 s, `pc find`, `pc tree`,
  `pc win list` and `pc shot` all returned exit 0 with sane output — no crash, no D-Bus error.
- `pc win close` on a text editor with unsaved changes correctly raised the GTK "Save Changes?"
  dialog instead of losing data, and the window survived until the dialog was answered.
- **Defect D1**: `pc win focus` / `pc win wait` report a window focused (`*` in `list`,
  `pc win focused` prints its id) while keystrokes are silently dropped. Reproduced twice, see below.

### T09 — PASS with defects
- Ticket Success check reproduced end to end: `pc find "9"` → `434 412`; then
  `pc click-text "9" "+" "1" "="` (each printing `clicked '<x>' at X Y`, exit 0) → screenshot read by
  QA shows `9+1 = 10` in the calculator. `pc find "nothing-on-screen-xyz-qq"` → **exit 1 in
  `real 0m1.374s`** (ticket allows 4 s).
- `pc find` is in `pc selftest` (`find: OCR located "7" at …`) as step 3 required.
- OCR is genuinely useful on real UI: it located `DuckDuckGo` (557 520) and `Qwant` (536 627) inside a
  Chrome modal, and `Open`, `bravo`, `one bravo`, `QA phase` in gnome-text-editor.
- **But it misses plainly legible text** — see D4. With two lines typed in Text Editor at default
  zoom, `pc find "QA phase one alpha"` → exit 1, `pc find "alpha"` → exit 1, `pc find "phase one
  alpha"` → exit 1, while `bravo` and `one bravo` on the next line matched. Every match returned came
  from line 2; line 1 was never seen.

### T10 — PASS with defect D7
- `gsettings get org.gnome.desktop.interface toolkit-accessibility` → `true`.
- Ticket Success check: `pc tree gnome-calculator --max 300 | grep -c "push button"` → **0**, but
  `grep -c button` → **36** — the role rename the implementer already documented in the README and
  quirks.md, so the check is wrong, not the code.
- `pc a11y-click "7" "+" "2" "="` → all exit 0; screenshot read by QA shows `7+2 = 9`. Works with no
  pointer and no focus, exactly as designed for GTK4's `0,0` extents.
- **Best result of the whole phase**: after `pc win close` raised the unsaved-changes dialog,
  `pc a11y-click "Discard"` (exit 0) dismissed it and closed the window. `ls ~/Documents` empty and
  `md5sum ~/moodle-envs/install-5.2.log` unchanged (`0e949de2…` before and after) — nothing was saved.
- `pc tree --find "Open"` correctly refuses with `no screen coordinates (GTK4/Wayland); use
  \`pc a11y-click\``, exit 1. `pc a11y-click "no-such-element-zzz"` → `not found`, exit 1.
- Chrome exposes only two frames to AT-SPI (`pc tree "Google Chrome"` → `frame "Example Domain -
  Google Chrome"`, `frame ""`) because it was launched by `pc open` without
  `--force-renderer-accessibility` — documented in the SKILL, so a limitation, not a defect. It does
  mean a web page's DOM cannot be verified with `pc tree` after `pc open <url>`.

## Defects

**D1 — HIGH — T08 — `pc win focus` / `pc win wait` report focus that the app does not actually have; `pc type` then succeeds (exit 0) while every keystroke is discarded.**
- Repro (deterministic, 2/2 trials, from a clean desktop):
  ```
  pc open gnome-text-editor
  id=$(pc win wait "Text Editor" 15)   # exit 0, prints an id
  pc win list                          # "* … Text Editor"  → reported focused
  pc win focused                       # prints the same id
  pc type "TRIALONE"                   # exit 0
  pc key F10                           # exit 0
  ```
  Nothing is typed, the menu does not open, and the tab shows no modified dot. `pc win focus <id>`
  afterwards does **not** repair it. A single `pc click X Y` inside the window makes both `pc type`
  and `pc key F10` work immediately (verified by screenshot: the primary menu opened).
- Not universal: the same sequence on gnome-calculator works, and `pc win focus Calculator` followed
  by `pc type "5"` did land the 5 in the calculator. It is windows that do not take keyboard focus
  themselves on map (here, gnome-text-editor restoring its session) that stay input-dead.
- Impact: this defeats T08 step 3's guard and PLAN §6's "wrong-window input" mitigation. The guard
  only proves the extension's `focus` flag, not Wayland keyboard focus, so an agent that follows the
  documented "focus before typing, verify with `pc win list`" recipe gets a false green and silently
  types nothing — or, worse, into whatever really holds focus. QA hit exactly this: a first attempt
  typed nothing, and a later click-then-type inserted `QAZZTEST` into the owner's real
  `~/moodle-envs/install-5.2.log` buffer (undone with `ctrl+z`; the file on disk was never modified —
  md5 verified before and after).
- Suggested fix: make focus verifiable rather than asserted. Cheapest: after `Activate`, have
  `pc win focus`/`pc win wait` send a no-op pointer click at the centre of the window's geometry
  (`--no-click` to opt out), which is what actually grants Wayland keyboard focus; and/or add
  `pc win focus --verify` that types a harmless key and confirms via AT-SPI that the app's focused
  object changed. Until then the SKILL must say: after `pc win focus`, click inside the window before
  typing, and always verify the text landed.

**D2 — MEDIUM — T07 — `pc click` does not validate its coordinates: garbage and out-of-range values silently click at 0,0, which is GNOME's hot corner.**
- Repro: `pc click 5000 5000` → exit 0; `pc click -50 -50` → exit 0; **`pc click abc def` → exit 0**.
  A screenshot taken straight after showed the **Activities overview open** (the pointer had been
  driven into the top-left hot corner). QA had to `pc key Escape` to restore the desktop.
- Impact: a bad coordinate (a mis-parsed OCR result, an unset shell variable) does not fail loudly —
  it changes the desktop state and every subsequent click/type lands in the overview, not in the app.
- Suggested fix: in `pc-click`/`pc-move`/`pc-drag`/`pc scroll --at`, require integers and reject
  anything outside the screen bounds (read from `pc status`) with exit 2 — or clamp to `1..W-1`,
  `1..H-1` so 0,0 is never reachable by accident.

**D3 — MEDIUM — T09 — `pc find` leaks one screenshot PNG into `/tmp` on every call.**
- Repro: `b=$(ls /tmp/tmp.*.png|wc -l); pc find "7" >/dev/null; a=$(ls /tmp/tmp.*.png|wc -l)` →
  `before=46 after=47`. One QA session left **48 files, 13 MB**.
- Cause: `pc-find` line 18 sets `trap 'rm -f "$shot"' EXIT` and the script's last line is
  `exec python3 …/ocr_find.py …`. `exec` replaces the shell, so the EXIT trap never runs.
  `pc click-text` and `pc selftest` inherit the leak.
- Impact: unbounded `/tmp` growth from a subcommand agents are told to prefer; PLAN §6 lists disk-full
  as a tracked risk. Suggested fix: drop the `exec` (`python3 … "$@"; rc=$?; exit $rc`), or delete the
  temp inside `ocr_find.py`.

**D4 — MEDIUM — T09 — OCR misses clearly legible text; multi-word phrases are unreliable.**
- Repro: gnome-text-editor showing exactly two lines, `QA phase one alpha` / `QA phase one bravo`, at
  default zoom on the default dark theme:
  `pc find "QA phase one alpha"` → exit 1; `pc find "alpha"` → exit 1;
  `pc find "phase one alpha"` → exit 1; `pc find "bravo"` → **0** `655 339`;
  `pc find "one bravo"` → **0** `639 339`; `pc find "QA phase"` → **0** `561 341` (also on line 2).
  Line 1 is never returned by any query although a screenshot QA read shows it rendered identically
  to line 2.
- Impact: the goal "get exact pixel coordinates for visible text" holds for buttons and menu labels
  but not for document text, and there is no way for the caller to tell a true absence (exit 1) from
  a missed line (also exit 1).
- Suggested fix: raise the pre-OCR upscale or add a psm 4/psm 3 line pass for queries longer than one
  word, and document in the SKILL that `pc find` targets **UI labels**, not document content — read
  document text from a screenshot or the a11y tree instead.

**D5 — MEDIUM — T07 — `pc open <url>` cannot be verified on the owner's Chrome profile: a modal "Choose your search engine" blocks every window, and T07's Success check step 3 is therefore unproven.**
- Repro: `pc open https://example.com` → exit 0, a 4th `Example Domain` tab appears, but the window is
  covered by Chrome's mandatory search-engine chooser. `pc key Escape` does not dismiss it,
  `pc key ctrl+w` is ignored even after `pc win focus` and a click inside the window, and the dialog
  offers no Cancel — a choice must be made once, which is an owner preference QA will not set.
- The README already warns about first-run dialogs, but T07's report claims the check passed
  ("Chrome shows example.com"); what is actually on screen is this modal.
- Suggested fix: owner answers the dialog once (it is a per-profile, one-time EU prompt), then re-run
  the T07 step; or change the check to use a `--user-data-dir` throwaway profile with
  `--no-first-run --no-default-browser-check`, as the README already describes for flag-controlled
  launches.

**D6 — LOW — T07 — `pc shot` returns exit 0 and prints the path even when writing the file failed.**
- Repro: `pc shot /nonexistent-dir/x.png` → a Python `FileNotFoundError` traceback on stderr, then
  `/nonexistent-dir/x.png` on stdout, **exit 0**. An agent following the see-act-verify loop would
  Read a file that does not exist.
- Also LOW/consistency: `pc key` and `pc win` with no arguments print usage and exit **0**, while
  `pc find`, `pc scroll` and `pc clip` exit 2 for the same mistake.
- Suggested fix: `python3 - … <<'PY' … PY || { rm -f "$tmp"; exit 1; }` in `pc-shot`, and exit 2 from
  `pc-key`/`pc-win` when arguments are missing (keep exit 0 for an explicit `-h`).

**D7 — LOW — T10 — `pc tree <app>` prints nothing and exits 0 when the substring matches no AT-SPI application.**
- Repro: `pc tree "Text Editor"` → empty output, exit 0, with the editor open. The AT-SPI application
  name is `gnome-text-editor`; `pc tree gnome-text-editor` works. The SKILL's own example
  (`pc tree calculator`) works only because that app's a11y name is `gnome-calculator`.
- Note also that the a11y app name and the `pc win list` `wm_class` differ
  (`gnome-text-editor` vs `org.gnome.TextEditor`), so a selector that works for `pc win` does not
  work for `pc tree`.
- Suggested fix: exit 1 with `pc tree: no application matching '<sub>' (try: pc tree | grep ^application)`
  when the filter matches nothing, and mention the naming mismatch in the SKILL.

**D8 — LOW — docs — the "preference order" is stated twice, differently, and only in the skill.**
- `~/.claude/skills/desktop/SKILL.md` §"Semantic UI tree" says `pc win` → `pc tree` → `pc find` (OCR)
  → raw coordinates. Its §"Rules" says "**Prefer `pc click-text`** for anything with a visible label",
  which puts OCR *above* the tree for exactly the case (buttons, menu entries) the tree handles best
  and most cheaply. `~/agents/README-pc-control.md` states no order at all.
- What QA measured supports the T10 order with one correction: for GTK4 the tree is only usable
  through `pc a11y-click` (`pc tree --find` returns no coordinates by design), and OCR is the weakest
  link (D4). Suggested wording: `pc win` (geometry/focus) → `pc a11y-click` (named controls) →
  `pc click-text`/`pc find` (labels the tree does not expose) → coordinates from a screenshot; drop
  the contradicting line in §Rules and mirror the order into the README.
- Minor doc drift found while testing: SKILL says `pc selftest` takes ~6 s (measured 10.9 s three
  times) and that `pc win resize` "re-centres the window" (it does not — position was unchanged at
  `+1291+693` across two resizes); the README/quirks claim `killall gnome-calculator` misses the
  process and one must use `killall gnome-calculato` — the opposite is true here
  (`killall gnome-calculato` → "no process found"; `killall gnome-calculator` → exit 0, process gone);
  and the T10 note that `pc open` children die with the calling shell is wrong (see T07 evidence).

**D9 — INFO — leftovers.**
- `pc win list` prints popup/tooltip surfaces as `None  None` (a `156x32+638+508` row appeared while
  a tooltip was up) and shows no marker for a minimised window, whose geometry still reads as if
  visible (`--json` does carry `"minimized": true`). Cosmetic, but a selector substring match could
  resolve to one of these transient rows.
- `pc win list --json` reports `in_current_workspace: false` for a window on the current workspace.
- `~/agents/bin/{env.sh,ocr_find.py,portal_shot.py,rd_type.py}` are not executable (correct — they are
  sourced/interpreted), everything else in `~/agents/bin` is `+x` and syntax-clean.
- **46 debugging PNGs left in `/tmp` by the T09/T10 implementation agents** (`t09-v*.png`, `eq*.png`,
  `q_*.png`, `calc*.png`, …) plus `/tmp/pc-selftest.png`. QA removed only its own files and the 48
  leaked `tmp.*.png` from D3; the implementers' files are still there.
- A Chrome window with 3 `example.com` tabs and the search-engine modal was left open on the desktop
  by the T07 agent; QA closed it (`pc win close google-chrome`) at cleanup.
- Desktop left clean: `pc win list` empty, no calculator/text-editor/Chrome processes, no stray
  `pc-open` or `gtk-launch` processes, `pc selftest` PASS as the final action.

## Not testable / out of scope

1. **T11 owner-view-rdp** — skipped by owner decision; not evaluated.
2. **Extension across a real login** — persistence is proven only from configuration
   (`dconf read /org/gnome/shell/enabled-extensions`, `disable-user-extensions false`). Nothing has
   survived an actual logout; the extension was installed live via `InstallRemoteExtension`.
3. **`pc open <url>` end to end in Chrome** — blocked by the profile-level modal (D5); needs the owner
   to answer it once.
4. **`pc tree` on web content** — needs Chrome started with `--force-renderer-accessibility`, which
   `pc open` cannot pass; a separate `google-chrome` launch (or T12/T14) is required.
5. **Multi-monitor / lid-open geometry** — all window tests ran on the single 1366x768 internal panel
   with the lid closed; clamping behaviour on a second display is unverified.
6. **Concurrency between agents** — QA was the only agent on the desktop, as briefed. Two agents
   driving `pc` at once (shared pointer, shared focus, shared clipboard) is untested and has no
   locking; worth a ticket before Phase 3 puts several agents on timers.
