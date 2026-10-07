# Write a full narrated lesson: chapters, script with numbers checked by the sim, plate, callouts, numbered badges, framing (ailearning)

Ticket: T84 (U01 "The neuron", builds 2 and 3 of 3, fix pass) · Last verified: 2026-09-25 by `npm run ci` green in `~/projects/personal/ailearning`
(node tests incl. words vs numbers, framing and play; unit and whole-lesson e2e 0 faults, also on the drop link) and stills at 400–2560 px.

## When to use
Writing or growing the explanation of a learning unit on the explainer engine: script, narration, plate additions, callouts, numbered badges,
framing, stills. For the engine itself use `/explainer-engine`; for the look `/cutaway-style`; for audio `/kokoro-narration`. Exercises: `learning-exercises`.

## The path we took
1. **Design as data first.** The script is Python data (`T84/tools/script_src.py`): chapters → clips → sentences; each sentence carries the
   state it lands on (`set`), the tags and NOTE rows it shows, and neutral `asserts` of what the words claim. `build.py` runs every sentence
   through a Python mirror of the sim (`sim.py`) and fails on a mismatch; `md.py` renders `lesson-design.md`; three critics (correctness,
   learner, pedagogy) review it; `unit_json.py` writes `units/<slug>/unit.json`.
2. **Narrate** with `/kokoro-narration` (render outside `public/`, copy `cues.json` + `audio/`). Budget: first chapter ≤ 600 kB per format.
3. **Watch per chapter** (`unit/watch.ts`): every tween at a cue; shots are named boxes in `layout.ts` (`SHOTS`), fitted between the chrome.
4. **Plate additions** as parts with `root` + `set(numbers)`; every number goes `sim/rules.ts` → `derive(state)` → `sim/format.ts`.
5. **Callouts and parts**: `SPOTS` (tap/hover targets, first match wins, dot on a static part), `live.ts` (the note's numbers),
   `unit.json` `terms` (gloss ≤ 12 words) and `parts` (`n` = the balloon).
6. **Tests** (`tests/unit/lesson.test.mjs`, `framing.test.mjs`) then stills of each chapter's last settled frame at 1366/1920/2560.
7. **Play after the explanation** (build 3): a drive (d1–d3), the Workbench (exercises as seeded cases with detectors and contrast
   pairs), the Challenge and a payoff beat; the script's `exercises` + `misconceptions` feed `lintPlay`; the bench framings are
   `BENCH_POSES` in `tests/lib/framing.mjs`. Guide `learning-exercises`.
8. **Narrow widths**: the page is a designed sheet below 1024 px (`entry.ts` gate + `src/site/sheet/narrow.mjs`), no plate code loaded.

Rules the owner set for lessons: numbers are drawn, never spoken; no Bet and no opening question; nothing moves on its own timer;
several examples, then exercises after the concept; a callout on every number and a numbered badge and callout for every part.

## Exact commands
```bash
cd ~/agents/research/2026-09-24/T84/tools && python3 build.py && python3 md.py && python3 unit_json.py   # design → checked unit.json
cd ~/projects/personal/ailearning
npm test                                   # lint, words vs numbers, display exactness, hand check, framing (5 stages)
npm run test:changed                       # only the checks covering what you changed (use this per change)
npm run ci                                 # + build checks (audio budget, base, links, hygiene) + e2e under pages-sim (once a day)
node tests/e2e/unit.mjs https://<tailnet-fqdn>:8470/ailearning/u/01-neuron/   # on the drop
HYGIENE_DENY=~/agents/research/2026-09-24/T79/hygiene-deny.txt npm run hygiene
.local/drop.sh                             # rebuild the https preview
```

## Pitfalls (measured)
- An effect that owns a sentence's `set` (`EFFECTS[…].own = ['set']`) skips `sets()` in `unit/watch.ts`, so the watch's weight tracker
  (`cur`) keeps the old value. A later sentence whose `set` equals that stale value is filtered out as "no change" and never tweens; one
  that differs tweens from the effect's value anyway. Until `sets()` compares against the state instead of `cur`, let the effect own
  the next changing sentence's `set` too (noted in T103, not fixed).
- Adding a chapter: [`/explainer-engine` reference/u01-chapter.md]; each sentence's data lands on its first `{mark}` only (check a later
  word with `npm run cue-check`); `tests/unit/chapter-numbers.test.mjs` fails when narration says a chapter number that moved (declare
  each spoken number in its `NAMED` table).
