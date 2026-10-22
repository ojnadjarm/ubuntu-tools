---
name: char3d
description: AAA game-ready 3D characters by code in headless Blender 5.0.1 - spec JSON -> body (MPFB CC0), face (eyes, lids, ARKit-52, visemes), hair + cards, garments, props, high-poly detail, retopo, UV sets, baked PBR (albedo, normal, ORM, emissive), Rigify rig, motion clips, secondary (cloth, springs), lookdev, Full HD renders, glTF + LODs, automatic QA. Use for "3D character", "char3d", "DarkSaddler 3D", "game character", "rig a character", "turntable", "bake textures", "LOD", "lip sync 3D", "foot sliding". Not for pixel sprites (/pixel-avatar) or games (/gamedev).
---

Triggers: MPFB, MakeHuman, Rigify, ARKit blendshapes, visemes, eyelid blink, beard, hair cards, robe cloth, spring bones, high-poly bake, normal map, ORM, texel density, LOD0/LOD1/LOD2, gltfpack, EEVEE character render, glTF morph targets, mocap cleanup, CMU BVH, character QA.

# char3d: one spec in, a AAA game-ready, rigged, animated, rendered and QA'd character out

Bar (T1032 brief): Diablo IV / Baldur's Gate 3 / Elden Ring / WoW tier. Realistic adult anatomy (7.5-8 heads), real material detail (weave, folds, trim wear, pores, strands or cards), LOD0 30-80k tris + LOD1/LOD2, 2-4K baked sets, game skeleton (<= 4 influences), glTF/FBX. No primitive shapes, no toy proportions, no storybook or cel looks.

Guide: `guide char3d` (`~/agents/KB/guides/char3d.md`). Architecture, interfaces, render budget: `~/agent-work/research/2026-10-20/T1032/ARCH.md`; research: `.../T1032/research/{modeling,face,rig-motion,secondary,lookdev,aaa-asset,qa}.md`. Asset licences: `CREDITS.md` (CC0 or CC-BY only; add a row for every new asset).

## Workflow
```bash
C=~/.claude/skills/char3d/scripts/char3d
$C build  SPEC [--out DIR] [--draft] [--until STAGE]          # DIR/<id>.blend, <id>.glb, <id>_LOD1..n.glb, textures/, build.json
$C render SPEC [--out DIR] [--draft] [--shots a,b] [--max-frames N] [--keep-frames]  # DIR/renders/<shot>.mp4|jpg
$C qa     SPEC [--out DIR]                                    # DIR/qa.json, exit 1 on any failed check
gltf_validator -o DIR/<id>.glb                                # glTF gate: 0 errors, 0 warnings
```
1. Write the spec: copy `specs/darksaddler.json`, validate with `specs/schema.json` (unknown keys fail, exit 2). New character = new spec, no code (see `T1032/GROK-LUNA.md`).
2. Iterate with `--draft` (960x540, 16 spp) and one shot (`--shots closeup --max-frames 12`); finals without `--draft` (1920x1080).
3. `build` runs body -> face -> hair -> garments -> props -> materials -> detail -> retopo -> uv -> bake -> texture -> haircards -> rig -> facerig -> motion -> lookdev -> secondary -> export -> lod (one module each in `scripts/c3d/stages/`); `--until rig` stops early. `build.json` carries state, so `render` and `qa` rerun alone. Stages still on a stand-in report `stub: true` and a `todo` in `build.json.stages`.
4. Every Blender/encode run goes through `heavy run --ticket $CHAR3D_TICKET`; renders also hold `flock $CHAR3D_LOCK` (one render at a time).
5. Read `qa.json` (`summary.failed`), fix the stage that owns the failing check, rebuild. Tests: `tests/smoke.test.sh` (~15 s), `tests/export.test.sh` (~60 s), one `tests/<lane>.test.sh` per stage.

