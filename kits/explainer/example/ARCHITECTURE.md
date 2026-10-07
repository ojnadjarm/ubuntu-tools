# Example unit A01 (neuron) on explainer-kit + the Cutaway adapter

The T71 owner-approved neuron plate, rebuilt on the kit (T77). It is the template for a new unit: copy it, keep the layers, replace the content.

| Layer | Files | Owner |
|---|---|---|
| Engine | `explainer-kit` (alias in `vite.config.ts`) | kit, never edited per unit |
| Style | `src/plate/*` (theme, ink, stage, parts, `Plate.apply(s, dt, run)`), `src/shell/shell.css` | Cutaway look; `CutawayView` adapts it |
| Unit | `content/a01.unit.json` (script), `public/bundles/a01/` (Kokoro clips + cues.json), `src/units/a01/state.ts` (numbers), `watch.ts` (timeline on cues, shots), `layout.ts` (geometry, anchors), `unit.ts` (UnitDef, controls, guided steps, beats) | per unit |
| Sim | `src/sim/neuron.ts` | pure arithmetic the plate and the step checks share |
| Root | `src/main.ts` | fonts, plate, shell text, `boot()` |

Flow: `boot()` → `WatchBeat` (state = f(clock)) → CTA "Your turn" → `GuidedPlay` (two spoken steps on the dials) → `EndBeat`.
Proof (T77): same state as the original at every 10 ms of the 78.8 s watch (0 of 88 cue onsets moved), same perf; see
`~/agents/KB/guides/explainer-engine.md` (numbers) and `~/agents/research/2026-09-24/T77/out/`.
