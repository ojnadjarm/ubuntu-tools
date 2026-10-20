# Lesson declutter: ≤ 7 labelled things per step, checked by `npm run declutter`

Ticket: T325, T328 · Last verified: 2026-10-20 by T846 audit (paths, package.json scripts, rules.mjs), 2026-10-18 (T368 parallel pages), 2026-10-12 by `npm run declutter` on U01–U07 at 1366x768, 1920x1080 and 2560x1440 plus `node --test tests/unit/declutter.test.mjs`

## When to use
Building, fixing or reviewing any ailearning lesson (sheet/unit), or writing a lesson brief: every step must meet the declutter budget and
the brief must cite this check. Not for the homepage or the narrow sheet (desktop only: 1366, 1920, 2560).

## The path we took
The owner's rule (memory `lesson-ux-prefs` #2: working marks erase once their step's recap is done; a crowded final sheet is a fault) was
a promise in prose that lanes ignored, so T325 turned it into a number and a check. Only U01 has the kit's `layout()`, so the check reads
what is really drawn instead: a canvas text recorder plus the three.js scene graph, on every unit.

| Module (`~/projects/personal/ailearning/`) | Does |
|---|---|
| `tools/declutter.mjs` | CLI: Vite dev server (no HMR, no watcher) + headless Chromium, one table per unit, exit 1 on any fault |
| `tools/declutter/walk.mjs` | Poses: each watch sentence (0.05 s before the next), chapter start/end, each guided step + done, every Workbench/Tuning/Practice case open, after one press of each plate Nudge/Step/Sweep button in turn (including one a press brings up, such as Step after Sweep), then after each hint short of Show me, and answered (Give up; a case with no answer, such as a contrast pair, solved by its verdict over every hand step) once nothing drawn has changed for 1.25 s, the closing chapter every 0.25 s, chooser, end card; then each beat that plays on by itself again at real speed (a muted line lasts its clip). Each pose rests 1 s first (labels placed on rest need 0.35 + 0.25 s). Each watch chapter, play beat (the end card on the page of the beat before it) and Workbench case (after the case before it is answered unrecorded) runs on its own page, 8 at once (`PAGES` in `declutter.mjs`; T368: 06 1255 → 280 s, 07 1246 → 289 s, same fault counts) |
| `tools/declutter/probe.js` | In page: every fillText/strokeText with its box and cap height, callout-layer lines, dots, rings, arrowheads, page controls over the plate, the end card and the zoom panel |
| `tools/declutter/things.mjs` | Texts → things: balloons, names, values (a label and its value count once); furniture and graduations are not counted; orphan leaders (a chain of leaders ≥ 12 px with no end on a balloon or within 4 text heights of a text; U07 BACKWARD PASS sits 3.3 text heights from its leader at 1366) |
| `tools/declutter/rules.mjs` | The budget and the faults (pure, unit-tested); `CHECKED` (the units the check covers) and `EXCEPTIONS` (named, maintainer-approved) |
| `tools/declutter/report.mjs` | `out/declutter/<slug>.md` + `.json` |

**Budget** (`rules.mjs` `BUDGET`): ≤ 7 labelled things (balloons, names, values, plate controls) per step · a finished chapter keeps ≤ 2
things that came in during it · 0 leftovers (also: a case's answer marks gone when the next case opens, unless that case draws them itself
when opened fresh) · 0 stray controls · 0 duplicates · 0 overlaps · 0 crossing leaders · 0 leaders naming nothing · labelled things ≥ 8 px cap height · none under
the end card, no label or plate control under the zoom panel · at real speed no stretch ≥ 1.5 s with nothing labelled, from the beat's
start to its end. Source and definitions:
`~/agent-work/T325/BUDGET.md`.

**Scope (one list, one place):** `CHECKED` in `tools/declutter/rules.mjs` = U01–U07, the sheets the owner has reviewed. `npm run declutter`
with no unit, daily `npm run ci` and `test:changed` check only these, so U08–U14 never fail ci; `npm run declutter -- 09` still measures any
unit by hand. Add a unit to `CHECKED` once the owner has reviewed it.

**Exceptions (named, never a raised budget):** `EXCEPTIONS` in `rules.mjs`; a matching fault shows as `exempt` in the table and never
fails. Today: U01 race L2b (a–d tags around both dials: over + the tag duplicates) and U04 bench/practice k3–k5 (Plate A and Plate B
repeat a label: duplicates drawn 2×), both owner 2026-10-12.

**Warnings:** `WARN` in `rules.mjs` = `small` (labels under 8 px cap height), pending owner ruling, 2026-10-12: printed and counted in the
table and the summary line, never a failing step (exit 0). Remove it from `WARN` once he rules.

**Wired in:** `npm run test:changed` runs `npm run declutter -- <NN>` for every changed unit in `CHECKED` (`units/`, `u/`, `public/bundles/`);
`npm run ci` ends with `npm run declutter -- --size 1366x768` over the `CHECKED` units (one width: three widths over 7 units
would push ci past 45 min; T331); the nightly runner runs `npm run ci:core` and declutters only the units changed since their last green
run, a full 1366 pass runs weekly (Sun 05:30; T340, guide `ailearning-ci-daily`); `npm run declutter:full` runs 1366, 1920 and 2560 into `out/declutter/<WxH>/`; `/make-lesson` step 5 and its UX checklist; `/explainer-engine`
rule 5 and `reference/testing.md`; the explainer kit's `ARCHITECTURE.md`.

