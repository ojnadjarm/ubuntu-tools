# Exercises as play on a learning unit: Workbench cases, misconception detectors, contrast pairs, hints, solo tuning levels, proven by a scripted e2e (ailearning)

Ticket: T84 (U01 "The neuron", build 3 of 3, fix pass) · Last verified: 2026-09-25 by `npm run ci` green in `~/projects/personal/ailearning`
(node play tests over 400 seeds, `tests/e2e/lesson.mjs`: 62 cases opened, 30 detector firings over 21 cases, 9 contrast pairs, 0 faults, also on the drop link).

## When to use
Adding exercises, a Challenge or a payoff beat to a unit on the explainer engine: skill `/explainer-engine` (Workbench section).
The explanation, script and callouts: guide `learning-unit-authoring`. The look: `/cutaway-style`.

## The path we took
- Owner rules: explanation first, then exercises; exercises are play (a value set by hand, or a thing built), never option lists,
  true/false, typed answers or drag-a-word; hints on request only (Look → Narrow → Show me); a refutation at most twice; 2 misses on one
  misconception put a contrast pair next; 3 clean first tries offer the skip; nothing moves on a timer; numbers are drawn, never spoken.
- Started from the kit's `Exercise` (rounds) and T65's Atelier puzzles; they had no detectors, contrasts or seeded cases, so the kit
  gained `Bench` (upstream, tested) and the unit writes cases as data: `units/01-neuron/unit/bench/e1.ts … e8.ts` (one exercise each,
  1–4 cases), `contrast.ts` (k1–k9), `unit/race.ts` (L1–L3 + L2b), `unit/click.ts` (the payoff), `bench/common.ts` (M ids, walks, press-in).
- Cases come from seeded generators in the sim (`sim/generators.ts`), never hand-typed numbers; every rule a case must keep (on a detent,
  the trap and the answer read differently, one setting meets both examples) is a node test over 400 seeds.
- Detectors read the hands and `d.log` (moves, tries on locked parts, rests = settings no move followed within a gap); each names one
  misconception id (`m.*`) that the script's `misconceptions` list gives a refutation clip and a contrast task.
- "You are the tuner" (T87, replaced the T84 race; owner: "you are always going to lose... YOU ALONE should be able to tune it"): the
  learner does the tuner's job on L1–L3 (`sim/race.ts` keeps the levels; `GOALS` = 0 where a setting meets every mark, else the best
  total on the clicks; `reached(w, k)`). Each settled dial click is one STEP; L1/L2 pass when the drawn total meets the goal (held
  verdict), L3 on Done at the floor (Done above it says `l3more` and returns null, so play goes on). Opening line `t0` names the job,
  closing `ttuned` names what they did. Proof (`play.test.mjs`): a grid search over every detent pair finds each goal, a BFS reaches
  it in 5 clicks, and a hand that always turns one or both dials a click toward a smaller total gets there in 3 moves. Measured pitfall:
  turning only one dial at a time can stall (L1 at total 3), since the total miss is an L1 norm; the hints carry that.
- Proof: `tests/lib/solve.mjs` holds, per case, the right moves, the wrong move its detector listens for, and what "Show me" must leave;
  `tests/unit/play.test.mjs` checks them over 400 seeds in node; `tests/e2e/lesson.mjs` plays the whole lesson in Chromium with them.

## Exact commands
```bash
cd ~/projects/personal/ailearning
npm test                                                               # play.test.mjs: generators, trap vs solve, assembly, tuner levels, lintPlay
npm run build && node --import ./tests/lib/register.mjs tests/e2e/lesson.mjs            # whole lesson by script, ~3 min
node --import ./tests/lib/register.mjs tests/e2e/lesson.mjs https://<tailnet-fqdn>:8470/ailearning/u/01-neuron/
# page hooks: ?mute&fast=10&beat=bench ; window.__d.beats.cur.{task,phase} ; __d.events.log (step/attempt/detect/hint/complete)
```

## Pitfalls (measured)
- The kit's Bench never emitted `complete` after the last case, so stored progress stayed "driven". Fixed upstream; the e2e reads
  `plates:v1:progress` and fails unless U01 is "cleared".
- The skip chip sat under the button ("`<button data-k="cta">` intercepts pointer events"); `player.css` lifts it; the e2e checks overlap.
- `?fast=10` speeds walks and muted lines, not springs: a Show me walk ends before the dial lands. Poll for the worked case (≤ 5 s).
- A detent hand's `settled()` is true for a moment right after `turn()`; wait for `value() === target && settled()`.
- A trap can coincide with the answer for some seeds (e1: weight = goal − input can equal goal / input); `wrong()` returns null and the
  e2e uses Show me there. Test the trap against the answer over all seeds, not one.
- Contrast placement: a miss firing puts the pair before the retry (button "Continue"), a play firing after the case.
- L2's drawn total (rounded to 2 dp) rises after the goal although the raw total never does (steps 21 and 26): the test checks the
  drawn total only up to the goal.
- Node ≥ 24 strips types but not TS parameter properties: a test cannot import a module that reaches one (`plate/parts/meters.ts` via
  `unit/controls.ts`), so the solver inlines the hand indices.
- `| tail` after `timeout` hides a failing e2e's exit code; write to a log and read it.
- A figure that appears beside Fig. 1 (Fig. 5, Fig. 6) collides with balloons and labels made for the explanation: U01 hides balloons
  6 and 11 there (`BESIDE` in `labels.ts`) and moved the race rows (STEP sat on example 3's row). `framing.test.mjs` checks them (10 → 0).
- Fig. 5's line drew 1 of 60 segments (three's cached instance count; `ink.setSegs` clears it). Stills alone missed it: the e2e's
  `__t.cut()` lists every visible line drawn short, at the drive, L3 pressed early and the Click.
- A scripted play can resolve before its last move: once the output meets the goal the verdict holds 0.35 s and disables the hands,
  so a no-op second dial move then hit a disabled hand (seen once, on the drop link). The e2e skips moves once the case has left play.
- Stills taken with `?beat=` skip the watch: call `d.reach(d.tl.duration())` first so the watch's end state is applied.
- Keyboard turns were lost: `DetentHand.turn(n)` counted from the spring's `value()`, so 4 fast presses landed 2 steps. It now counts
  from the pending goal (kit test: 4 `turn(+1)` in one frame land 4 steps). Click-count cases (e4, ch VII) depend on it.
- The end beat must leave the plate usable: `EndBeat(d, label, { hands: [0, 1] })` keeps the dials on after the card closes (×, Esc,
  click outside); a return visit lands on the end without the card.
- Race readouts: the STEP counter and "best on the clicks" need their own slots (the floor label sits on the step row, right-aligned);
  the tuner block shows only in ch IX and the race.

## Links
- Code: `~/projects/personal/ailearning/units/01-neuron/{unit/bench,unit/race.ts,unit/click.ts,sim}`; kit `~/agents/kits/explainer/src/unit/{bench,flow,hints,walk,log,kinds}.ts`
- Tests: `tests/unit/play.test.mjs`, `tests/lib/solve.mjs`, `tests/e2e/lesson.mjs` (in `npm run e2e`); kit `test/bench.test.ts`
- Design / results: `~/agents/research/2026-09-24/T84/{lesson-design.md,build-3.md,findings.md}`
