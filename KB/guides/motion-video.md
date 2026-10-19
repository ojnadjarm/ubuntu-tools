# Make a high-end motion video headlessly (Remotion, Motion Canvas, Blender EEVEE, ffmpeg presets)

Ticket: T439, T453 · Last verified: 2026-10-19 by real renders (Remotion 10 s 1080p60 in 3 aspects, Remotion three.js 5 s with motion blur, Motion Canvas, Blender EEVEE), LUT grades into 10-bit HEVC/AV1, a narrated mix with ducking and burned captions

## When to use
Any promo, title card, kinetic type, explainer or 3D shot rendered to mp4. Not for interactive web lessons (`/explainer-engine`) or narration alone (`/kokoro-narration`).

## The path we took
Survey and table: `~/agent-work/research/2026-10-19/T439/STACK.md`. Remotion for product/marketing motion and 4K, Motion Canvas for explainer beats, Blender EEVEE for 3D, Manim for maths; everything ends in `mv-encode` (ffmpeg presets). Resolve (no NVIDIA/AMD GPU) and Natron (dormant) were ruled out. skill /motion-video holds templates and the scripts. T453 added: `Camera3D` (three.js + camera motion blur), aspect variants, LUT + 10-bit masters, a CC0 music/SFX library, ducked mixing and captions from Kokoro word timings (architecture: `~/agent-work/research/2026-10-19/T453/ARCH.md`). Whisper/ASR was skipped: our VO is TTS with exact word timings; whisper.cpp is not installed.

## Exact commands
```bash
mv-render new remotion ~/agent-work/motion/<ticket>
mv-render remotion ~/agent-work/motion/<ticket> Main ~/agent-work/motion/<ticket>/out/main.mp4
mv-render mc <mc-dir> <mc-dir>/out/main.mp4
MV_FPS=30 MV_SECONDS=5 mv-render blender ~/.claude/skills/motion-video/templates/blender/shot.py <frames-dir>
mv-encode <frames-dir>/frame_%04d.png shot.mp4 --fps 30 --preset h264-master
mv-encode main.mp4 main-av1.mp4 --preset av1
mv-render clean <dir>
mv-render variants <dir> Main <out-dir>                   # 16x9 / 9x16 / 1x1
mv-encode in.mp4 out.mp4 --preset hevc-10 --lut film      # or av1-10, --lut bleach|file.cube
mv-assets fetch                                           # CC0 library -> ~/.local/share/motion-video
mv-mix --out mix.wav --duration 10 --vo vo.m4a --vo-at 0.6 --music <lib>/music/ambient-loop.ogg --sfx <file>@0.4@-8
mv-captions vo/cues.json vo caps --offset 0.6
mv-encode main.mp4 final.mp4 --audio mix.wav --burn caps.ass --subs caps.srt
```

## Pitfalls (measured)
- Motion Canvas has no headless CLI; `render.mjs` clicks the editor's `#render`. Killing `npx vite` left Vite holding the pipe and the caller hung 10 min; spawn Vite as a process group and kill `-pgid`.
- `"type": "module"` breaks the Motion Canvas `vite.config.ts` (`motionCanvas is not a function`).
- QSV fails ("MFX session -9"); VA-API h264/hevc works at 75/54 fps. Iris Xe has no AV1 hardware encode.
- Blender EEVEE headless runs on the Iris Xe; 4-6 s/frame at 1080p with 16 samples and raytracing off; 12 s/frame with raytracing on and 32 samples.
- Remotion's first render downloads Chrome Headless Shell; 600 frames 1080p60 = 53 s.
- Machine load from parallel agents (load avg 7-19) halves every number; renders never start in the CI window (00:50-01:50).

- Remotion concurrency: flat 2D 22.6-24.6 s for 600 frames at 4-16 (42.8 s at 2); WebGL 3D 28 s at 4, 78 s at 16. Default 6.
- Camera motion blur 8 samples = 1.8x render time, not 8x.
- `--subs` with `-shortest` truncated the video at the last caption; fixed with `-t <duration>`.
- Ducking measured: music bed -36.8 dB alone vs -43.5 dB under the VO (6.7 dB), mix -16.1 LUFS.
- FreePD closed; OpenGameArt CC0 and Kenney (CC0) zips with read-only dirs.

## Links
- Code: `~/.claude/skills/motion-video/` (SKILL.md, scripts/, templates/)
- Tests: the renders in `~/drop/T439/` and `~/drop/T453/`
- Design / results: `~/agent-work/research/2026-10-19/T439/STACK.md`
