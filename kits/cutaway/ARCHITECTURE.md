# cutaway kit — architecture (written before code)

**Start from:** T71 `mockups/cutaway-plate/src/plate/` (the owner's "10 times better" plate). Every file here is lifted from it;
only three things are new: parameters where the mockup hard-coded the neuron (title block text, dial range, colour role),
`framing.ts` (pure shot maths, so the 2560 title-block clip can be tested without a browser), and `loop.ts` (the director's
render-on-demand loop, pulled out so a new plate does not copy a 130-line director).

## Where it lives and how to import it
`~/agents/kits/cutaway/` is a plain TypeScript source package (`cutaway-kit`, no build). Its clocks, timeline, cue binder, render loop and
caption timing are the engine's (`explainer-kit`, `~/agents/kits/explainer`), so a plate aliases both kits and dedupes three and gsap:

```ts
const KIT = join(homedir(), 'agents/kits/cutaway'), ENGINE = join(homedir(), 'agents/kits/explainer');
resolve: { alias: [{ find: /^cutaway-kit$/, replacement: `${KIT}/src/index.ts` }, { find: /^cutaway-kit\/(.*)$/, replacement: `${KIT}/src/$1` },
                   { find: /^explainer-kit$/, replacement: `${ENGINE}/src/index.ts` }],
           dedupe: ['three', 'gsap'] },
server: { fs: { allow: ['.', KIT, ENGINE] } },
```
TypeScript needs the same mapping plus the three types (copy `starter/tsconfig.json`); node tests load `explainer/test/register.mjs`.
Fonts (and their OFL files) are copied from `fonts/` into the plate's `public/fonts/`. `starter/` is a runnable plate built this way:
`npm run dev` (http://127.0.0.1:18975), `npm test` (framing), `node tools/shot.mjs <url> <w> <prefix> <t,…>` (stills),
`node tools/perf.mjs <url>` (playback budget). Kit tests: `npm test` in this folder.

## Modules
| Layer | File | Role | Pattern |
|---|---|---|---|
| Tokens | `tokens.ts` | paper, ink, hatch, Byrne primaries, ink weights, type faces and sizes | Design tokens (single edit point, HMR target) |
| Look owner | `ink.ts` | shared line/fill materials per colour role and weight, text plates, `paint(theme)` | Flyweight registry + Observer (HMR repaint) |
| Geometry | `geom.ts` | polylines, arcs, Béziers, hatching, break lines, offsets, partial draw-on | Pure functions |
| Framing | `framing.ts` | shot box → scale, centre and visible rect; `cuts()` finds half-framed objects, `heldFaults` checks held moments, `fitShot` finds the nearest whole box | Pure functions |
| Renderer | `stage.ts` | WebGLRenderer, orthographic camera, fit a shot into the viewport minus chrome, render | Facade over three.js |
| Loop | `loop.ts` | the engine's `OnDemand` and `stateKey`: draw only when state changed; stop after 30 idle frames | Template method (`tick` supplied by the plate) |
| Motion | `motion.ts` | the engine's clocks, paused GSAP timeline and cue binder (`ManualClock` starts stopped here), plus `Narration` | Adapter (GSAP) + Strategy (clock) |
| Input | `interaction.ts` | spring knob, drag/keys → dial detents, pointer routing to the dial under the pointer | Adapter (pointer → dial) |
| Parts | `parts/*.ts` | callout, balloon, dimension, detail link, section cut, flange, sheet, title block, caption, focus lamp, veil, dial, gauge (signed), valve, pipe, glass tube, glass column, engraved scale, graph paper, text notes | Composite leaves (`Part { root }`), each reads plain numbers |
| Chrome | `shell.ts`, `captions.ts` | Begin card, control bar (pause, replay, status, CC), captions, `live` class; one `ShellPort` the plate's main drives | Facade over the DOM |
| Chrome CSS | `plate.css` | page tokens, caption, control bar, begin card | CSS tokens |

## Data flow
`clock (audio) → timeline.seek(t) → state (plain numbers) → part.set(...) → stage.frame(shot) → stage.render()`, the last three only
when `loop` sees a changed state. Cue times come from the `kokoro-narration` cues.json through `CueBinder`, so a callout's `set(p)`
tween starts on its spoken word.

## SOLID
- **S** a part only draws; `Ink` only owns the look; `Stage` only frames and renders; `framing` only computes; the timeline only tweens numbers.
- **O** a new plate adds parts and shots; the kit is not edited. A new instrument is a new `Part`.
- **L** any clock (`AudioClock`, `ManualClock`, `PerfClock`) drives the same timeline; seeked stills use `ManualClock`.
- **I** `Part` is one field; parts see `Ink`, never the renderer.
- **D** the plate's `main.ts` builds `Ink`, `Stage`, clock and parts once and injects them; nothing in the kit news a collaborator it does not own.

## Refinement after the dogfood (T75 step 4)
The gradient plate built from the skill alone fell short in six ways (sparse, little colour, unconnected parts, a weak Fig. 2, a colourless
moving object, tiny numerals) and the kit made three of them likely. Changes, each with the gap it closes:
- **Parts the neuron plate used but the kit lacked** (`parts/glass.ts`, `parts/scale.ts`): `Tube`, `Column`, `Valve`, signed `Gauge`,
  `Scale`, `GraphPaper`, `note`. A plate now builds a connected machine from kit parts instead of inventing thin ones.
- **Chrome** (`shell.ts`, `captions.ts`): the starter gets the mockup's bar (pause, replay, CC) and captions; frozen stills call
  `skipBegin()` so the bar shows in stills.
- **Framing covers every figure** (`framing.ts`: `framingFaults` over a `WHOLE` map, `textFaults`): the starter test checks title,
  figures, captions and dimension labels in every shot, and that the resting shot renders scale numerals at 11 px or more at 1920.
- **Look gate** (`starter/tools/look.mjs`): pixel metrics on a still (primary-colour coverage, empty cells inside the casing),
  calibrated on the neuron plate; the skill budgets them, so "too sparse" and "too little colour" are numbers, not opinions.
- Tooling: `perf.mjs` reads the script length from the page, `narrate.sh` keeps raw WAVs out of `public/`, the dev port is free.
