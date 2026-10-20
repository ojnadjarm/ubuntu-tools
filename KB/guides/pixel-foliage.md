# Pixel-art foliage: trees, shrubs, ferns, grass, glowing flora (day + night, Godot wind atlases)

Ticket: T715 (rebuilt from zero), before it T710, T713 · Last verified: 2026-10-20 (T846: module list, 12 `plants.PRESETS`, 9 s x 12 fps = 108, script `--help`, paths) and by `tests/selftest.sh` (12 presets, deterministic, 0 warped px, 1 px steps, seamless loop), `legacy/tests/selftest.sh` and pixel-scene's selftest through the `species.py` shim, T707 scene copy rendered in Godot 4.7 (still + 9 s loop), resp-check 5/5

## When to use
Use this when a map or scene needs vegetation sprites: trees, bushes, ferns, tufts, flora with sway, day/night versions, normal maps and Godot scenes. T709's `/pixel-scene` skill calls it (through the legacy shim until it switches). For characters use `/pixel-avatar`. For whole maps and tiles use `/pixel-scene`.

## The T715 method (current)
- Why: the owner rejected T710/T713 ("hot air animation", "I don't see leaf"). Old wind moved every texel by its own floored offset (flutter at 23 cycles/loop), so neighbours switched at different moments: shimmer. Old leaves were 3-5 px glyphs, ~400 per oak, that merged into texture at x3.
- Survey: Slynyrd Pixelblog 33 (leaf balls step 1 px, one wave per loop, ~0.2 s/frame, falling leaves as 2x2 sprites), Medeiros, 80.lv Voronoi clusters, AGS layered leaves; no headless library. Chosen: own Python rig generator, rigid pieces, baked atlases. Detail: `~/agent-work/research/2026-10-20/T715/RESEARCH.md`, `ARCH.md`.
- Modules: `palette.py`, `leafart.py` (leaf stamps: lit half, shaded half, dark lower/right edge, midrib, stem), `rig.py` (Pose, Piece, Rig, Sprite painter, night rim), `plants.py` (12 presets), `motion.py` (gusts, springs, quantise, 1 px clamp), `render.py` (z-order blit), `checks.py` (shape identity, motion stats, flicker), `export.py` (atlases, json, tscn), `build.py`, `preview.py`, `sheet.py`.
- Data flow: `plants.PRESETS[n](seed, size) -> Rig -> motion.track -> render.frame per tick (108 at 12 fps) -> checks -> export`. Godot picks `seq[floor((t + time_offset - x / speed) * fps) mod 108]` from the atlas (`templates/foliage_anim.gd`).
- Results: 0 warped px on all 12 presets; flip-back share (A->B->A pixel flicker) T713 0.218 -> T715 0.023 day and night; oak ~400 glyphs -> 201 leaves of 8x5 px; rest pose 27-71% of ticks; 6 critique rounds (`rounds/CRITIQUE.md`).
- Compatibility: `scripts/species.py` only re-exports the legacy `PRESETS` from `legacy/scripts`, so pixel-scene's `foliage_bridge` and maps built on it (T714) keep the T713 sway-map API until they switch to `plants`.

## Exact commands
```bash
S=~/.claude/skills/pixel-foliage/scripts
python3 $S/preview.py /tmp/b.png oak fern --seed 4          # x1 | x3 | x8 crop, day + night, 6 wind ticks (1.1 s)
python3 $S/build.py <project>/foliage all --seed 2 --res res://foliage/   # all 12: 15 s
python3 $S/sheet.py ~/drop/<T>                              # boards x3/x8 day+night + 9 s wind MP4
~/.claude/skills/pixel-foliage/tests/selftest.sh            # 29 s, prints SELFTEST ok 12 presets
~/.claude/skills/pixel-foliage/legacy/tests/selftest.sh     # old T713 code still works
```

