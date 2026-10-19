# Playthrough gate: every ailearning exercise names its control and can be completed

Ticket: T400, T406 (speed) · Last verified: 2026-10-19 by `npm run playthrough` over U01–U14 at 1366x768 and `node --import ./tests/lib/register.mjs --test tests/unit/playthrough.test.mjs`

## When to use
Building, fixing or reviewing an ailearning lesson's Workbench / Tuning / Practice cases, or the owner says "nothing happens" / "what do I do".
Not for guided steps (Your turn) or the watch: use `npm run declutter` (guide lesson-declutter) for what is drawn.

## The path we took
Reuses the declutter walker (`tools/declutter/walk.mjs`: onPage, beatOrder, cases, settle, limiter, `--mute-audio` args); no new framework.

| Module (`~/projects/personal/ailearning/`) | Does |
|---|---|
| `tools/playthrough.mjs` | CLI: Vite dev server, headless Chromium, 8 pages at once, `out/playthrough/<slug>.md` + `.json`, exit 1 on any fault |
| `tools/playthrough/play.mjs` | Per case (4 to a page): read the shown instruction (`[data-k=ask]`) and the visible control names (plate buttons; each enabled hand's kind word, its state key, labels within 40 px of its grab area, a balloon → its part's name and term; every plate label for tap cases); then play: (1) the worked answer (`answer ?? show`) as the learner's own moves with the case open, (2) else the hand setting its verdict or press-in passes (grid search), (3) else tap each labelled spot, skipping misses; completed = bench event `step` phase `done` within 8 s for the worked answer and its seat, 2 s for search/turns/taps (a judged miss ends a wait at once), the tap path capped at 30 s a case; goal easing runs 4x (`EASE`); each record carries `ms` |
| `tools/playthrough/rules.mjs` | Pure: `named(prompt, names)` (each name word is a prompt word or, from 3 letters, its prefix; numbers and stop words never name), faults `unnamed` / `no-prompt` / `never-completes` |

## Exact commands
```bash
cd ~/projects/personal/ailearning
npm run playthrough -- 01            # one unit (~2 min for U01's 64 cases)
npm run playthrough                  # every built unit (491 s idle, T406), tables + fails.txt in out/playthrough/
node --import ./tests/lib/register.mjs --test tests/unit/playthrough.test.mjs
```

## Pitfalls (measured)
- Restoring the plate a give-up leaves does not complete dynamic cases: U05/U06/U07 went 41/41, 42/42, 43/43 "never" until the worked answer was played live as moves (U07 43 → 18).
- `show` often only uncovers the working (U01 e2: pencils never move), so the grid search fallback is needed (U01 19 → 0 never).
- Contrast pairs have no hands and complete on taps; the tap path took U07 18 → 6. Tuning levels whose answer sweeps and steps (U07 L1–L5) still read "never": check by hand before calling it a lesson bug.
- Kind words come from class names (DetentHand → dial/knob); a SlotHand part with no balloon (U01 k4 valve) reads `unnamed` even when the prompt says "valve".
- Too slow for `ci:core` (6 min cap); a separate script, run report-only by `ailearning-ci-daily` nightly → `~/agents/log/ailearning-playthrough/fails.txt` (never turns CI red).
- Speed (T406, 495 cases, 12 pages): 1281 s → 491 s. The time was not the 8 s waits (16 never cases) but the settles and the worked answer's landings waiting on real-time goal easing (U01 129 s → 48 s with `EASE` 4) and tap passes drawing 10 frames per untaken spot (U12 e1 130 s a case; untaken idle taps now draw 1 frame, path capped at 30 s; every completing tap case needs ≤ 10 s).
- Faster easing turned U07 tune L4 from never to completes (its answer now lands within `LAND_MS`): a gate false-fail, load-sensitive before.

## Links
- Code: `tools/playthrough.mjs`, `tools/playthrough/*`, `tools/test-changed.mjs` (maps `tools/playthrough/` to its test)
- Tests: `tests/unit/playthrough.test.mjs`
- Design / results: `~/agent-work/research/2026-10-18/night/T400/` (ARCH.md, FAILS.md)
