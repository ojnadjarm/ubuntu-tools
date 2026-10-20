# motion-video reference: every command and knob (mv-render, mv-encode, mv-mix, Blender MV_* vars)

```bash
mv-render new remotion ~/agent-work/motion/<ticket>      # or: new mc <dir>
mv-render remotion <dir> Main <dir>/out/main.mp4 -- --concurrency=8   # extra remotion flags after --
MV_SIZE=1080x1920 mv-render mc <dir> <dir>/out/main.mp4  # Vite + headless Chrome clicks Render; PNG frames -> crf 10
MV_FPS=30 MV_SECONDS=5 mv-render blender ~/.claude/skills/motion-video/templates/blender/shot.py <frames-dir>
mv-encode <frames-dir>/frame_%04d.png out.mp4 --fps 30 --preset h264-master
mv-encode in.mp4 out-av1.mp4 --preset av1 [--audio vo.wav --loudnorm | --target youtube]
mv-render clean [--all] <dir>                             # before a drop: node_modules, output/, .remotion; keeps out/ (deliverables, edit/, OTIO) unless --all
mv-render bundle <dir> <bundle-dir>                      # one remotion bundle, kept while src/ + lock hash holds; render from <bundle-dir>
mv-render variants <dir> Main <out-dir>                   # one comp -> Main-16x9 / 9x16 / 1x1 (--width/--height)
mv-render bench <dir> Main 4 8 16                         # render time per --concurrency
mv-encode in.mp4 graded.mp4 --preset hevc-10 --lut film   # LUT grade (film|bleach|any .cube) + 10-bit master (or av1-10)
mv-encode in.mp4 hdr.mp4 --preset hevc-hdr10|av1-hlg --finish none   # T626 BT.2020 10-bit HDR, SDR white 203 nit, MaxCLL/MaxFALL measured; mv-review FAILs PQ without mastering metadata (tests/mv-hdr.test.sh)
mv-encode in.mp4 hdr.mp4 --preset hevc-hdr10 --x265-preset medium   # libx265 speed preset for hevc/hevc-10/hevc-hdr10 (or MV_X265_PRESET; default slow; the film template exports medium) (tests/mv-encode-preset.test.sh)
mv-assets fetch && mv-assets list                         # CC0 music + SFX library -> ~/.local/share/motion-video
mv-mix --out mix.wav --duration 10 --vo vo.m4a --vo-at 0.6 --music <lib>/music/ambient-loop.ogg --sfx <lib>/sfx/kenney-impact/impactSoft_heavy_000.ogg@0.4@-8
mv-captions vo/cues.json vo caps --offset 0.6 [--size 1080x1920]   # caps.srt (sidecar) + caps.ass (burn, active word highlighted)
mv-encode main.mp4 final.mp4 --audio mix.wav --burn caps.ass --subs caps.srt
mv-lut film|bleach out.cube                               # regenerate a house look
mv-lut match ref.png src.mp4 match.cube [--strength 0.8] [--sheet m.jpg]   # LUT that matches src's colour to a reference
mv-encode in.mp4 out.mp4 --preset h264-web --finish film [--grain 2]   # film: halation + temporal grain + deband/dither; clean: deband + dither only (no 8-bit banding)
mv-diff a.mp4 b.mp4 [--json] [--out dir]                  # what changed between two renders (SSIM ranges + audio dB)
mv-estimate <project> [--seconds 20] [--fps 24] [--size 1920x1080] [--draft] [--budget 6000] [--json]   # T1004 CPU s per step from the project's mv-build history (creative-ci.jsonl): fit a + b x frames x pixels (x samples for plate*) over 2+ builds, 1 build scales linearly; rc 1 "over budget: <est> > <budget>", rc 2 no history
mv-beats music.ogg --out beats.json [--every 2] [--downbeats]   # beat/downbeat cues: mv-mix --cues beats.json --sfx hit.wav@cue:beat12
MV_HDRI=<file.hdr|polyhaven-slug> [MV_HDRI_ROT=deg MV_HDRI_STRENGTH=1.0] [MV_GROUND=catcher] mv-render blender shot.py <frames-dir>   # Blender IBL + shadow catcher
MV_CAMERA=dolly|orbit|crane|push|handheld MV_CAMERA_EASE=linear|ease|expo MV_LENS=40 MV_FSTOP=2.8 mv-render blender shot.py <frames-dir>   # T586 camera move, lens mm, DOF
MV_LOGO=logo.svg [MV_LOGO_DEPTH=0.35] [MV_BRAND=brand.json] [MV_RING=0] mv-render blender shot.py <frames-dir>   # T597 extruded brand logo (default: brand.json "logo"); MV_RING=0 hides the ring
MV_MODEL=model.glb|.gltf [MV_MODEL_HEIGHT=2.0] [MV_HDRI=studio_small_09] mv-render blender shot.py <frames-dir>   # T656 glTF hero, materials kept, centred on the floor, camera path scaled to frame its bbox; CC0 model: `mv-assets fetch` -> ~/.local/share/motion-video/model/camera-01/
MV_MODEL=hero.glb MV_MODEL_ANIM=<clip|first> [MV_MODEL_ANIM_SPEED=1.0] [MV_MODEL_ANIM_CUE=<mark>] mv-render blender shot.py <frames-dir>   # T677 plays the glTF clip on a looping NLA strip, whole loops scaled so one ends on the cue (default MV_TITLE_CUE, else the shot end); without it the hero holds its rest pose; unknown clip exits listing the names
mv-render blender shot.py <frames-dir> --draft|--resume   # MV_DRAFT=1: 50 %, 4 spp, no blur; MV_RESUME=1: keep rendered frames; MV_ENGINE=CYCLES = CPU stills only
MV_LOOK=none|soft|filmic [MV_VIGNETTE=0.15] [MV_DEPTH=16|8] mv-render blender shot.py <frames-dir>   # T612 compositor look: soft = bloom, filmic = fog glow + dispersion 0.01; both glow above 1.0 + corner vignette; 16-bit PNG by default
MV_FOG=0.02 mv-render blender shot.py <frames-dir>   # T689 world Principled Volume (density, 0 = off, pixels unchanged; 0.01-0.03 reads as haze) + volume-only backlit spot whose beams the hero cuts into light shafts; volume tile 4, 64 samples even in --draft (tests/mv-fog.test.sh)
MV_TITLE="TEXT" [MV_TITLE_CUE=sec] [MV_CUES=cues.json] mv-render blender shot.py <frames-dir>   # T625 extruded Inter-Bold 3D title, per-letter rise + fade 40 ms apart from the cue; logo shrinks to 0.65 above it (tests/mv-title3d.test.sh)
mv-mix --out mix.wav --duration 30 --vo vo.m4a --music bed.ogg --music-db -14 --duck 8 --fit bars   # T589 bed loops whole 4-bar groups, ends on a downbeat
mv-mix --out mix.wav --duration 30 --music bed.ogg --sfx hit.wav@2.5 --game play.wav@0@-4 --duck-on vo,sfx,game   # T670 bed ducks under VO, SFX and game audio; T686 loudness.json duck.<class>.depth_db caps the dip (sfx 8, game 6, vo uncapped)
MV_DUCK_ON=vo|sfx,game|... ./build.sh   # T720 film/trailer: mv-mix --duck-on; default sfx,game when any SFX/game stem is mixed (bed dips under hits and game audio), else vo
MV_EDIT=1 ./build.sh   # T720 film/trailer: also timed edit_media (graded plates, alpha title, music bed in out/edit) + build.json .edit for mv-otio; default 0 skips it
mv-sfx whoosh|riser|hit|sub-drop --out x.wav [--dur S] [--seed N] [--pan P] [--pitch PCT] [--room small|hall]   # T613/T642 procedural SFX, placed; mv-sfx cues camera.json --out cues.json: whoosh/hit marks with pan + pitch from --dump-camera
mv-quality ref.mp4 enc.mp4 [--min-vmaf 93] [--sheet s.jpg]   # T590 VMAF/1 % low/worst second/PSNR-Y/SSIM; --search ref.mp4 --preset av1 --target 95 bisects CRF
mv-quality ref.mp4 enc.mp4 --subsample N                      # T681 score every Nth frame (MV_VMAF_SUBSAMPLE; auto: all up to 600 frames, else ceil(frames/600))
mv-encode in.mp4 out.mp4 --preset av1 --crf 30                # override the preset CRF (QP for VA-API presets), e.g. the one mv-quality --search found
```
Review, cue and caption flags the examples above leave out:

