# HD-2D scene: pixel-art sprites in a lit 3D diorama (Octopath / FF Brave Exvius look), made with code

Ticket: T1414 · Last verified: 2026-10-28 by a 1080p 4 s loop render (Tiny Epic Narrator, sarcophagus chamber, Gamelyn v4 low guard, shoulder cape, blue steel)

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
- A face built as a skin sphere with 2x2 eye stamps and a mouth line reads "circle with two dots and a line" (owner, v2).
  FFBE heads (studied from a sheet in `dsxragnarok/ffbetool` test fixtures; spriters-resource and fandom images sit behind
  Cloudflare, curl and headless Chrome both get the challenge page): skin is only the lower ~40% of the head, bangs reach
  the eye line, each eye is taller than wide (dark lash cap, 2 px coloured iris, white glint), V chin with a dark tip, no nose.
  Recipe that worked: sphere + cone jaw to a point, hair cap cut away below the brow at the front (`inter` with
  min(brow - y, z - z0)), 5 bang cones and 2 side locks as hard unions (group None: the outline pass draws the separations),
  a dark line per lock on its shadow side and a light one near the root, a separate flat `glint` ramp for the halo band,
  eyes as `pat()` stamps (near eye 5x5, far eye 4x4). Lift the head 0.5 so the chin clears the gorget.
- A sword as one round cone plus a white line reads as a light-saber stick: a flat diamond-section SDF (taper, then a
  6-unit point) with a darker fuller and light edges as texture bands; in the scene the emissive bloom eats most of it.
- Alternative poses as tiny modules that import the hero and replace `gamelyn.pose` (`build` reads the module global):
  `sprite.py gamelyn_estocada ...`; a raised guard by the head crosses the face again, a level thrust does not.
- A cape cone started at the neck with a round cap of radius 8 reaches head height: from behind it "hangs from the head" (owner, v3).
  Start it 3 units under the neck, top radius 6.6, and clip it flat at `neck - 1.4` (hidden under gorget and pauldrons); add clasps.
- An emissive 'ice' blade blooms to white in the scene: a blue steel ramp with `kind: metal` (bias 0.8, fuller -1.8, edges 1.6)
  keeps it bluish and detailed; runes as dots with emission 0.5.
- FFBE battle idles read by a wide low base (feet ~13 units apart along the facing, crouch 1.2, lean 2.4) and a blade that leaves
  the silhouette toward the enemy (dir (-0.66, 0.62, 0.42) at yaw -0.6, hilt at the waist); a hilt behind the head hides both hands.
- "Match the reference's quality" is not "copy its design": the owner rejected a horned-helmet redesign; keep the character's own look.

## Links
- Code: RunarStudio/Tiny_Epic_Narrator `arte/hd2d/` (PR #3 branch `liaison/gamelyn-dibujado`)
- Skills: /pixel-avatar (sprite tracer), /code-hero-render (EEVEE look values)
