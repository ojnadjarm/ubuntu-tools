---
name: motion-video
description: Headless motion videos (Remotion, Motion Canvas, Blender EEVEE, Manim, ffmpeg encodes). Use for "motion video", "animation video", "promo", "explainer video", "render a clip", "3D shot", "encode", "captions", "vertical video", "color grade", "film", "trailer".
---

Triggers: title card, kinetic type, product video, AV1, 4K60, voice-over mix, H.264, HEVC, VP9-alpha, VA-API drafts, loudnorm, 3D camera moves, motion blur, LUT grades, 10-bit masters, CC0 music/SFX library, ducking, burned or sidecar captions, 16:9/9:16/1:1 variants, diagrams, code.

# motion-video: pick the tool, render headless, encode with a preset

## Workflow
```bash
mv-new <name> --kind promo|explainer|3d|film|trailer [--brand brand.json] [--game <cpp-vulkan dir>]   # -> ~/agent-work/motion/<name>
cd ~/agent-work/motion/<name> && ./build.sh      # [Kokoro VO] -> 16:9 + 9:16 renders -> mix + captions -> LUT -> h264 -> mv-review; out/build.json, exit 1 on a FAIL
mv-review out/<name>-16x9.mp4 [--scopes]         # sheet, LUFS/peak, black/frozen, legal Y, photosensitive flashes; exit 1 on FAIL
mv-report out/                                   # one HTML report per review.json
```
1. Pick the tool: Remotion (promo, kinetic type, `Camera3D`), Motion Canvas (explainers), Blender EEVEE `shot.py` (real 3D), Manim (math).
2. VO: `/kokoro-narration` -> `vo/cues.json` drives cuts, SFX `@cue:NAME` and captions.
3. Never render inside the CI window: `ci-window && mv-render ...`; drafts with `--draft`.
4. Drop mp4 only; delete PNG frames, `mv-render clean` the project.

## Scripts and knobs (detail: reference/commands.md)
| Script / knob | One line |
|---|---|
| `mv-new` | scaffold a project + `build.sh` (kinds above; trailer = cpp-vulkan replay plates) |
| `mv-render` | `remotion`/`mc`/`blender` renders, `new`, `bundle`, `variants`, `bench`, `clean` |
| `mv-encode` | presets h264-master/web, hevc(-10), av1(-10), *-hw, vp9-alpha, HDR; `--lut`, `--finish`, `--burn`, `--subs`, `--audio` |
| `mv-mix` | VO + music bed + SFX + game audio, ducking, loudness `--target` |
| `mv-captions` | cues.json -> `.srt` sidecar + `.ass` burn |
| `mv-review` / `mv-report` | QC gate / HTML report |
| `mv-quality` / `mv-diff` | VMAF + CRF search / what changed between renders |
| `mv-assets` | CC0 music, SFX, models -> ~/.local/share/motion-video |
| `mv-lut` | house LUTs, `match` a reference |
| `mv-beats` / `mv-sfx` | beat cues / procedural whoosh, riser, hit, sub-drop |
| `mv-otio` | film edit -> OTIO + Kdenlive |
| `MV_SIZE` `MV_FPS` `MV_SECONDS` | render size / rate / length |
| `MV_CAMERA*` `MV_LENS` `MV_FSTOP` | Blender camera move, lens, DOF |
| `MV_HDRI*` `MV_GROUND` | IBL + shadow catcher |
| `MV_LOGO*` `MV_BRAND` `MV_RING` `MV_TITLE*` `MV_CUES` | brand logo, 3D title on a cue |
| `MV_MODEL*` | glTF hero + animation clip |
| `MV_LOOK` `MV_VIGNETTE` `MV_DEPTH` | compositor look, PNG depth |
| `MV_DRAFT` `MV_RESUME` `MV_ENGINE` `MV_SAMPLES` `MV_RAYTRACE` `MV_SHUTTER` | speed/quality |

## Reference (read the one you need)
- `reference/production-line.md`: kinds, `build.sh` env, build.json, mv-review checks, mv-report, mv-otio, Lottie, VO cues.
- `reference/commands.md`: every command line with its flags and MV_* variables.
- `reference/craft.md`: studio recipe, which tool, encode preset table (fps, size), quality rules.
- `reference/pitfalls.md`: measured render times and failures (Remotion, Motion Canvas, Blender, QSV, SVT-AV1).
- Guide: `guide motion-video`. Reference project: `~/agent-work/motion/T478/reel`.