| CLI | Flag | Default | What |
|---|---|---|---|
| `mv-diff` | `--ssim` | 0.98 | a 0.1 s sample counts as changed when its SSIM is below this |
| `mv-diff` | `--audio-db` | 3 | or when the two RMS levels differ by more than this many dB |
| `mv-diff` | `--floor` | -50 | ignore audio deltas where both sides are below this dBFS |
| `mv-diff` | `--gap` | 0.3 | merge changed samples closer than this many seconds into one range |
| `mv-diff` | `--per-range` | 4 | max A\|B sheet pairs per changed range |
| `mv-diff` | `--cols` | 2 | A\|B sheet pairs per row |
| `mv-review` | `--cols` | 10 | contact-sheet frames per row |
| `mv-review` | `--black` | 1.0 | FAIL on a black stretch this long (s) |
| `mv-review` | `--freeze` | 2.0 | FAIL on a frozen stretch this long (s) |
| `mv-review` | `--brng` | 0.001 | FAIL when a frame has more than this fraction of Y outside 16-235 |
| `mv-review` | `--pse` / `--no-pse` | on | photosensitive check: FAIL any 1 s with > 3 general or red flashes over >= 25 % of the screen |
| `mv-beats` | `--meter` | 4 | beats per bar for `--downbeats` |
| `mv-beats` | `--snap T[,T...]` | off | print each cut time's nearest beat: `T beatK t delta_ms` (input may be an earlier beats.json) |
| `mv-captions` | `--words` | 5 | max words per caption line |
| `mv-captions` | `--accent` | `33C2FF` | active-word colour in the .ass, BGR hex |
| `mv-sfx cues` | `--clip` | `camera` | clip name the whoosh/hit marks go under in cues.json |
| `mv-sfx cues` | `--fps` | 60 | camera.json frames per second (= shot.py `MV_FPS`) |
| `mv-quality` | `--json` | off | print the full result as JSON |
| `mv-report` | `--min-vmaf` | 93 | VMAF floor for the check and the VMAF lane |
| `mv-report` | `--target` | - | loudness.json target drawn on the loudness lane |
| `mv-encode` | `--codec-args PRESET` | - | print an SDR software preset's encoder + BT.709 tag args, one per line, for a caller's own ffmpeg graph (film build.sh) |

