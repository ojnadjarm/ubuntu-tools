# ailearning index: one bookmark page with every built unit's newest Play link — RETIRED 2026-10-07 (T271)

**Retired.** Superseded by the one test site https://<tailnet>:8472/ailearning/ (`?review` lists every built sheet; guide `local-sites`).
`~/drop/units/` and every `~/drop/tNNN/` lesson build moved to `~/.local/state/drop-archive/2026-10-07/`. Restore the CLI: column 3 of
`~/agents/backups/retired/2026-10-07/MANIFEST.tsv`. History below.

Ticket: T247 · Last verified: 2026-10-05 by `ailearning-index` (14 units, 15/15 links 200) and headless shots at 400/768/1366/1920/2560

## When to use
After any ailearning unit drop, or when the owner asks "where is the link for plate N". Not for publishing the site itself (`.local/drop.sh` / `sites`).

## The path we took
- Existed: bare `~/drop/tNNN/` folders, `/drop-link` (one checked link), `content/homepage.json` + `units/*/unit.json` (title, kind, minutes, status, chapters), `KB/history.md` (done lines).
- Chosen: stdlib Python CLI `~/agents/bin/ailearning-index` renders a static page `~/drop/units/index.html` in the site tokens (title.css/sheet.css); fonts + favicon hard-linked from `public/`.
- Newest build of unit NN = highest `~/drop/tNNN/uNN/u/<slug>/` (the drop named after that unit); no own drop + status drawn → published site `:8472/ailearning/u/<slug>/` (+ "newest build" link to the latest drop that contains it).
- Note per card = the newest history.md line for that ticket with "done"/"built", test numbers and "Open:" stripped. Stamps come from file mtimes, so reruns are idempotent (`unchanged`).

## Exact commands
```bash
ailearning-index            # regenerate; prints URL, units, links 200 n/n; exit 1 if a link is not 200
ailearning-index --check    # write nothing; list units with a dead link or with unit source but no drop; exit 1 on any
ailearning-index --dry-run  # page to stdout
```
Bookmark: https://<tailnet-fqdn>:8470/units/

## Pitfalls (measured)
- First placed at `~/drop/ailearning/index.html`; the repo's `.local/drop.sh` does `rm -rf ~/drop/ailearning`, so the page moved to its own folder `~/drop/units/` (T247 follow-up). `~/drop/ailearning/` stays the old site drop only (its index.html restored from `~/agents/research/2026-10-05/T247/backup/`).
- A long unbroken URL in the footer made 400 px scroll to 561 px; `overflow-wrap:anywhere` fixed it.
- A CSS grid with auto-fill left 2 empty cells in the last row at 1366/1920 (14 cards, 4 columns); flex-wrap with grow fills the row.
- Notes are only as good as the history.md line; a ticket without a "done"/"built" line gets an empty note.

## Links
- Code: `~/agents/bin/ailearning-index`
- Tests: `ailearning-index --check`; shots script pattern in `~/agents/research/2026-10-05/T247/`
- Design / results: `~/agents/research/2026-10-05/T247/ARCHITECTURE.md`, `shot-*.png`