## Pitfalls (measured, T715)
- "Hot air": any per-pixel UV displacement or warp shader (T710/T713 `foliage.gdshader`, `_w`/`_m` maps) makes foliage shimmer like heat haze at x3, however the field is tuned. Move whole pieces by whole pixels; `checks.shape_identity` must print 0 warped px.
- Invisible leaves: 3-5 px glyphs (~400 per oak) read as texture, not leaves, at x3. Use 7-9 px leaves with a lit half, a shaded half and a dark lower/right edge, ~200 per oak, painted bottom-up so each dark edge separates two leaves.
- warp_share and rigid_share did not separate old from new (0.762 vs 0.601; 0.011 vs 0.177, noisy). The flip-back share does (0.218 vs 0.023).
- Motion too small reads as still: clusters leaned 0->1 px and stayed (R1). Turbulence inside gusts, front at 120 px/s and hysteresis keep 0.6 give 0-1-2-3-2-1-0 swings.
- A parent cluster step plus a chain step in the same tick made 2 px jumps on the willow; `_one_px` clamps every periodic track to 1 px per tick.
- Night rim on every internal edge looked like neon (R1-R2, conifer tiers until R6): rim only on the closed silhouette (dilate 2, erode 2), top 55%, 60% strength, never on trunks or lower conifer tiers.
- Shrubs at amp 0.4 moved 1 px and read still (R2); amp 1.0, limb 0.8 give 2 px.
- Catalogue boards from tick 0 showed falling leaves on the ground; boards and stills use `export.rest_track`.
- Godot: relative paths in movie/still runs fail ("Can't save PNG"); pass `$PWD/out/...`.

## Legacy method (T710/T713, kept in `legacy/`)
### The T710 path
- Survey: T707 `foliage.py` (in-house, weak: busy dark zigzags, unreadable ferns). Slynyrd Pixelblog 44/15 (leaf-bundle method, value grouping, avoid noise). Aseprite Gentree (an editor plugin, not headless). There is no Python library for this. Chosen: rewrite on T707's sway-map contract using the Slynyrd bundle method.
- Modules: `palette.py` (14 ramps x 7 levels, day + night lists), `core.py` (`Canvas`: levels, ramp id, height, emissive, sway/phase, rim, ground shade; `crown()`, `stroke()`, `clean()`, `finish()`, export), `species.py` (12 presets + shared trunk/branches/blade/tuft), `build.py` (files + .tscn), `preview.py`, `sheet.py` (catalogue + MP4), `godot-check.sh`.
- Data flow: preset -> Canvas levels -> `finish()` (clean, outline, rim) -> `rgba('day'|'night')` palette lookup -> PNGs. The Godot shaders read only the PNGs.

### Leaves (T713)
- Survey: Slynyrd Pixelblog 15/44 (suggest leaves, group values), Sea of Stars and Eastward trees (leaf-shaped silhouettes, few bright single leaves over a grouped mass), Octopath HD-2D (strong lit top, dark core). No headless library paints leaf glyphs, so we built `leaves.py` on the T710 canvas.
- Method: each cluster is a fan of twigs from a hidden spur. Leaves sit alternately along every twig, and their glyph points along the twig (8 directions). Mass leaves are flat at their band level. 10-16% become accent leaves: one level up, with a lit edge and a cast shadow. A dark core shows through the gaps, with twigs and a few sky holes.
- Glyph sets in `leaves.GLYPHS`: `oak` (almond, lobed), `round` (bush, blossom clumps), `holly` (spiky), `willow` (blades), `broad` (hydrangea). Flowers: `cherry`, `floret`. The conifer uses needle sprays and the fern uses tapered leaflets (species.py).
- Resolution stays the same (oak 96x98 at size 1). A 3-5 px glyph is 9-15 screen px at x3, and a crown holds ~400 leaves. T709 already scales trees x1.25.

### Wind (T713)
- Survey: real wind comes in gust fronts that cross a field, with calm between them. Branches lag the trunk and leaves flutter faster (Habel 2009 tree animation, GPU Gems 3 ch. 6 "GPU-generated procedural wind"). Pixel games step whole sprites or clusters on a world-space wave. Chosen: a world-space field in the shader (`templates/wind.gdshaderinc`), mirrored in numpy (`scripts/wind.py`) for MP4s and metrics.
- Model: 3 gusts per loop with uneven spacing, strength, rise and fall. Fast attack, slow release, then a damped recoil past rest. Lag comes from the cluster phase plus `loose` x flex, so willow strand tips trail. Leaves flutter at 23 cycles per loop, gated by the gust, and flip to the `under` ramp only at gust peaks. Grass gets a travelling ripple and ferns press down (`bob`). Every term repeats each `period`.
- Contract: `_w.png` is unchanged. `_m.png`, `_u.png` and `_night_u.png` are new files, so old shaders (T707/T709 `sway.gdshader`) keep working.
- Measure (`~/agent-work/research/2026-10-20/T713/tools/motion.py`): plant-activity synchrony fell from 0.646 to 0.047. The displacement autocorrelation peak inside 3 s fell from 0.476 to none.

