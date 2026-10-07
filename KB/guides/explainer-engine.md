# Build a narrated learning unit: animation on the spoken word → guided play → exercise (the explainer engine)

Tickets: T77 (extracted from T65 atelier-perf and T71 cutaway-plate), player T84, layout and number-only callouts T87, endless practice and
give up T88, lesson then Practice, saved completion, one voice, buttons T91, Practice from anywhere, landing states, closing chapter, no
Parts list T92, section head framing T93, pencils and cue layers T95, sheet change T96, cleanup T100, skill split T101, clamp and presses T106–T110, review T111 · Last verified:
2026-09-26 by the kit's `npm test` (60 pass); U01 on the site ran the player through T100's full `npm run ci`.

## When to use
- Any learning-game unit, lesson or narrated explainer where visuals land on spoken words and the learner then plays: skill `/explainer-engine`
  (a short router; the how-to lives in its `reference/*.md`). This guide keeps the history and the measured pitfalls.
- Audio and cue sheet: `/kokoro-narration`. The look: `/cutaway-style` (or your own `View`). A non-interactive video: this is overkill.

## The path we took
- **T77** lifted the engine, copied mockup to mockup since T65, into `~/agents/kits/explainer/` (style-agnostic, no three.js): clocks (audio
  is the master) → paused GSAP timeline seeked by the clock → cue binder (`{mark}` → second) → director (Mediator) + beat machine (State):
  `WatchBeat`, `GuidedPlay` (Specifications), `Exercise`, `EndBeat`; detent hands on 120 Hz springs; render on demand; progress events;
  `boot()`. A style plugs in through `View`; Cutaway is `explainer-kit/cutaway`. Survey: Theatre.js, Motion Canvas, Remotion are
  video/keyframe tools with no interactive beat machine on an audio clock; XState would replace 40 lines. Kept the fleet's engine with GSAP.
- **T77 dogfood** (a fresh agent with only the three skills built A02 "Bias") listed 9 gaps, all closed: the starter, round semantics,
  `dialHand()`, `Easing.eps`, overshoot counting, `tools/narrate.sh` (raw WAVs out of `public/`), `tools/drop.sh`, gates on an engine unit,
  e2e `#n` marks.
- **T84** added the player (seek on sentence spans, chapter bar, re-watch keeps the dials, tap vs grab 6/10 px slop, drawn callout that holds
  the voice, caption term links, side column, keys sheet, instruction with hints on request, end card, resume, volumes, `lintUnit`) and the
  Workbench (seeded cases, detectors, refutations, contrast pairs, Look → Narrow → Show me, skip, `lintPlay`). Owner fix: a callout never
  opens on a pointer pass.
- **T87** owner rules: numbers only after the explanation (`LabelMode`), click the number only (`MarkerRouter`), controls and numbers in clear
  paper by rule (`place`, `layoutFaults`), per-pose layout, solo tuning instead of a race.
- **T88** endless practice (`pool`, `?seed=`), give up, a chooser after the watch. It also added one modal with a stack of views for the Parts
  list and callouts; **T92 removed it** with the Parts list (owner: the numbered badge and its callout name a part).
- **T91** chapters then a Practice section (`sections`, `SectionHead`), grow-only saved progress, one voice at a time, the hatched button roles.
- **T92** Practice from anywhere (`Beat.leaving()` + `BeatMachine.left`, Memento), landing states, the closing chapter, bar status that wraps.
  Design: `~/agents/research/2026-09-25/T92/ARCHITECTURE.md`.
- **T95** learner pencils, first-drag cue, hint arrows on top; kit `layoutFaults` takes `z`, `kind: 'cue'` and `clip` (59 kit tests).
- **T96** the site holds the page turn until the plate draws (`sheet:ready`).
- **T100** cleanup: the Cutaway kit's motion, loop and captions re-export this engine; U01 imports the kit's `geom` and `parts/part`; site e2e
  runs in parallel lanes (879 → ~450 s) and `npm run test:changed` runs only the covering checks.
- **T101** split the 29.5 kB skill into a 4 kB router plus 8 reference files; this guide lost its how-to duplicates.

## Exact commands
```bash
guide explainer                                                            # this page + skill /explainer-engine
cd ~/agents/kits/explainer && npm test                                     # 60 tests
cp -r ~/agents/kits/explainer/starter ~/path/my-unit                       # then the skill's reference/new-unit.md
node ~/agents/kits/explainer/tools/compare.mjs out/before.json out/after.json   # refactor proof: state, cues, audio, frames
```
Gates and e2e actions: skill `reference/testing.md`.

