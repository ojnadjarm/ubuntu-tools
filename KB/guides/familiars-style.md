# Familiars: the agent creature look (3D on the stage, SVG in lists)

Ticket: T1515-V2 · Last verified: 2026-11-09 by `node tests/test_next.js`, `tools/shots.mjs` at 5 widths, draw-call and fps count on the iGPU

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

## Links
- Code: `~/agents/dashboard/static/next/js/familiars/`, `.../gl/familiars/`, `.../gl/creatures.js`
- Skill and kit: `~/.claude/skills/familiars-style/`
- Tests: `~/agents/dashboard/tests/test_next.js`
- Design / results: `~/drop/T1515-V1/PICK.md`, `~/drop/T1515-V2/after/`, `~/agent-work/research/2026-11-09/T1515/PLAN.md`
