# explainer kit — architecture (written before code)

The engine every learning game runs on: **narrated animation → guided play → exercise/mechanic**, with no art direction in it.
A style (Cutaway is the first) plugs in through one port, `View`. A unit plugs in as data plus a timeline builder.

**Start from:** the engine copied unchanged from mockup to mockup since T65 — `T71/mockups/cutaway-plate/src/{core,timeline,audio,unit,play,
interaction,shell,content}` (the owner-approved version) and `T65/mockups/atelier-perf/src/{play/race,sim/tuner,core/bus}` (the exercise with
success/lose, hints and the event bus). Every module below is lifted from those files; what is new is only the generalisation: state type
`S` instead of `A01State`, hands bound to state keys instead of `dials[0]→w1`, steps and exercise rounds as data, one `boot()` facade for the
composition root that every mockup `main.ts` repeated.

**Survey (research first).** Theatre.js (keyframe studio), Motion Canvas and Remotion (generator/React video) are authoring tools for
video: none drives an interactive beat machine from an audio clock with render-on-demand. XState would replace a 40-line `BeatMachine` with a
dependency. Chosen: extract the fleet's own engine (GSAP stays the tween core), because it is the one the owner approved and its perf is measured.

## Package
`~/agents/kits/explainer/` is a plain TypeScript source package `explainer-kit` (no build, no three.js, peer dependency `gsap`).
Import it with a Vite alias and `dedupe: ['gsap']` (see the skill). `adapters/cutaway/` is the Cutaway style adapter; it types the stage
structurally, so it works with `cutaway-kit`'s `Stage` or a plate's own copy and never imports three.js itself.

