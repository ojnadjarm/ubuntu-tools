# Lesson visual self-check: no duplicate tooltips, no overlaps, no flicker or jitter while dragging (`npm run visualcheck`)

Ticket: T405 · Last verified: 2026-10-19 by `node --import ./tests/lib/register.mjs --test tests/unit/visualcheck.test.mjs` (3/3) and U04 runs; baseline in progress (see Links)

## When to use
Before a sheet goes to the owner's QA, or when he says "flicker", "duplicated tooltips", "messy", "labels jump". Not for step counts or
leftovers at rest (guide lesson-declutter) or exercises that never complete (guide playthrough-gate).

## The path we took
Survey: declutter poses steps at rest and playthrough plays solutions; neither drags frame by frame. Chosen: reuse the declutter walker
(onPage, beatOrder, cases, settle, rest, limiter, browserArgs with `--mute-audio`) and its probe + `things()` classifier; add a drag layer.

| Module (`~/projects/personal/ailearning/`) | Does |
|---|---|
| `tools/visualcheck.mjs` | CLI: Vite dev server, headless Chromium, 8 pages; `out/visualcheck/<slug>.md/.json` written per unit as it finishes; exit 1 on a fault |
| `tools/visual/drag.mjs` | Per Workbench/Tuning/Practice case at real speed: open + snap, main object = first enabled hand (dial: arc round its centre, 180° then 360° back; pencil: along its track; carried part: a line), 2 legs × 24 mouse steps, in-page rAF sampler (≤ 4 frames per step), release, rest, snap; `--shots` keeps a PNG per step |
| `tools/visual/rules.mjs` | Pure: `duplicates` (labelled thing or DOM tooltip twice at once, any frame), `overlaps` (open + released pose, labels vs labels/plate controls/chrome controls), `motion` (flicker, jitter per mesh track), `THRESH`; declutter `EXCEPTIONS` honoured |

Thresholds (`THRESH`): flicker = one label blinks ≥ 2× in a drag (presence gap or flash past its first hide, mid-word re-type, alpha dip ≥ 0.4
and back); jitter ≥ 2 back-steps ≥ 2 px or jumps ≥ 40 px between frames (same text, same leg); duplicates 0; overlaps 0.

## Exact commands
```bash
cd ~/projects/personal/ailearning
npm run visualcheck -- 04                                  # one unit
npm run visualcheck -- 04 --case bench/e3.1 --shots ~/drop/<ticket>   # one case with PNG frames of its faults
npm run visualcheck                                        # every built unit (one at a time on a loaded machine)
node --import ./tests/lib/register.mjs --test tests/unit/visualcheck.test.mjs
```

## Pitfalls (measured)
- First full run died at 37 min: node heap OOM (4 GB) — under load (load 10–13) a mouse step took long and the sampler kept every frame. Capped at 4 frames per step (≈ 200 frames a case) and reports are now written per unit.
- A value losing a digit ("6.5" → "6") read as a re-type (U04 e3.1: 5 false flicker faults); a re-type now needs the cut mid-word.
- Frame counts vary 145–343 per case between runs of the same case (parallel pages): thresholds count events, not frames.
- Labels the kit hides while a part moves (U04 Fig. 6 balloons, `plate/rest.ts`) hide once and return: 1 blink, under the threshold by design.
- Overlaps at rest are also declutter faults; this check adds the released pose and chrome controls over labels.

## Links
- Code: `tools/visualcheck.mjs`, `tools/visual/*`; tests `tests/unit/visualcheck.test.mjs`, fixtures `tests/unit/fixtures/visual/*.json`
- Design / results: `~/agent-work/research/2026-10-18/night/T405/` (ARCH.md, FAILS.md, tables/), frames `~/drop/T405/`