Every `--flag` in a `scripts/mv-*` `--help` must appear, as a whole word, on a SKILL.md or reference/ line or table row naming that CLI, or under a `##` heading naming it (`tests/mv-flags-doc.test.sh`).

Paths, devices and concurrency knobs:

| Knob | Default | What | Read by |
|---|---|---|---|
| `MV_PLATE_JOBS` | 1 | Blender plates rendered at once beside the titles (they share one GPU) | `templates/film/build.sh` |
| `MV_LAYOUT` | 1 | 0 skips the mv-layout check of the camera dumps | `templates/film/build.sh` |
| `MV_MASTER` | 0 | 1 also keeps out/master-<aspect>.mp4 via h264-master as its own timed step | `templates/film/build.sh` |
| `MV_VAAPI_DEVICE` | `/dev/dri/renderD128` | VA-API render node for hardware encode/decode | `scripts/mv-encode`, `scripts/mv-diff` |
| `MV_VMAF` | `~/.local/opt/mv-quality/vmaf` | Netflix vmaf CLI binary | `scripts/mv-quality` |
| `MV_VMAF_THREADS` | nproc/4 shrunk by the 1-min load, min 1 | vmaf threads | `scripts/mv-quality` |
| `MV_BEATS_VENV` | `~/.local/opt/mv-beats` | Python venv for beat detection | `scripts/mv-beats` |
| `MV_OTIO_VENV` | `~/.local/opt/mv-otio` | Python venv with OpenTimelineIO | `scripts/mv-otio`, `tests/mv-otio.test.sh` |
| `MV_LIBRARY` | `~/.local/share/motion-video` | CC0 asset library root | `scripts/mv-assets` |
| `MV_CHROME` | `/usr/bin/google-chrome` | Chrome that renders Motion Canvas | `templates/motion-canvas/render.mjs` |

Every `MV_*` name in scripts/ and templates/ must appear in SKILL.md or reference/ (`tests/mv-knobs-doc.test.sh`).

Scripts: `scripts/mv-{new,review,render,encode,mix,captions,assets,lut,diff,beats,quality,report}` (linked in `~/.local/bin`). Templates: `templates/{remotion,motion-canvas,blender}`, `templates/brand.json`, `templates/build.sh` (versions pinned in package.json). LUTs: `luts/`. Asset manifest: `assets.tsv` (every row CC0, source page kept in `LICENSES.tsv`).