## Layers
| Layer | Files | Role | Pattern |
|---|---|---|---|
| Time | `core/clock.ts` | `AudioClock` (context output time is the master), `ManualClock` (`?t=` stills, tests), `PerfClock` (muted) | Strategy |
| Tweening | `motion/timeline.ts` | paused GSAP timeline, rendered only by `seek(clock.now())`; named marks | Adapter |
| Cues | `motion/cues.ts` | `{cue}` marks and spoken words → seconds on the watch axis; `layoutClips` puts clips on one axis | Pure functions |
| Content | `content/types.ts`, `content/load.ts`, `content/lint.ts` | unit spec (`unit.json`: clips, terms, `chapters`, `parts`) + `cues.json` from `kokoro-narration` → `UnitBundle`; `lintUnit(spec, cues)` fails a digit in narration, a gloss over 12 words or two sentences, a term said or glossed before it is named, an unknown part term or chapter clip | Data, Specification |
| Voice | `audio/voice.ts` | schedule the watch clips on the axis, play one line, stop, soft earcons; `NullVoice` for muted/frozen runs | Null Object |
| Captions | `captions.ts` | script sentences timed by word timings; `spans` (sentences covering the watch axis with no holes, the seek grid), `tokens` (words with term links), `glued` (a term keeps its trailing punctuation on its line), `text(id)` | Pure lookup |
| Loop | `loop.ts` | rAF only while something changed; stops after 30 quiet frames | Template method (`tick` supplied) |
| Events | `core/events.ts` | typed progress events (beat, step, hint, attempt, complete, span, seek, term) | Observer |
| Store | `core/store.ts`, `unit/resume.ts` | `LearnerStore` (localStorage `plates:v1:progress`, try/catch, memory fallback, prefs); `track` feeds it from events and `flush`es on pagehide; `restore` puts reach, terms and beats back and names the resume point; `resumeLine`, `isFinished` and `landing` are the pure landing policies (Begin | Continue / Start over | the finished chooser) | Repository, Observer, Strategy |
| Chapters | `unit/chapters.ts` | chapter rows from `spec.chapters` (or one per watch clip) and the learner's reach | Pure functions |
| Hotspots | `play/hotspots.ts` | `Hotspot {part, term, hits, dot}`, `disc`/`box`, `HotspotRouter.peek/part/byTerm` | Specification |
| Hands | `play/spring.ts`, `play/hand.ts`, `play/pointer.ts`, `play/keys.ts` | 120 Hz spring (knob or needle), detent dial hand, pointer routing (6 px mouse / 10 px touch slop: a tap opens a part, a drag turns a hand), the `KEYS` table (`pressKey`) the `?` sheet lists | Adapter (pointer → hand) |
| Unit logic | `unit/director.ts` | owns state, goal easing, clock, voice, captions, hands, beats, `furthest` (the watch second reached), named terms, the open callout (`explain(id)` holds a timed beat, closing resumes at the sentence start; `hear(id)` plays the naming sentence); draws through `View` only when state changed; `chrome()` feeds progress, chapters, parts values | Mediator |
| Beats | `unit/beats.ts`, `unit/watch.ts`, `unit/guided.ts`, `unit/exercise.ts`, `unit/end.ts` | `BeatMachine` with a snapshot stack (`back(to, at)` re-watches, `returnTo` comes back with the dials as they were); `WatchBeat` (state = f(t); `seek`/`scrub` snap to sentence starts, clamp to `furthest`; `back`/`fwd` one sentence; touch pauses with a snapshot); `GuidedPlay` (spoken steps checked by predicates, the ask stands as an instruction, hints on request only); `Exercise` (rounds with pass/fail verdicts, retry, hints after misses and on request); `EndBeat` (chapter list, a closing line) | State, Memento, Specification |
| Workbench | `unit/bench.ts`, `unit/flow.ts`, `unit/hints.ts`, `unit/walk.ts`, `unit/log.ts`, `unit/kinds.ts` | `Bench` plays a queue of `Task`s (exercise rounds, contrast pairs, race levels): posed from a seed, played by hand, judged by a press-in (`commit`) or a held `verdict`; `detect` names a misconception (once per case, at a miss or while playing); `BenchFlow` (pure policy) refutes at most twice, queues the contrast pair on the second firing and offers the skip after 3 clean first tries; `HintLadder` Look → Narrow → Show me on request; `Walk` runs scripted motion on frame time; `CommandLog` keeps moves, tries and rests; `lintPlay` checks exercises are play (continuous or construct) with a detector, refutation and contrast for every misconception. The last case emits `complete` and a Continue to `next` | Command, Strategy, State |
| Chrome | `shell/shell.ts`, `shell/progress.ts`, `shell/side.ts`, `shell/pops.ts`, `shell/icons.ts` | Begin card (`begin(offer)` renders a `BeginOffer`), bar (play, back, progress with chapter ticks and term marks, status, chapters, CC, sound, one toggle per section, `?`), caption with term buttons, standing instruction (Say again, Hint), side column (chapters, transcript), sheets (keys, chapters, sound, working, a section's tabs), end card (with an optional `next` link or phantom note), section head, the callout's hidden a11y mirror — DOM and class names only | Humble Object, Facade |
| Zoom | `play/zoom.ts`, `shell/zoom.ts` | `Zoom` (pure: 1–3×, zoom about a point keeps it fixed, pan bounded inside the 1× view, `look(l, W, H)` the camera over the framed shot); `ZoomControl` (buttons, Ctrl+wheel/pinch, touch pinch, bare-paper pan via `PointerRouter.pan`); the view applies it through the stage's `look` | Strategy, Humble Object |
| Player | `player.ts` | what the chrome, the pointer and the keys ask for, in one place: toggle, back, fwd, seek, scrub, chapter, hint, tap (note first, then a part), hover, volume, mute, captions; sections: the way into Practice and back (`origin` from `BeatMachine.left`, else `lessonPoint`); prefs from the store | Facade, Observer |
| Boot | `boot.ts` | URL modes (`?t=`, `?mute`, `?beat=`), clock/voice choice, store + resume (`progress`), Begin → audio unlock, `Player.bind`, resize, `__probe`/`__d`/`__rec` test hooks (`watch`, `go`, `turn`, `seek`, `explain`) | Facade + composition root |
| Style | `adapters/cutaway/view.ts`, `adapters/cutaway/player.css` | `View` over a Cutaway stage and figure: apply state, frame the shot, `fig.frame(stage)` for screen-constant parts (the callout note), lamp, veil, render, `explain`/`light`/`noteAt` delegates; `dialHand(dial, view)`; `cutawayEasing`; the player chrome's CSS (the side column narrows the stage from 1024 px, the drawing is never covered) | Adapter, Factory |
| Starter | `starter/` | unit A02 on the engine + `cutaway-kit` parts with watch, guided play, exercise and the Cutaway gates; the copy source for new units (`example/` is the extraction proof) | Template |

## Interfaces (the three seams)
```ts
// engine ← style
interface View<S> { draw(s: S, dt: number, run: boolean): void; resize(): void; prepare?(): void; readonly canvas: HTMLElement;
  explain?(c: Explained | null): void; light?(part: string | null): void; noteAt?(px: number, py: number): 'hear' | 'close' | 'inside' | null }
interface Projector { toWorld(px: number, py: number): [number, number]; toScreen(x: number, y: number): [number, number] }
// engine ← unit
interface UnitDef<S> { initial(): S; watch: { order: string[]; lead: number; gap: number; build(s: S, cue: CueBinder): Timeline }; live?: Live<S> }
interface Live<S> { now(term: string, s: S): string | null; working?(s: S): { title: string; rows: string[] }[] }   // the numbers a note and the Working sheet show
interface Control<S> { hand: DetentHand; key: keyof S; glow?: keyof S }          // a hand drives one state number
type Spec<S> = (d: Director<S>) => boolean                                      // "is the step done?"
interface GuidedStep<S> { hand?: number; ask: string; done: Spec<S>; ok: string; hold?: number; hint?: string; hintAfter?: number; enter?(d): void; after?(d): void }
interface Task<S> { id; of?; label; ask; hands; setup(d, seed); ok; miss?; commit?(d): {pass, walk?} | null; verdict?(d): boolean | null; detect?(d, 'miss' | 'play'): string | null; look?; narrow?; show?; after?; retry? }
interface Round<S> { ask: string; setup?(d): void; update?(d, dt): void; verdict(d): boolean | null; pass: string; fail: string; hints?: string[] }
// engine → page chrome and the site
interface ShellPort { cta(…); caption(t | tokens); playing(on); pausable(on); status(t); end(onReplay);
  progress?(t, dur, furthest); chapters?(list); terms?(named); explain?(c); light?(part); instruction?(t); hintable?(on); spans?(list); values?(map) }
interface Beat { label; enter(o?: {at?, snap?}); update(dt); exit(); snapshot?(); where?(snap); seek?(t, play); scrub?(t); back?(); fwd?(); hold?(); release?(); hint?() }
d.events.on('beat' | 'step' | 'hint' | 'attempt' | 'complete' | 'span' | 'seek' | 'term', f)   // progress; `track` stores it
```

## Data flow
Watch: `AudioClock → WatchBeat.update → Timeline.seek(t) → S (plain numbers) → View.draw(S)` only when `stateKey(S)` changed. The voice
schedules the same clips at `layoutClips(order, lead, gap)` offsets, so every tween placed with `CueBinder.at(clip, mark)` lands on its word.
Guided play / exercise: `pointer|keys → DetentHand (Spring) → S[key]`; the beat checks its `Spec`/`verdict` every frame, holds it for
`hold` seconds, then `Director.say(ok|pass|fail)` and moves on. The director eases free keys toward `goal` (camera slower, snapped under
reduced motion) and lands a key on its goal once it is within `Easing.eps`, so the loop stops. Nothing runs on its own timer: every change enters through the clock, a hand or a beat.
Seek: `ProgressBar | transcript | chapter | J/L → Player.seek → WatchBeat.seek(t)`: clamp to `furthest`, snap to the sentence start, write the
memento back, render the frame (`tl.seek(0); tl.seek(t)`, the GSAP trap), then play on. From a play beat the same seek re-watches through
`BeatMachine.back`, and "Back to your turn" returns with the dials as they were. Callout: `tap → HotspotRouter.peek → Director.explain(term)`
(held narration) `→ View.explain(Explained)` (drawn note) `+ ShellPort.explain` (a11y mirror); a locked term (not yet heard) says only where it
is explained. Resume: `events → track → LearnerStore`; next visit `restore` → `landing(resume, isFinished, finished)` → Begin card "Continue" →
`go(beat, {at | snap})`, or a finished chooser's beat. Sections: `go()` records `BeatMachine.left = { name, enter: Beat.leaving?() ?? { snap } }`
(Memento); the Player keeps it as `origin` on entering a section from the lesson, and the section's way back goes there, else to
`lessonPoint()` (the end once finished, else the first chapter not done). There is no Parts list: the numbered badge is the only way to a part.

## SOLID
- **S** clocks tell time, the timeline tweens numbers, the voice plays audio, a beat decides flow, the view draws; the director only mediates.
- **O** a new unit adds a state type, a timeline builder, steps and rounds as data; a new mechanic is a new `Beat`; a new art direction is a
  new `View`. The kit is not edited for any of them.
- **L** any `Clock`, `Voice` (`VoicePlayer`/`NullVoice`), `View`, `Beat` implementation is swappable; tests run on `ManualClock` + `NullVoice`.
- **I** `View` is two methods and a canvas (callouts optional), `Projector` two, `ShellPort` six required and the player methods optional; the engine never sees three.js.
- **D** `boot()` (or a unit's `main.ts`) builds every collaborator once and injects it; the director news only what it owns (timeline, captions, beats).

## Perf rules (from T69, measured)
1. Render on demand: `View.draw` runs only when the state key changes, the clock plays, or a flow animation is live (2.5 s tail). Idle = 0 frames.
2. Nothing before Begin but the opening frame; no `setAnimationLoop`.
3. Physics is a 120 Hz fixed-step spring per hand, not a rigid-body engine; it rests when the hand rests.
4. Compile shaders (`View.prepare`) before Begin, not on the first watch frame.
5. The loop's `dt` is capped at 0.1 s, so a background tab never makes a spring explode.
6. Timelines import `gsap/gsap-core`: the kit tweens plain numbers, so CSSPlugin (18 kB raw) stays out of the bundle.

## Tests
`npm test`: `engine.test.ts` (cues, captions, hands, watch, idle, guided, exercise, easing, dialHand) and `player.test.ts` (seek and
spans, back sentence, keys, re-watch with dials kept, tap vs grab, callout hold and hear, term tokens, instruction and hints on
request, end, resume with a throwing store, volumes, lint), `bench.test.ts` (command log and rests, flow policy, hint ladder, walks, pencil/slot/locked hands, pass and
miss with refutation and contrast, Show me and the skip offer, the last case completing the beat, lintPlay) `lesson.test.ts` (asserts, lint, notes, chapter stops, peek vs pin), `landing.test.ts` (beat chapters with clips, `isFinished`, `landing`,
`resumeLine`, `lessonPoint`, `BeatMachine.left`), `voice.test.ts` and the section tests: 58 tests (2026-09-25) on `ManualClock` + `NullVoice` and a stub shell.
Units built on the kit meet the declutter budget (≤ 7 labelled things per step, a chapter end keeps only its result, no leftovers): the
site's `npm run declutter -- <NN>` checks every step (guide lesson-declutter, T325).
