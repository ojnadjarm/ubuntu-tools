# motion-video reference: studio recipe, tool choice, encode presets, quality rules

## Studio-grade recipe (T453, sample `~/drop/T453/04-*`)
1. VO: `/kokoro-narration` on a unit.json -> `vo/audio/vo.m4a` + `vo/cues.json` (word timings; no ASR needed for our own VO).
2. Picture: Remotion `Main`/`Camera3D` (three.js via `@remotion/three`, `<CameraMotionBlur samples>`; `--props='{"samples":1}'` for drafts). Lay out with `s = min(width/1200, height/1080)` so every aspect fits.
3. Sound: `mv-mix` (music ducked ~7 dB under the VO by sidechaincompress, SFX at times; two-pass linear loudness to a `--target` from `loudness.json`: web -16 (default), youtube -14, broadcast -23, podcast -16; `mv-review --target` checks the same table).
4. Captions: `mv-captions` with the same `--offset` as `--vo-at`.
5. Master: `mv-encode --audio mix.wav --burn caps.ass --subs caps.srt [--lut film] --preset h264-master|hevc-10`.

## Which tool
| Job | Tool | Why |
|---|---|---|
| Product/marketing motion, kinetic type, UI mockups, data-driven, 4K | **Remotion 4.0.536** | React/CSS/SVG/WebGL, deterministic frames, `--scale=2` for 4K from a 1080 comp |
| Explainer beats, diagrams, code walkthroughs, sequenced reveals | **Motion Canvas 3.17.2** | generator timelines (`yield* all(...)`), fast, crisp vector |
| Real 3D: product turntables, lighting, DOF, reflections | **Blender 5.0.1 EEVEE** | GPU (Iris Xe) via EGL in `-b`; PNG frames → mv-encode |
| Math/geometry proofs | Manim CE 0.21.0 (`manim -qh`) | already installed |
| After Effects/LottieFiles assets | `@remotion/lottie` inside Remotion (`LottieCard`) | proven in the T478 reel |
| Narration | `/kokoro-narration` → `mv-mix` → `--audio mix.wav` | -16 LUFS, captions from its word timings |
| 3D camera moves in a motion comp | `@remotion/three` + `@remotion/motion-blur` (`Camera3D` template) | frame-driven camera, ~6-11 fps 1080p60 |
Never: DaVinci Resolve (no NVIDIA/AMD GPU), Natron (dormant), Cycles GPU (Iris Xe unsupported; Cycles CPU = stills only).

## Encode presets (mv-encode, measured on 600 frames 1080p60 flat graphics, load ~7)
| Preset | Use | fps | Size |
|---|---|---|---|
| h264-master | delivery master, plays everywhere (x264 slow crf 16) | 19.9 | 1931 KB |
| h264-web | upload/social (crf 20) | 34 | 1560 KB (with audio) |
| hevc | smaller master, hvc1 tag (x265 slow crf 18) | 5.7 | 985 KB |
| av1 | smallest web file (SVT-AV1 p5 crf 28) | 10.8 | 726 KB |
| h264-hw / hevc-hw | fast drafts on Iris Xe VA-API | 74.8 / 53.7 | 1161 / 1002 KB |
| vp9-alpha | transparent overlay .webm | | |
| hevc-10 | 10-bit master, no banding after a LUT (x265 main10 crf 16) | 5.4 | 2185 KB (300 fr 3D) |
| av1-10 | 10-bit web master (SVT-AV1 p5 crf 24) | 8.5 | 1246 KB (300 fr 3D) |

## Quality rules
- Author at 1920x1080 and scale up (`--scale=2` in Remotion) for 4K; keep all sizes relative to `width/1920`.
- 60 fps for UI/kinetic type, 30 fps for Blender (each frame costs seconds); motion blur in Remotion via `@remotion/motion-blur` only where needed (multiplies render time).
- Easing: springs (`spring({damping: 12–14})`) and `Easing.inOut(cubic)`; never linear on position.
- Colour: Blender uses AgX + "Medium High Contrast"; Remotion/MC are sRGB; grade with `--lut` and master 10-bit (`hevc-10`/`av1-10`) when there are gradients or a grade; delivery copies stay 8-bit h264 for compat. ffmpeg has no OCIO filter here, so ACES is out; AgX lives in Blender.
- Fonts: Inter and JetBrains Mono are system fonts (fc-list); other Google fonts via `@remotion/google-fonts`.
- Assets: Poly Haven / ambientCG / Kenney are CC0. An HDRI (Poly Haven) fixes black chrome. Mixamo needs the owner's Adobe login.

