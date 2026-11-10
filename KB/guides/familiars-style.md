# Familiars: the agent creature look (3D on the stage, SVG in lists)

Ticket: T1515-V2, T1515-V3, T1515-V4, T1515-V5, T1515-P21 · Last verified: 2026-11-10 by `node tests/test_next.js`, `tools/shots.mjs` at 5 widths, draw-call and fps count on the iGPU

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
- V5 polish (2026-11-10, measured): the Court box stretched to the tall side pane's grid row, so at 1366x768 the eye sat
  below the fold; `court.js` `fold(b)` clamps the fit box to the visible height (min 240 px). Lids are domes in the face cream (a darker lid read as a swollen bag), 0.62 eye radii deep so the iris never pokes through (0.53 did), with an
  ink half-torus on a bone at 0.22 eye radii; in the SVG a stroked sclera read as glasses, so the eye has no ring, only the lid line.
  The muzzle is a flush patch (z scale 0.03): a 0.09 deep sphere read as dough. Error keeps the normal colours (`tint: 0`). Parts that must not dim in sleep (halo ring,
  lamp) use `flag: 0`; sleep dims the rest by 0.14, not 0.42. Motes ride 2 tilted rings (r 1.18 / 1.0, tilt 0.5 / -0.42)
  round y 1.12; a thread is hidden when its hand-to-mote segment passes within 0.5 units of the face (25 of 100 in the SVG).
  SVG lamp r 10 at (86,32): fine = coral, talking = lighter + ring, needs you = red with "!" and 3 rays, readable at 48 px.
  A model sheet paints its grid as stills (one view per frame, then stops): 60.3 fps at 400-2560 where 24 live canvases gave 24.
  Court draws are 2 a creature + 15: 51 with 18 creatures, 43 with 14. Evidence: `~/drop/T1515-V5/` (`sheet.png`, `perf.json`).

## Manager gear (T1515-P21, 2026-11-10)
Role `manager` (the Discord project managers in `org.json`): one small accessory, a violet bow tie at the chest
(SVG `<g class="gear-manager">`, 3D two cones + a knot on the hip at `0.33 * W` forward); never the PO's headset or the
worker's hard hat. Every role's SVG gear sits in `<g class="gear-<role>">`, so a test can tell roles apart.
- Pitfall: a role missing from `ROLES` falls back to `worker`; managers wore hard hats until `manager` was added.

## Lists that move (T1515-V3, 2026-11-10)
Org and Chat draw `familiars/alive.js` `familiar(id, state, role, messageId?)`: the SVG twin in a `.fam` box that
`static/css/familiars.css` animates. A new chat message makes its sender talk for 2 s (`familiars/talk.js` `heard`,
`talking`, `watch`); a screen with no chat feed hears through `familiars/ear.js` `listen(on)`.
- Measured (Iris Xe, 1366x768): 60.2 fps at rest and mid-talk, 1 WebGL context (the stage), 21 animations on Org, 30 on Chat.
- Pitfall: animating the `<svg>` and its parts every frame took the main thread from 6 % to 14 % at rest and 34 % mid-talk
  on Chat (wall time); the box now moves on the
  compositor and blink / working ring change in steps: about +4 points on Org, +6 on Chat over a still page.
- Pitfall: class `.lb` is the fullscreen viewer in `eye.css` (fixed, opacity 0); a label with that class vanished and
  swallowed clicks. Grep `eye.css` before naming a class.
- Pitfall: under load 8 to 16 one 5 s CPU sample swings 2x; compare on/off in the same run, 10 s windows, 3 rounds.
- Test hooks: `.fam.talking`, `svg.cr.talking`, `data-fam="<id>"`; hidden pause via `html.away`.

## Links
- Code: `~/agents/dashboard/static/next/js/familiars/`, `.../gl/familiars/`, `.../gl/creatures.js`
- Skill and kit: `~/.claude/skills/familiars-style/`
- Tests: `~/agents/dashboard/tests/test_next.js`
- Design / results: `~/drop/T1515-V1/PICK.md`, `~/drop/T1515-V2/after/`, `~/agent-work/research/2026-11-09/T1515/PLAN.md`