## Pitfalls (measured)
- **Sheet revealed before the plate drew** (T96): `blocking="render"` does not cover a module's top-level await; Sheet I was revealed 173–401 ms
  (1× CPU) and 774–1123 ms (4×) before the plate drew. Fix: `sheet:ready` on the first frame, the site holds the turn; an idle canvas without
  `preserveDrawingBuffer` was captured white on the back turn. Guide `learning-site-homepage` § Smooth sheet changes.
- **Seeding progress, then reloading, tests the old page** (T92): `pagehide` flushes the leaving page's progress and `LearnerStore.save`
  unions its sets into the seed (a seeded "stopped at bench" landed as finished). Seed through a fresh context's `storageState` (`flow.mjs` `landAt`).
- **The way back always went to `end`** (T92), whose entry emits `complete: unit`: an unfinished lesson read finished. Fixed by `leaving()`.
- **Orphan CSS declarations** (T92): removing a selector from a multi-line rule in `player.css` failed the lightningcss build ("Invalid token in
  pseudo element").
- **Saved completion** (T91): `visited` was never stored and a null `restore()` let the next save write empty sets; the owner saw finished
  chapters (XI/XIII) as "Not reached yet". The site's lesson e2e reopens the finished lesson with sound and needs 13/13 rows done and open.
- **Two voices** (T91): `line()` = `load().then(start)` and `stop()` only stopped started sources, so a line cut while decoding started later;
  entering "Your turn" while `d1` was fetching, then again, played it twice. `flow.mjs` (clip fetch delayed 700 ms, 20 entries, spying on
  `AudioBufferSourceNode.start/stop`): old build 17 overlaps and 6 voices at once, now 0.
- **Section head over the plate** (T93): U01's `frameIn` floored the zoom at the sheet's width, so on wide stages (1366×768, 2000×950,
  2560×1080) the Practice shot rose 54–213 px under the opaque `SectionHead` rule. Fixed with the inset's `whole: true`.
- **Hint words with no slot** (T95): 543 reachable e3 cases had 158 with no clear slot for the arrow words (outward slots within 40 units);
  0 with inward and outward slots within 72 units, slots off the casing and every radius tried. A whole-arc line break round a value box hid a
  two-click arc entirely: drop only the under-stroke there. Per-pose number slots made numbers jump inside the dial and under the break line:
  fixed windows instead. The needle grip at r 38 with gripR 16 met its own window at the stub (3 < 4): r 35.
- **Engine refactor proof** (T77, neuron unit, 1920, headless Iris Xe): frozen sweep 7883 samples, state max diff 0, 88 cue onsets moved 0 ms;
  audio clips land at offset + outputLatency + 20 ms in both builds; live onsets differ ≤ 19 ms, the original against itself 16 ms (frame
  quantisation); rAF max 16.8 ms, 0 frames > 20 ms; idle draws 0; ready 355–371 vs 366–407 ms.
- **Stills differ run to run** on flowing dashes (104–270 px, original vs itself): compare state, not pixels.
- **Spring overshoot**: keyboard `turn(5)` crosses 7 detents before it settles. **Key presses in one frame**: `DetentHand.turn(n)` was relative
  to `value()`, so four presses landed one click; it keeps a `goal` now.
- **Goal easing**: before `eps` easing stopped only when the 4-decimal state key stopped changing: a 500-unit lamp move drew about 5 s, the
  camera about 8 s; now 2.7 + 2.5 s and 4.6 + 2.5 s (flow tail). An `EndBeat` `enter` that moved the lamp cost 120 `idleEnd` frames.
- **Starter A02 numbers** (1920, headless Iris Xe, https drop): e2e 51.6 s, the whole flow, idle 0/0, 0 errors; firstPaint 242 ms, plate 39 ms,
  rafMax 16.8 ms, 0 frames > 20 ms, draw max 3.4 ms; look at the play shot 4.5 % primary, 23 % bare, largest square 3 (4 at 2560).
- **The framing gate caught a cut the stills missed**: the dogfood's `bias` shot cut "Fig. 1." at 1920×960; `{x:-330, y:-110, w:1029, h:672}` is
  the only box near the bias row that is clean on all 5 viewports.
- **Bundle growth broke the cold page turn**: +37 kB raw pushed the render-blocking unit module past Chromium's ~4 s cross-document view
  transition limit under uncompressed `pages-sim` (reveal 4.38 s, turn skipped; 4.04 s kept it). Fixes: `gsap/gsap-core` (−18 kB raw, gzip
  205.8 → 198.2 kB) and `pages-sim` serving gzip like Pages (cold card at 1.7 s).
- **Captions**: a term is an inline button, so a line could start with its comma ("weights" / ", one gauge") until `Captions.glued` (kit test P6).
- **Canvas painters**: U01's tuner drew "STEP" as "P" after a centred repaint (`textAlign` leaked).
- **Diagonal leaders under the bar**: U01's detail A leader ran under the bar's left end at 1920 until re-routed; hence piecewise tests (24 boxes a segment).
- **Bench**: the last case emitted nothing, so progress never stored "played"/"cleared" (fixed; kit test). The skip chip sat under the button
  (Playwright: "`<button data-k="cta">` intercepts pointer events"). A case with no Look rung showed "Another hint" first.
- **Detent walks at `?fast=10`**: a Show me walk ended before its last click landed; scripts poll for the worked case (≤ 5 s).
- **End card**: `.chapter-list li` as the 3em/1fr grid squeezed labels to 29 px, one word a line, and 13 rows pushed the card to top −773 px at
  1366; now labels 442 px, Replay visible at 1366/1920/2560.
- **three.js `LineSegments2`** grown after its first draw is cut to the first length: U01 Fig. 5 drew 1 of 60 segments.
- **Paused mid-tween numbers**: a dial swinging 1 → 1.5 read 2.22 / 0.78 while paused, until `Beat.goals()`.
- **Plate text at 1366** (T84): 22-unit plate text draws at ~8 px, hence `Live.working`'s 13 px mirror.
- **Side column**: `--side-w` applied before the player went live, so the landing measured a stage 380 px narrower than the one shown.
- **End card click-through**: a click outside the card reached the plate and opened a callout under it; the shell's capture listener stops it.
- **`perf.mjs` on an engine unit**: it clicks a Begin card under `?mute`, which the engine never shows; use `cold.mjs`.
- **T100 baseline** (2026-09-26): full ci serial ~892 s, 98.5 % e2e (geometry 336 s, lesson 255 s); U01 plate chunk 850.6 / 243.5 kB raw/gzip.

- **A balloon with no slot in any pose is hidden silently** (T99 → T105): moving Fig. 6 into the watch scene left balloons 6, 11, 17, 18
  with no clear slot; `place.test.mjs` (node, ~15 s) failed, but T99 ran only `tsc` under the ship-first rule. Run the node tests before
  every drop; the fix moved the figure's side and hosted leaders elsewhere, not the rule.
- **A guess control wider than its gauge** (T95 → T106/T110): the guess pencil went to −1.5 with a hatched band below 0, and its drag
  wrapped from −1.5 to 5, while the narration says the output never goes below 0. Clamp to the gauge (0–5), no wrap; a detector that
  only a below-range guess could trigger goes too (contrast k3 dropped from `lesson.mjs`).
- **Synthetic clicks hide a lost press** (T96 → T107): `click()` sends down and up in one instant, so T96 measured 10/10. A hand-held press
  (down, 90 ms, up) that started on the turn and ended after it lost its click to `<html>`: 0/6 at +100 ms. `transitions.mjs` now presses
  for real at 0/100/300/1000 ms and fully loaded; 149/149 after the `turn.js` fix. Xvfb + xdotool with Edge matched it.
- **Test loops that run to their cap**: `while pgrep -f "<name>"` matches its own shell (T105, T110: 10 min each, after T98 had named it).
  T107 re-ran the 10-min `transitions.mjs` for 2 h; iterate on one case.
- **A headed browser plays the lesson aloud** on the owner's desktop (T107); `--mute-audio`, headless or Xvfb.

## Links
- Code: `~/agents/kits/explainer/{src,adapters/cutaway,tools}`; starter `~/agents/kits/explainer/starter/`; proof `example/`
- Skill: `~/.claude/skills/explainer-engine/SKILL.md` + `reference/{new-unit,components,exercises,lesson-flow,layout,narration-sync,testing,pitfalls}.md`
- Tests: `~/agents/kits/explainer/test/{engine,player,bench,lesson,place,landing,voice}.test.ts`, starter `test/{framing,content}.test.ts`
- Design / results: `~/agents/kits/explainer/ARCHITECTURE.md`, `~/agents/research/2026-09-24/T77/`, `~/agents/research/2026-09-25/{T92,T100}/ARCHITECTURE.md`
