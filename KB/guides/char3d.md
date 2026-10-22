# 3D character by code: spec -> rigged, animated, rendered, QA'd character + glTF (char3d)

Ticket: T1032 · Last verified: 2026-10-20 by `tests/export.test.sh` (MPFB + Rigify fixture: glTF 0 errors / 0 warnings, 4 clips, 91 morph targets, 9-16.5 MB) and the six T1032 research probes

## When to use
A 3D character (body, face, hair, garments, props, rig, clips, Full HD renders, glTF) built headless from a JSON spec in Blender 5.0.1; skill /char3d. Not for pixel sprites (/pixel-avatar), game integration (/gamedev) or plain 3D shots without a character (/motion-video).

## The path we took
- Exists: MPFB 2 (CC0 hm08 body, ARKit-52 `faceunits01`, `visemes02`), Rigify (bundled), Blender Cloth, glTF-Validator, motion-video's EEVEE/encode conventions, T702 `gait()` motion design. Chosen: MPFB body/face + Rigify + code for garments, hair, props, motion, springs; EEVEE renders. Why: MPFB gives a quad, rigged body with 92 working face shapes in ~13 s, all CC0; a face from zero is weeks.
- Pipeline of one-module stages over a blackboard `build.json`: body -> face -> hair -> garments -> props -> rig -> facerig -> motion -> secondary -> lookdev -> export; then render (+ encode) and qa (bake in Blender, judge in numpy). Each command is its own `heavy` process; renders hold the T1032 render lock.
- A new character is a new spec (`specs/schema.json`, `char3d/1`); Grok and Luna fit the same enums (`T1032/GROK-LUNA.md`).

## Exact commands
```bash
C=~/.claude/skills/char3d/scripts/char3d; S=~/.claude/skills/char3d/specs/darksaddler.json; O=~/agent-work/char3d/darksaddler
$C build $S --out $O --draft                    # .blend + .glb + build.json
$C render $S --out $O --draft --shots closeup --max-frames 12
$C render $S --out $O                           # finals 1920x1080 -> $O/renders/*.mp4|jpg
$C qa $S --out $O                               # $O/qa.json, exit 1 on a failed check
gltf_validator -o $O/darksaddler.glb            # 0 errors, 0 warnings
~/.claude/skills/char3d/tests/smoke.test.sh; ~/.claude/skills/char3d/tests/export.test.sh
```

## Pitfalls (measured)
- MPFB face packs missing -> `load_targets` returns silently with 0 keys: assert 92 shape keys. Rigify needs `addon_utils.enable('rigify')` first.
- Bone heat fails or weights the toe to the spine (mesh 55 mm under ground): analytic capsule weights (min z -0.02 mm). `IK_Stretch` defaults to 1.0: set 0; bake IK every frame (0.13 mm drift vs 64-108 mm with sparse Bezier keys).
- Blender 5.0: `action.fcurves` is gone (channelbag API); pose-bone `.location` is bone-local; only simple-expression drivers run headless.
- EEVEE renders a refracting cornea black: Fresnel gloss / blended cornea. The distro Blender has no OIDN: Cycles finals need the official tarball; EEVEE 1080p 32 spp = 6.9 s wide, 10.7 s close-up; timings double at load 13-22.
- Garment drape never settles with partly pinned sleeves or garment-layer colliders (17-49 mm a frame at 180 frames): pin sleeves, collide with the body only, refit layers (0.83 mm at 61 frames).
- Cloth never loops by itself (1.9-8.8 cm seam): 8-frame body-local crossfade. Springs loop exactly at zeta 0.7 + 3 pre-roll periods.
- glTF: `export_apply` kills shape keys; `ACTIONS` mode drops the face animation of all but the active clip; skinned meshes under the armature give `NODE_SKINNED_MESH_NON_ROOT`; morph normals add 11 MB (+73 %); hair curves export as empty nodes. `stages/export.py` handles each (baked stand-ins, one NLA track per clip, unparent for the write, morph normals off, `<id>.cards` meshes).
- Cornea catchlight: a 2.5 % Fresnel cornea under a 0.25 m key peaks at luma 0.85 at 960x540 (AgX, 2-3 px), 0-1 px over 0.93; a specular-only eye light (`diffuse_factor` 0, 20 W, 0.1 m disc by the camera) gives 0.99 and 9-13 px. Iris albedo above ~0.15 reads pale grey at luma 0.6 (sclera 0.78); 0.5x the iris colour gives 0.43.
- Blink keyed but never seen (2026-10-21): motion looks up `face.controls['blink.L']` while facerig published only ARKit names, so the eyeBlink keys were overridden by their drivers (lid_visible 11.6-14.7 % at every blink peak); facerig now also publishes `blink.L/R` -> 0.0 %.
- A texture set whose first part is a KEEP kind (hair lashes, cards) got that unswapped variant as its primary; Blender drops 0-user materials on save, so QA saw "no material loads its maps" (face, hair). Primary = first non-KEEP material; hair cards load groom maps made from the strand atlas.
- Pores at detail scale 900 per UV unit on a 4K body (head 56 px/cm) = 0.08 cm tiles, aliased to nothing: scale 70 (1.1 cm tile, ~0.8 mm pore spacing).
- Garment/prop UV packs are not reproducible between builds (robe UV max diff 0.98 with identical topology; body and face sets identical): never reuse baked maps from another build without copying its UVs.
- Full list per stage: SKILL.md "Pitfalls".

## Links
- Code: `~/agents/skills/char3d/` (`scripts/char3d`, `scripts/c3d/stages/*.py`, `specs/`), credits `CREDITS.md`
- Tests: `tests/smoke.test.sh` (~5 s), `tests/export.test.sh` (~60 s, MPFB fixture `T1032/export-docs/fixture/` or `CHAR3D_EXPORT_FIXTURE`), `tests/<lane>.test.sh`
- Design / results: `~/agent-work/research/2026-10-20/T1032/ARCH.md`, `.../T1032/research/*.md`, previews `~/drop/T1032/index.html`