### Pitfalls (legacy, T710/T713)
- T713 leaves: per-leaf edge shading (+1 top, -1 bottom) on every overlapping leaf gave a checkerboard at x8 (r1-r2). Flat mass leaves plus 10-16% accent leaves with a cast shadow read as leaves (r3-r4).
- Lobes and midribs inside a 5 px glyph (`.X.X.`, `XXvXX`) read as dither. Keep the inside solid and put the shape in the outline.
- `clean()` erased every 1 px leaf tip on the silhouette. Leaf pixels are marked `detail` and skipped.
- Leaves that start at 35-55% of each twig left a dark donut in the big front cluster. Starting at 12-37% fixes it (r17, 3 seeds).
- Cluster structure got lost until the underside term was raised (`-0.55*max(0, ny-0.15)`).
- The conifer: dense sprays (hw*0.9 per side) or sprays that overwrite the cast band made one shapeless triangle (r10-r11). Sparse 2-3 px strokes that skip level-1 pixels keep the tiers (r12, r16).
- In a lit Godot night scene, the night albedo under CanvasModulate goes double dark. Use the day albedo there and let the lights grade it. Leaf heights must follow the cluster dome, or the moon band never lights a cluster.
- Godot shader names: `TAU` is a built-in constant (redefinition error), and a function parameter named like a uniform (`amp`) fails to compile.
- Sway weights grown into the trunk tore it in gusts. Growth now goes only into transparent pixels.
- Leaf flips on the palest `under` level at level+1 flashed like snow. Use the same level on the `under` ramp, gate above 0.45 + 0.5*random, and flutter above 0.5.
- Per-pixel lighting plus noise gives the T707 mud. One level per leaf bundle gives clean bands. On the oak, `clean()` cut lone-level pixels from 217 to 37 out of 3656 opaque.
- Highlight flecks on every lit bundle read as sparkles or hatching (rounds 2-3). Top-rim arcs on level-4 bundles only, plus 35% of level 3, read as leaves.
- The crown read as a donut (dark ring) on seed 3 until a front-centre cluster was added to `crown_layout`.
- Ferns: 1 px pinnae every 1 px merged into a blob (rounds 4-5). Every 2 px, plus darkening the older frond where a new frond overlaps it (`gap`), separates them.
- The night rim on thin strokes (grass, willow strands) turned every blade cyan. The rim skips `thin`.
- Shrubs floated about 4 px above their pivot until the crown bottom was tied to `by` (`cy = by - 0.95 ry`).
- A preset size knob clashed with `meta['size']` (sprite px). The knob is stored as `scale`.
- Tilt-shift grade (T707 `post.gdshader`, top 14% band, `textureLod(..., b * dof)`) blurs crowns at the top of the frame. Keep crowns below 14% of the height, or narrow the band to `smoothstep(0.0, 0.06, uv.y)`, or set `dof = 0` on foliage scenes.
- The hook denies hand-written `sleep` wait loops. `godot-check.sh` waits for the weston socket with `wait-for --until`.
- Costs (T713): the scene copy build takes 30 s, the Godot still 15 s, the 11 s movie about 60 s, and motion.py (MP4 + metrics) 100 s. T710: building all 12 presets takes 3.3 s; the catalogue plus a 270-frame 1080p MP4 takes 25 s; the selftest takes 9.5 s; the Godot import plus 60 frames takes 35 s.

## Links
- Code: `~/.claude/skills/pixel-foliage/` (SKILL.md, scripts/, templates/foliage_anim.gd; legacy/ = T713 scripts, shaders, reference, selftest)
- Tests: `~/.claude/skills/pixel-foliage/tests/selftest.sh` (prints `SELFTEST ok 12 presets`)
- T715: `~/agent-work/research/2026-10-20/T715/` (RESEARCH.md, ARCH.md, rounds/R1-R6 + CRITIQUE.md, tools/compare.py, scene/ = T707 copy on atlases), `~/drop/T715/`
- Design / results: `~/agent-work/research/2026-10-19/T710/` (rounds r1-r9, compare.py, godot/), `~/drop/T710/`
- T713: `~/agent-work/research/2026-10-20/T713/` (diagnosis.md, boards r0-b17, tools/board.py, tools/motion.py, scene/ = T707 copy on pixel-foliage), `~/drop/T713/`
