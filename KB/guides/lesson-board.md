# Track every ailearning lesson's stage (not started, in development, in review, approved) on the lesson board

Ticket: T272 · Last verified: 2026-10-07 by node tests 441/441 (board 5/5), CLI fixture test PASS, headless board check (43 = 29+0+13+1, 15/15 links 200, 5 widths 0 overflow)

## When to use
- "Which lessons are done / approved / in review?", "U05 approved", a lesson ticket starts or publishes: `lesson-board`.
- Not the release switch: `content/homepage.json` `status: drawn` still decides what Pages links (guide learning-site-homepage).

## The path we took
- Survey: homepage.json status = release only; unit.json/cues.json = build facts; history.md = trail; no source held the work stage.
- One data file `content/board.json` (`{units: {U05: {state, since, note?}}}`, missing = not-started, one line per unit) + pure model
  `src/site/board/model.mjs` + facts from unit.json/cues.json + renderer; `board/index.html` is a Vite input only in `REVIEW=toggle` builds.
- Homepage header: `Board` link with class `rv-on` (review mode only). Architecture: `~/agents/research/2026-10-07/T272/ARCHITECTURE.md`.
- Initial states (2026-10-07): U01 approved (owner), U02–U14 review (all built and complete, owner review pending), U15–U43 not started.

## Exact commands
```bash
lesson-board show                      # "1 of 43 approved · Not started 29 · ..." (+ --json)
lesson-board set U05 dev               # first ticket of a lesson starts
lesson-board set U05 review            # a build is published (sites publish ailearning)
lesson-board set U05 approved --owner  # only after the owner's word; without --owner exits 3
sites publish ailearning               # the board reads board.json at build time: publish after a change
# board: https://<tailnet-fqdn>:8472/ailearning/board/
~/.claude/skills/make-lesson/tests/lesson-board.test.sh   # CLI on a fixture site
```

## Pitfalls (measured)
- `new-lesson` adds pages with the regex `input: \{[^}]*?\} \}`: a `{ board: ... }` inside the input object broke it; the board entry is a spread `...board` of a const.
- "Chapters done" counts up to the last narrated chapter whose clips are all in cues.json: play chapters (Your turn, Workbench, Tuning) have no clips.
- `auto-fit` columns gave 3+1 at 1366 and 5 tracks at 1920; fixed breakpoints 1/2/4 columns at 0/640/1200 px.
- Days in stage are computed in the browser from `data-since`, so they stay true between publishes.
- Node is not on a bare agent PATH: `export PATH=~/.nvm/versions/node/v24.20.0/bin:$PATH`.

## Links
- Code: `~/projects/personal/ailearning/src/site/board/`, `content/board.json`, `board/index.html`; CLI `~/.claude/skills/make-lesson/scripts/lesson-board.mjs` (symlink `~/agents/bin/lesson-board`)
- Tests: `tests/unit/board.test.mjs` (`npm run test:changed -- content/board.json`), `~/.claude/skills/make-lesson/tests/lesson-board.test.sh`
- Design / results: `~/agents/research/2026-10-07/T272/` (ARCHITECTURE.md, verify.cjs, shots/)