## Exact commands
```bash
cd ~/projects/personal/ailearning
npm run declutter -- 04                                   # one unit (04, U04 or 04-gradient), ~5 min at 1366, exit 1 on any fault
npm run declutter -- 04 --size 1366x768 --out ~/agent-work/<ticket>/m1366   # the other desktop widths
npm run declutter -- 04 --watch                           # only the watch (or --play) while iterating
npm run declutter                                         # the CHECKED units (U01–U07)
npm run declutter:full                                    # the CHECKED units at 1366, 1920 and 2560 (exit 1 on any fault)
node --import ./tests/lib/register.mjs --test tests/unit/declutter.test.mjs   # the rules on hand-made samples
```
Read `out/declutter/<slug>.md`: one row per step, then "Faults by step" with every counted thing.

## Cleaning a lesson to the budget (never by adding elements)
Erase working marks at their recap; show slopes/values only on the part being explained; hide callouts while things move; remove controls
outside their step; names only during the explanation, numbers after. Chapter sentences and numbers stay word for word (`unit.json`
byte-identical is the proof).

## Pitfalls (measured)
- The check cannot see marks without text (hatching, ghost lines, empty holders, dashed slots, half-erased outlines), leaders with no dot or
  balloon, boxes not drawn as one 4-segment rectangle, or anything under 0.2 opacity: judge them by eye on stills. Of these it now catches
  only orphan leaders (legs left after their label or balloon is erased). An empty-rectangle rule was measured and dropped: 163 distinct
  empty rectangles in U02 alone at 1366, nearly all part outlines (racks, trays), so it cannot tell a dead holder from a part.
- The blank rule counts from the beat's start: U02's closing chapter said its first sentence over the bare plan (0 labelled for 8.75 s at
  1366); T340 shows the plan's names (INPUT ONE/TWO, H1, H2) over the payoff sentence until the readings show (`unit/close.ts`).
- It poses a step, it does not play it: flicker while things move (a balloon blinking during a walk, values retyping) is not covered; a
  verifier plays these in real time. Presses and hints are posed only inside Workbench/Tuning/Practice cases (one press per button, in
  page order, then the hints), not in the watch or guided beats.
- The real-speed walk once waited every muted line twice (its own `voice.line` timer plus `Director.say`'s) and stopped after 10 s
  unchanged mid-line; it now relies on `say` alone and stops on a 10 s hold only when no line is playing.
- Answers were sampled mid-ripple (U01 race) and contrast pairs (no Give up) never solved; the walk now waits until the drawing is still and
  solves a case with no answer by its verdict (step `<id> solved`).
- Duplicates compare whole label texts only: "1.5" inside "2 × 1.5 × 1.5 = 4.5" next to "LAST DIAL · 1.5" is not flagged. Flagging it
  would also flag every intended working row; open owner decision (T328).
- Contrast pairs draw the same name on Plate A and Plate B (U04 k3–k5: BEFORE 3.88, WEIGHT SLOPE): the owner allowed it (2026-10-12),
  so it is a named exception, not a budget change.
- `covered` sees the end card and the zoom panel only, and only labelled things and plate controls: a frame corner or part outline under
  the zoom panel (U02 Fig. 5 at 1366) still passes.
- A 3-frame sample missed labels placed after a rest (U04 c4a.rings 1 → 3); the walk now rests 1 s per pose (+~3 min a unit).
- Run units one at a time. Six runs in parallel (load 15 on 16 cores) took 15–35 min a unit instead of ~4 and caught a balloon mid
  draw-on (U05 2560 c6b.recap6: a leader with no ring, an orphan that was gone when re-run alone in 78 s).
- With HMR on, another lane's edit reloaded the page mid-walk and crashed a run (U07); the dev server now runs with `hmr: false, watch: null`.
- A ruled canvas drawing 3+ texts is furniture (title block), which hid the NOTE · TESTS card (U01 e5 answer: 0 labelled); a canvas that
  carries a worked number (`d.d`) is read.
- A dial whose other graduations are out of frame left a lone "+5" counted as a value (U02 c5a.once); a canvas that draws 2+ integers is a scale.
- Real counts before T325 (1920): worst steps 31–68 labelled things, 121–154 of ~150 steps over budget in every unit.

## Links
- Code: `tools/declutter.mjs`, `tools/declutter/*`, `tools/test-changed.mjs` (unit → declutter), `package.json` (`declutter`, `ci`)
- Tests: `tests/unit/declutter.test.mjs`, `tests/unit/test-changed.test.mjs`
- Design / results: `~/agent-work/T325/BUDGET.md`, tables `~/agent-work/T325/stick/m1920/` + `m1366/`, per-lane evidence `~/drop/T325/<unit>/` is gone since 2026-10-13 (a copy is in `~/.local/share/Trash/files/`)

- Parallel pages (T368): a case's open pose reads the dials the previous case left, so its values (TURN, LAST DIAL) differ from a serial run; serial runs already differ there (and in `small`, 920–923 on 06). Counts and faults match.
