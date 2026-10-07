# Explainer starter: engine + Cutaway parts, with a narrated watch, guided play and an exercise

Unit A02 "Bias: the dial with no input" (T77 dogfood, built from the three skills only). Copy this folder for every new unit: it is
the one starting point that joins `explainer-kit` (engine) and `cutaway-kit` (drawing parts) and covers the whole owner-approved flow.

| Layer | Files | Owner |
|---|---|---|
| Engine | `explainer-kit` + `explainer-kit/cutaway` (`CutawayView`, `cutawayEasing`, `dialHand`) | kit, never edited per unit |
| Style | `cutaway-kit` parts composed in `src/plate/plate.ts` (+ `tally.ts`, a new instrument drawn with `Ink`), `src/shell/shell.css` | per unit |
| Unit | `content/a02.unit.json` (script) → `public/bundles/a02/` (`tools/narrate.sh`), `src/units/a02/state.ts` (numbers), `layout.ts` (geometry, `SHOTS`, `LABELS`, `WHOLE`/`SHOWN_BY`, `CASING`, `ANCHORS`), `watch.ts` (timeline on cues), `unit.ts` (controls, guided steps, exercise rounds, beats) | per unit |
| Sim | `src/sim/bias.ts` | pure arithmetic the plate and the checks share |
| Root | `src/main.ts` | fonts, stage, plate, shell text, `boot()`, `__casingPx` for the look gate |
| Gates | `test/framing.test.ts` (node), `tools/shot.mjs` + `look.mjs` (stills + look gate), `tools/cold.mjs` (perf budget), kit `tools/e2e.mjs` | per unit |

Flow: `WatchBeat` (4 clips, state = f(clock)) → "Your turn" → `GuidedPlay` (2 spoken steps: weight dial with an empty input, bias dial
to the mark, hint after 10 s) → `Exercise` (2 click-budget rounds; miss → miss line → hint → `setup` → retry) → `EndBeat`.
Config: `package.json` has both kits as `file:` deps (node tests resolve them); `vite.config.ts` aliases both to source with
`dedupe: ['gsap','three']`; `tsconfig.json` `paths` the same.
