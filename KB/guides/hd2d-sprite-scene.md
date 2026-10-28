# HD-2D scene: pixel-art sprites in a lit 3D diorama (Octopath / FF Brave Exvius look), made with code

Ticket: T1414 · Last verified: 2026-10-28 by a 1080p 4 s loop render (Tiny Epic Narrator, sarcophagus chamber, Gamelyn v2 detail)

## When to use
"2D HD", "HD-2D", "Octopath style", "FF Resonance / Brave Exvius style": small crisp pixel sprites standing in a 3D
set with DOF, bloom and volumetric light. Not for flat pixel maps (T703), nor painted cards (`arte/gamelyn` paper theatre).

## The path we took
- Sprites: the /pixel-avatar SDF tracer (`core.py`, `rig.py`, `hands.py`, vendored into the project's `arte/hd2d/pixel/`),
  one module per character with `FRAMES`, `pose(f)`, `build(f)`; `sprite.py` writes albedo, emissive mask and normal map per frame
  at any yaw (3/4 battle view: yaw -0.6 facing left, 0.55 facing right).
- Set: one bpy script (`cripta_hd2d.py`), self-contained (no ~/.claude import, so the repo builds anywhere).
  Each sprite frame is a vertical plane, image node `Closest`, alpha DITHERED (casts shadows); only one plane per sprite is
  `hide_render=False` per scene frame (keyed, CONSTANT): no image-sequence juggling.
- Pixel scale: plane metres per sprite px = PX * depth * (36 / lens) / 1920, so every sprite lands on the same 3.5 screen px grid.
- Look: procedural ashlar (Brick texture on two object axes + noise), emissive moon window as backlight, spot "god ray"
  with volume 7 through a fog cube (density 0.03), torch billboards with looping noise, tilt-shift = compositor band blur.
- Post: `dialogo.py` (Pillow) for the translucent dialogue box, `sonido.py` numpy ambience, ffmpeg loop x3.

## Exact commands
```bash
cd <repo>/arte/hd2d/pixel
python3 sprite.py gamelyn ../sprites/gamelyn --yaw -0.6 --sheet /tmp/g.png     # 8 frames in ~3 s
cd .. && blender -b --factory-startup -P cripta_hd2d.py -- sprites /tmp/s_ --size 540 --samples 16 --vtile 8 --vsamples 48 --rays 1 --stills 40
blender -b --factory-startup -P cripta_hd2d.py -- sprites frames/f_ --size 1080 --samples 20 --vtile 8 --vsamples 48 --rays 1
python3 dialogo.py frames frames_dlg
```

## Pitfalls (measured)
- Render cost is GPU-bound: 1080p at 40 samples, vtile 4, 96 volume samples, 2 shadow rays = 80 s/frame; 16 samples,
  vtile 8, 48 volume samples, 1 ray = 20 s/frame with no visible loss. Cost is linear in samples (~1.2 s per sample).
- Scaling a plane without `transform_apply` leaves Object coordinates in local units: the brick texture became 2 giant
  bricks with a hard line across the floor.
- A plane rotated 90 deg on X is still flat in local XY: scale it (w, h, 1) and read Generated Y, not Z, or flames become bars.
- bmesh half-arch: after rotation (pi/2, 0, 0) local +Y is world +Z; delete `v.co.y < 0` to keep the top half.
- A low two-handed guard reads as a stub at 64 px: the blade must point at the enemy (sword dir (-0.45, 0.85, 0.3) at yaw -0.6),
  a vertical blade covers the face.
- EEVEE "Shadow buffer full (2377/2048)" with ~10 shadowed lights: `eevee.shadow_pool_size = "1024"`.
- Blender world volume did not show light shafts; a fog cube with Principled Volume did.
- Detail upgrade without a bigger hero (T1414 v2): raise the module's `SCALE` (1.12 -> 1.6, `sprite.py` reads it), widen the
  cell (128 -> 176) and shrink the plane pixel by the same ratio (`HERO_PX = 1.12 / 1.6`): 61 -> 87 px tall, same screen size.
- Gold bands on every plate read as stripes, not trim: one band per piece, plus 1 px rivets (`m.dots`) and stacked
  hollow lames (ellipsoid minus an offset ellipsoid) for pauldrons and tassets. 8-9 step ramps give the specular room.
- "Match the reference's quality" is not "copy its design": the owner rejected a horned-helmet redesign; keep the character's own look.

## Links
- Code: RunarStudio/Tiny_Epic_Narrator `arte/hd2d/` (PR #3 branch `liaison/gamelyn-dibujado`)
- Skills: /pixel-avatar (sprite tracer), /code-hero-render (EEVEE look values)
