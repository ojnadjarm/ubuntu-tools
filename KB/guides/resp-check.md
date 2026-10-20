# Check a web page is responsive at 400/768/1366/1920/2560: no h-scroll, symmetric margins, one small contact sheet (`resp-check`)

Ticket: T504 · Last verified: 2026-10-20 by T846 read-only audit (`--help`, paths, code); before: 2026-10-19 by `bash ~/agents/bin/tests/resp-check.test.sh` (12/12, 19 s)

## When to use
Every web ticket's "fluid + responsive at 400/768/1366/1920/2560" proof. Replaces playwright MCP evaluate + 5 full PNG reads
(278–664 KB each) with 5 text rows and, if a look is needed, one JPEG sheet ≤ 200 KB. Not for overlap/flicker checks inside a
lesson (guide lesson-visualcheck) or pixel diffs.

## The path we took
Survey: cached chromium-headless-shell 1243/1247 under ~/.cache/ms-playwright, `google-chrome --headless` (155, no page JS
hook from the CLI), the playwright MCP's node runtime (playwright-core 1.64, expects headless shell 1247). Chosen: the MCP's
playwright-core + its headless shell 1247: already installed, matching revision, page JS for measuring; no npm install.
Architecture: one bash file `bin/resp-check` (args, usage, file → file:// URL) that execs node with a heredoc module:
`loadPlaywright()` (global node_modules beside `process.execPath`, or `RESP_CHECK_PW`) → per width a fresh page at a device
height (400×860, 768×1024, 1366×768, 1920×1080, 2560×1440) → `measure()` in the page → one row → optional `contactSheet()`
(the same browser lays the 5 shots out in a flex row and screenshots it as JPEG, lowering quality 80→30, then column width
300→120, until ≤ 200 KB).
Content margins = union of: the nearest block box of every non-empty text node, media elements (img/svg/video/canvas/iframe/
form controls), and boxes that paint (background or border). FAIL = `scrollW > vw` or `|left − right| > tol` (default 2 px).

## Exact commands
```bash
resp-check http://127.0.0.1:8080/                      # 5 rows + PASS|FAIL n/5; exit 0 all pass, 1 any FAIL, 2 usage/load error
resp-check ./site/index.html --sheet /tmp/sheet.jpg    # local file works; sheet = 5 columns, ≤ 200 KB
resp-check <url> --widths 400,1920 --tol 4             # subset of widths, looser margin tolerance
```

## Pitfalls (measured)
- Ragged text is not a margin: text nodes count by their block box, so a centred 900 px column with short lines still reads 16/16 px
  at 400 and 233/233 at 1366.
- A 1500 px fixed page centred with `margin:0 auto` fails only at 400/768/1366 (scrollW 1500) and passes at 1920/2560 (210/210, 530/530).
- Random-noise pages are the worst case for the sheet: 186 686 bytes after the quality/width ladder; ordinary pages are ~24 KB.
- Off-canvas content wholly left of 0 or right of scrollW is ignored; partially clipped content counts from 0.
- 5 widths take ~3.5 s on a fixture page (4.9 s with `--sheet`); each width reloads the page, so JS that lays out on load is honest.
- New CLI in ~/agents/bin: run `~/agents/install.sh --links` or live sessions get "command not found".

## Links
- Code: ~/agents/bin/resp-check
- Tests: `bash ~/agents/bin/tests/resp-check.test.sh` (fixtures: fluid, 1500 px fixed, left-aligned, noise; file:// only)
- Brief: ~/agent-work/briefs/T504-resp-check.md