- Numbers: `derive` rounds the weights to what is drawn *before* computing products, sums and misses, so every drawn row checks by hand
  (a test re-does each row from its own digits). A true minus (−), brackets on negative operands, one decimal on the clicks, two off them.
- The caption covers the bottom 216 px of the stage (two lines at 21 px + CTA + bar). Close-ups inside the machine always put a part under
  it: U01 dropped its dials/gauge/right shots; every shot box ends on bare paper. The test checks the caption band (52rem) and the bar
  (64rem × 72 px) separately: the bar is wider.
- A shot fitted at 1920 can cut at 1366 or in a short window: test 5 stages (1442×895, 2051×1195, 1442×760, 2051×1055, 993×604).
  At 1366 the side column leaves a 993 px stage: 22-unit text is ~7.8 px there. The side column mirrors the drawn working as 13 px
  text (`LIVE.working` in `unit/live.ts`, kit `Live.working`), gated on the block being in the camera box (`inShot`), or it lists
  numbers the learner cannot see. The unit e2e measures the mirror's font size at 1366.
- Lines that leave the frame (dimension lines, detail leaders) are exempt from whole-or-out but not from the chrome bands; test a diagonal
  in pieces, its bounding box is useless.
- Sampling: the framing test samples each sentence 0.45 s before the next cue, only where a named shot is held and exposure is 1.
- A sentence of 3 caption lines at 46rem forced the caption to 52rem; a comma at a line start needed the kit's `Captions.glued`.
- The e2e "forward one sentence" check needs the second sentence heard first (`furthest` > its start), or `fwd` does nothing.
- `unit.json` is generated: `unit_json.py` overwrites the repo copy from `script_src.py`. Tune shots and lamps in `script_src.py`, not in
  `unit.json` (build 2 had to port 17 hand edits back; now `unit_json.py` output equals the repo file).
- Tests that hardcode a count of the script (chapters, parts) break when the lesson grows: `site.mjs` expected 11 chapter rows on the
  narrow sheet and build 3 made 13. Read counts from `unit.json`.
- Stills: sample the last settled frame of a chapter (clip end − 0.1 s), except where the chapter ends inside an exit tween (U01 c10: 545 s).
- Working marks pile up unless each chapter fades them: the owner found the ch X sheet crowded. Fade a chapter's note, leaders, sums and
  gap marks once its recap is said; the framing test `chapter ends` counts what is visible at each end (ch X: the neuron plus 5 labels).
- Before Begin there is no caption or bar: frame the landing with `INSET_BEFORE` (28/28), or at 2560 Fig. 1 sits high with a dead band
  below it. A zoomed box must also keep its foot above the caption band (`frameIn` clamps the centre).
- A callout that repeats its gloss and cites "said at 0:09" for a part the voice never names: mark it `said: false` in `script_src.py`
  (`BENCH_CALLOUTS`) and regenerate with `unit_json.py`; never hand-edit `unit.json`.
- Callouts open on a click or tap, never on hover (owner): hover only outlines the part. The e2e checks hover leaves it closed.

## Links
- Code: `~/projects/personal/ailearning/units/01-neuron/` (`unit.json`, `unit/`, `plate/`, `sim/`, `entry.ts`), `src/site/sheet/narrow.mjs`
- Tests: `tests/unit/{lesson,framing,play}.test.mjs`, `tests/lib/{lesson,framing,solve}.mjs`, `tests/e2e/{site,unit,lesson}.mjs`
- Design / results: `~/agents/research/2026-09-24/T84/{lesson-design.md,ARCHITECTURE.md,build-2.md,build-3.md,findings.md,stills-2/,stills-3/,stills-4/}`, brief `~/agents/briefs/T84-u01-full-lesson.md`