## Knobs
| Where | Knob | Values / default |
|---|---|---|
| env | `CHAR3D_TICKET`, `CHAR3D_LOCK`, `CHAR3D_BLENDER`, `CHAR3D_BLENDER_RES` | T1032, `T1032/render.lock`, `blender`, `~/.local/share/char3d/blender-res` (MPFB sandbox; the owner's `~/.config/blender` stays untouched) |
| `body` | `base`, `height_m`, `macros`, `targets`, `skin`, `hide_under` | `mpfb` or `placeholder`; MPFB macros (elder: gender 1, age 0.95, height 0.7, muscle 0.35) |
| `face` | `eyes.cornea`, `lids`, `brows.style`, `shape_packs`, `expressions`, `visemes`, `gaze` | `fresnel_gloss`; `bones`; `faceunits01` + `visemes02`; expressions/visemes = ARKit weight dicts; gaze saccades/s, blinks/s |
| `hair[]` | `kind`, `render`, `strands`, `length_m`, `width_m` | `curves` (render) also builds `<id>.cards` (glTF); `cards` only |
| `garments[]` | `kind`, `profile`, `params`, `trim`, `decals`, `layer` | profile `[[r, z], ...]`; robe params folds/fold_depth_m/gathers/gather_depth_m/cinch/blouse_m; trim edges hem/cuffs/front/collar/band/rim; decal kind `scroll` (regions front_border, hem_band; wave_m, thread_m) |
| `props[]` | `kind`, `attach`, `length_m`, `grip`, `parts[]` | one object per part (shaft, crystal, claw, knob, binding, ferrule, ...) |
| `detail` | `subdiv` {draft, final}, `layers[]` {kind, parts, depth_m, scale} | high-poly twin `<part>.high` per part; kinds folds, weave, embroidery, seams, stitches, wear, pores, wrinkles, carve, grain, facets |
| `retopo` | `default`, `parts`, `ratio` | `construction` (the code-built low is the game mesh), `decimate`, `quadriflow`, `instant_meshes` (SDF props) |
| `uv` | `sets[]` {id, size, parts, texel_px_cm}, `default_set`, `margin_px` | body + robe 4096, hat/gear/staff/hair/face 2048; part ids match by prefix (`staff` = `staff.*`) |
| `bake` | `mode`, `maps`, `size` {draft}, `samples`, `cage_m` | `cycles` selected-to-active from `<part>.high`; `flat` = constant stand-in maps |
| `textures` | `use_baked`, `paint`, `detail_normals[]` | baked set material swapped on once the bake is real; `gradient` = painterly albedo from AO/curvature/height |
| `asset` | `lods`, `skeleton`, `max_influences` | [0.5, 0.25] via gltfpack, `game` (DEF bones only), 4 |
| `rig` | `generator`, `metarig`, `ik_stretch`, `weights` | `rigify`, `human`, 0, `capsule` (body) / `transfer` (garments) |
| `motion` | `fps`, `clips[]` (`idle`, `walk` + `gait`, `talk` + `line`, `beats`, `mocap` + `source`) | 30 fps (24 fps fails the jitter gate) |
| `secondary` | `cloth`, `springs`, `pulses` | cloth quality 5, springs zeta 0.65-0.75 |
| `look` | `name`, `engine`, `view`, `samples`, `size`, `raytrace`; optional `hdri`, `hdri_strength`, `contrast` override the preset (it owns rig, HDRI, AgX look, grade); `light_rig` is accepted, the preset's rig is used | `grim` (Diablo IV), `painterly` (WoW / Arcane, stylized PBR), `cinematic` (BG3 reveal); EEVEE; samples draft 16 / final 32, close-ups 64 |
| `renders[]` | `kind`, `clip`, `seconds`/`frames`, `lens_mm`, `fstop`, `target`, `expression` | turntable, clip, closeup (85 mm), still |
| `export` | `gltf`, `fbx`, `morphs`, `actions`, `hair` | true, true, true, true, `cards`; `MORPH_NORMALS` constant in `stages/export.py` (off) |
| `qa.thresholds` | motion (plant drift, penetration, jitter, loop seam, lids, staff contact = float/penetration, layer_poke_mm, loop_pop_ratio; grip and clip ends default to jitter and loop seam), render (exposure, noise, mp4 MB), asset (LOD0 tris, LOD ratios, influences, quads, UV, texel density, albedo range), glTF errors | a check runs only when its threshold is in the spec |

## Pitfalls (measured, T1032, Blender 5.0.1 distro build, 16 threads, Iris Xe)
**Body and face**
- MPFB face targets need the `faceunits01` + `visemes02` packs; without them `load_targets` returns silently (1.05 s, 0 keys): assert the shape-key count (92 with both packs, 9.6 s, cache the .blend).
- MPFB rigify rigs need `addon_utils.enable('rigify')` first (else NotImplementedError); `rigify_generate` of `human` = 706-930 bones in 1-5 s, `basic_human` 222 bones in 0.1-0.2 s.
- A linear shape-key blink cuts into the eyeball (lid 5 % off the eye, 80 deg travel -> 19.6 % deep mid-blink): rotate lid bones about the eye centre.
- EEVEE renders a refracting (Transmission) cornea black, raytracing on or off: use a Fresnel gloss / blended cornea (Alpha 0.08, Specular IOR Level 1, `BLENDED`) and a concave iris set inside the eyeball. UV-sphere eyeballs show the pole seam: point the pole forward.
- `Grid to Mesh` threshold defaults to 0.1 (0 verts on an SDF); `SDF Grid Fillet` gave 0 verts: use Offset(+r) then Offset(-r). SDF/voxel meshes have no UVs or loops: props only, never deforming parts.

**Rig and motion**
- Bone heat fails on code-built multi-shell bodies (100 % unweighted) or "succeeds" wrong on a proxy (toe on DEF-spine, mesh 55 mm under ground): use analytic capsule weights (0.006-0.069 s, min z -0.02 mm), transfer to garments.
- Rigify `IK_Stretch` defaults to 1.0: set 0, and keep every stance within 0.97 x leg length (0.5 m stride on a 0.99 m leg drifted 48 mm).
- Foot sliding is keying: bake IK targets every frame (0.13 mm drift); 14 sparse Bezier keys slid 64-108 mm.
- Pose-bone `.location` is bone-local (feet went sideways / 52 cm underground): convert with `bone.matrix_local.to_3x3().inverted()`; bake world positions after `frame_set`, never read F-curves.
- Blender 5.0 has no `action.fcurves`: use `bpy_extras.anim_utils.action_get_channelbag_for_slot(action, slot).fcurves`.
- CMU mocap contacts slide 9-29 mm raw: lock the ball of the foot (IK chain 3, smoothstep 3 frames) -> 0.0 mm; ankle-only locks leave 9-13 mm and pop. `import_anim.bvh` loses `global_scale` after `read_factory_settings`: call `io_anim_bvh.import_bvh.load` directly.

**Secondary**
- Surface Deform bind fails on the robe (`Target contains concave polygons`, even after split_concave): the robe stayed skin-only while its trims and the inner robe rode the cloth; secondary falls back to a Mesh Cache (overwrite) on the garment itself.
- Garment drape (2026-10-20): partly pinned bell sleeves and one-sided layer colliders never settle (17-49 mm a frame after 180 frames): pin sleeves, drape against the body only, refit layers after; settles in 60-71 frames (0.83 mm last frame).
- Cloth never converges to a loop (1.9-8.8 cm per-period error): take a late cycle and crossfade the seam over 8 frames in body-local space. Self-collision at 8k verts costs 9x (2.2 s/frame): sim a 2-5k cage, collide with a <= 1k proxy.
- Spring chains loop exactly with zeta 0.65-0.75 and 3 periods of pre-roll (<= 1e-5 rad); zeta 0.39 needs 10 periods.
- Drivers: only simple expressions run in `-b --factory-startup` (autoexec off); a driver on an unassigned material never updates.

**Lookdev and render**
- The distro Blender has no OpenImageDenoise or OSL: Cycles finals need the official tarball; EEVEE is the default (1080p 32 spp 6.9 s wide, 10.7 s close-up; 13x cheaper than Cycles CPU).
- EEVEE timings double at load 13-22 (parallel lanes): measure at load <= 3. SSS speckles at 32 spp in close-ups: 64 spp.
- Particle beards cost +5.4 s/frame and spray out ungroomed; 5.0 curves have 15x more geometry by default: keep the curve `resolution` low.
- AgX hides clipping (+4 EV = 0.07 % clipped): pair clip % with mean/p99 luma. The RGBA alpha includes the ground: mask the subject by projection.

**AAA asset (detail, retopo, UV, bake, LOD)**
- 4K set = 14.2M-tri high, ~329 s of bakes and 15.9 GB RSS per part: one bake at a time under the render lock; iterate at 2K (63 s per set) or 1K (15 s).
- QuadriFlow returns CANCELLED ("needs to be manifold") on voxel output even with 0 non-manifold edges: `remove_doubles(1e-5)` + `dissolve_degenerate`, else Instant Meshes `-d -b -f N/4` (pure-quad mode subdivides once).
- Weave at scale 400 aliases into moire in a unique 4K bake: weave and pores go in tiling detail normals, never in the unique bake.
- A tube robe baked a normal map with mean R 0.70 (0.5 expected): gate every bake on a flat-plane test (mean R/G 0.5 +- 0.02).
- The distro build lacks Draco (`libextern_draco.so`) and the glTF exporter writes no `MSFT_lod`: LODs are separate `<id>_LOD<n>.glb` files from gltfpack (`-si`), validated one by one.
- glTF export keeps 4 influences per vertex and drops the rest silently: limit + normalise in `rig`, check in QA.
- `BVHTree.overlap` misses coplanar UV triangles: use `bpy.ops.uv.select_overlap` (works headless). `Image.pixels.foreach_set` needs float32.

**QA**
- MAD jitter thresholds flag every swing frame next to a plant (53/120): use the Savitzky-Golay residual in mm; 24 fps fast motion leaves 4.3 mm on clean curves, 30 fps 1.8 mm.
- `BVHTree.overlap(self)` returns each pair twice and already skips neighbours: divide by 2.
- Garment depth on the masked (open) body: a nearest hit on a crease or mask edge passes a one-face 0.9 straight test from 4.8 cm outside (mantle 47.7 mm, false): judge along the pseudo-normal (sum of the normals of every face touching the hit) -> 0 mm.
- Layer order needs its own check (`layer_poke`, base surfaces, Solidify off): self_x and garment_depth never saw the inner robe 27 mm through the robe or the robe 35 mm through the mantle.
- A looping walk shot of 120 frames on a 72-frame clip with a camera-only follow wrapped at 9.84 vs 0.96 median step (10.2x, `video_loop`): render whole cycles and carry the whole set (lights, ground pool) with the root.
- Clip `impacts`, `blinks`, `staff_plants` are scene frames (start + pose index); one-shot ends and impacts are judged with one-sided SG fits, never exempted.
- Bone heat warns but `--python-exit-code 1` does not catch it: gate on unweighted count and min z.

**Export (glTF)**
- Hair curves export as an empty node: the hair stage makes a `<id>.cards` mesh part; export skips curves.
- `export_apply` drops every shape key: export never applies; a shape-key-free mesh with modifiers (solidify, subsurf) gets a baked stand-in instead, with armature and simulation modifiers (cloth, surface deform) left off.
- `ACTIONS` mode exports only the active shape-key action, so 3 of 4 clips lose their face: export pushes one NLA track per clip (named by clip id) on the rig and on each shape-key block (the Action's KEY slot) and uses `NLA_TRACKS`: exactly one animation per clip.
- A skinned mesh parented to the armature is a `NODE_SKINNED_MESH_NON_ROOT` warning (8 on MPFB): export unparents skinned meshes for the write; bone-parented props stay children of their bone.
- Morph normals add 11 MB (+73 %) on 91 MPFB targets (26.9 vs 16.5 MB with textures): off by default. Normal-mapped skin without tangents warns `MESH_PRIMITIVE_GENERATED_TANGENT_SPACE`: tangents on.
- `export_def_bones` keeps 182 of 930 Rigify bones; sampling 4 clips x 182 bones costs ~20-30 s of the export (3.5 s without animation).
