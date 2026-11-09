# Familiars: the agent creature look (3D on the stage, SVG in lists)

Ticket: T1515-V2, T1515-V4 · Last verified: 2026-11-10 by `node tests/test_next.js`, `tools/shots.mjs` at 5 widths, draw-call and fps count on the iGPU

## When to use
An agent needs a face: a new panel screen, another project, a new role or state. Load skill `/familiars-style` (rules + kit).
Not for people or the owner (he is the gold diamond), and not for pixel-art avatars (`/pixel-avatar`).

## The path we took
Existed: V1 mock `~/drop/T1515-V1/` (look A, three.js Groups, 388 draws) and the panel's ray-marched blob creatures.
Chosen: one merged, bone-skinned mesh per creature (2 draws: toon body + ink hull) in its own depth + 4× MSAA target,
composited once onto the HDR scene. Why: the panel's renderer has no depth buffer and the three subset has no Group/geometry classes.

| Module (`dashboard/static/next/js/`) | Concern |
|---|---|
| `familiars/genome.js` | id + role → traits; shared by SVG and 3D |
| `familiars/svg.js`, `avatar.js` | list avatar, `creature(id, state, role)` |
| `gl/familiars/geo.js`, `body.js`, `glsl.js` | primitives and rig, creature design and poses, shaders |
| `gl/familiars/layer.js` | GPU objects, pose blending, depth pass and composite |
| `gl/creatures.js` | stage placement, entrance, leap, tags, streams |

## Exact commands
```bash
cd ~/agents/dashboard && node tests/test_next.js
node tools/shots.mjs ~/drop/<ticket>/after agents,org,overview
```

## Pitfalls (measured)
- Draw calls: 388 in V1 → 43 a frame for the whole Court with 15 creatures (2 per creature + 1 composite per pass).
- Headless Chromium uses SwiftShader: 3 fps and a blank 2560 stage at a 3.5 s wait under load 23. On the real GPU
  (`--use-angle=gl-egl --ignore-gpu-blocklist --enable-gpu`): 60 fps interacting, 30 fps settled at 1366.
- Projected body bounds are x −0.83…0.92, y −0.25…2.08 body units: the old tag box (±0.5 s, −0.72…+0.6 s) let tags
  cover the pad; `footprint` is now ±0.65 s, −0.88…+0.76 s.
- `avatar.js` lost its `params` export mid-port and the live page threw (the panel serves the working tree): change an
  export and its importers in the same write.
- New genome traits draw from the rng after the existing ones, or every creature changes.

## CEO: the Conductor (T1515-V4, 2026-11-10)
The orchestrator's animal form: one fixed, hand-built creature, not a genome draw. "Conductor" is the module name only;
every label on screen shows the orchestrator's display name (owner, 2026-11-10).
- Parts: floor-length navy coat with coral lining and 5 hem scallops, stand-up collar, gold spark clasp, cream head with
  navy cap, half-lid gold eyes, two ear tufts, coral spark-halo (ring + 8 spokes), ledger arm, conducting arm, hip lantern,
  3-bone tail with the lamp, and one mote per running agent (12 drawn at most) with mint threads while working.
- Palette: navy `#2a3466` / `#1d2340`, coral `#D97757`, cream `#f3e9dc`, gold `#e2b04a`, mint threads, red only for "needs you".
  Coral is the CEO's alone: `HUES` holds 238 where 24 was (same length, so every other creature keeps its hue slot).
- Files: `gl/familiars/ceo.js` (`build()` → `update(t, w, live)`, `BONES = 50`), `gl/familiars/ceo-motes.js`
  (`attach(rig, anchors)` → `sync(list, mesh)`, `step(...)`), `familiars/ceo-svg.js` (`ceoSvg(state, {motes, lamp})`).
  `creature(id, state, "ceo", opts)` and `layer.js` role `"ceo"` pick them; `live = {motes: [{id, hue}], lamp, failing}`.
- Measured (Iris Xe, 1366×768, Court with 13 creatures + the CEO): 43 draws a frame, 59.8 fps; the CEO is 2 draws,
  7940 vertices, 11744 triangles, 50 bones, motes and threads included.
- Pitfalls (measured): motes and threads as separate meshes would add 24 draws, so they are bones of the one mesh and a
  hidden mote has scale 0; a mote's hue is repainted in `aCol`/`aShade`, so the caller must set `needsUpdate` when
  `update` returns `recolor`; the shader's bone array is sized per creature (`body(50)` here, `body(28)` for the rest);
  24 live canvases on one page fall to 24 fps at 2560, so lists use the SVG twin and pass motes only from 48 px up;
  the stage scissor (x ±1.2 size, y −1.2…+1.6 size) bounds the mote rings (radius 1.3 units round y 2.2).
- Model sheet, 5 poses video, perf: `~/drop/T1515-V4/` (`index.html`, `poses.mp4`, `perf.json`, `before/`, `after/`).

## Links
- Code: `~/agents/dashboard/static/next/js/familiars/`, `.../gl/familiars/`, `.../gl/creatures.js`
- Skill and kit: `~/.claude/skills/familiars-style/`
- Tests: `~/agents/dashboard/tests/test_next.js`
- Design / results: `~/drop/T1515-V1/PICK.md`, `~/drop/T1515-V2/after/`, `~/agent-work/research/2026-11-09/T1515/PLAN.md`
