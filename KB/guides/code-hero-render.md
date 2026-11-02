# Make an AAA hero shot or character loop 100% with code (Blender EEVEE by script, numpy audio, no AI image)

Ticket: T1415, T1417, T1450, T1451 · Last verified: 2026-11-02 by T1451 (T1450 film remixed: calm score, remux only); by T1450 (61 s narrated film, 1464 frames at 1600x1125, `templates/film/`); before: 2026-10-27 by T1417: the Mooblox logo island 5 s loop rendered with the skill
(150 frames at 1080², 9.3 s/frame), `tests/loop.test.py` 5/5, `tests/audio.test.sh` 3/3, `tests/smoke.test.sh` 6/6, `tests/encode.test.sh` 2/2

## When to use
The owner asks for art "made with code" or "without AI image models": a mascot or character loop, a logo hero loop, a Discord
piece. The quality bar is the T1415 droid (`~/drop/T1415/`): "AAA, shocking and breathtaking". Not for multi-shot edits, VO or
titles (`/motion-video`), rigged humans (`/char3d`) or pixel sprites (`/pixel-avatar`).

## The path we took
T1415 wrote a bespoke bpy scene (lib3d, character, stage, anim, sound). T1417 measured why it landed
(`~/agent-work/research/2026-10-27/T1417/POSTMORTEM.md`) and lifted it into skill `/code-hero-render`:
| Module | One job |
|---|---|
| `hero/prims.py` | rounded, smooth bpy primitives; `outline` extrudes 2D polylines with holes (logos, wordmarks) |
| `hero/materials.py` | ceramic (coat + SSS), clay (noise mottling + bump), glass dot matrix, emitters, floor, water, holo code |
| `hero/stage.py` | rig presets neon/dusk/studio (warm key, cool fill, 2 complementary rims, one volumetric shaft), world, halo, depth field |
| `hero/look.py` | EEVEE + AgX settings, DOF camera, compositor (bloom, fog glow, dispersion, vignette), aspect sizes |
| `hero/loop.py` | `cyc`/`win`/`kick` maths, `seam()` check, `Keyer`, keys 1..N+1 + LINEAR (Blender 5 channelbags) |
| `hero/cli.py` | shared argv (`--stills --size --aspect --samples --raytrace --concept`), build → key → look → render |
| `hero-render` | concepts / stills / draft / final passes behind the load gate, blender under `heavy run --ticket $HERO_TICKET` (nice if no heavy), contact sheets |
| `hero-audio` | numpy pad with whole cycles per loop + cue events (tap, pluck, bloop, chirp, bell, whoosh) that wrap the seam |
| `hero-encode` | levels pre-grade → mv-encode film finish → ≤ 25 MB (CRF steps) → poster, seam SSIM, mv-review, `--clean` |
The shot script owns only `build(scene, a)`, `pose(t)` and `apply(ctx, p, key, t)`. Starter: `templates/shot.py`.

## Exact commands
```bash
S=~/.claude/skills/code-hero-render; P=~/agent-work/motion/<T>/<name>; mkdir -p $P/audio; cp $S/templates/shot.py $P/
$S/scripts/hero-render $P/shot.py $P concepts neon,dusk,studio      # Read $P/concepts/sheet.jpg, pick
$S/scripts/hero-render $P/shot.py $P stills 1,40,90 -- --concept dusk
$S/scripts/hero-render $P/shot.py $P draft -- --concept dusk        # Read $P/draft_sheet.jpg
echo '[{"t": 0.5, "kind": "bell", "pan": 0, "f": 523}]' > $P/audio/cues.json   # hand-written cue list, format: hero-audio --help
$S/scripts/hero-audio $P/audio/score.wav --seconds 5 --root 87.31 --mood major --cues $P/audio/cues.json
$S/scripts/hero-render $P/shot.py $P final -- --concept dusk        # run in the background
$S/scripts/hero-encode $P/frames/final ~/drop/<T>/<name>.mp4 --audio $P/audio/score.wav --clean
python3 $S/tests/loop.test.py && bash $S/tests/audio.test.sh && bash $S/tests/smoke.test.sh && bash $S/tests/encode.test.sh && bash $S/tests/heavy.test.sh
```

## Film mode (T1450): a narrated 45-90 s short, not a loop
`templates/film/` has `shot.py` (the T1450 worked example: a spark on a mirror floor, 11 beats, one continuous camera), `make_timeline.py`
(Kokoro marks to `timeline.json`), `audio/score.py` (numpy score on the same cues, FFT reverb, VO ducking), `make_subs.py` (libass
title, word-lit captions, end card) and `encode.sh` (open gate to 16:9 + 4:5, two-pass finish then burn, -16 LUFS). Steps: SKILL.md "Film mode".

## Pitfalls (measured)
- Blender 5.0.1 has no `Action.fcurves`. T1415's "set LINEAR" loop ran on an empty list and did nothing. Walk
  `action.layers → strips → channelbags → fcurves` (`loop.linearize`). The `keyframe_new_interpolation_type` pref does not
  reach `keyframe_insert` from a script: keys stayed BEZIER (tested 2026-10-27).
- Mix node sockets go by index in 5.0: 6/7 are the A/B colours, output 2 is the result. "A"/"B"/"Result" failed in T1415.
- Volume on the key or rim lights washed the frame out (T1415 look-dev, volume 0.2-0.3). Keep volume 0 on them and 3.5 on the shaft
  only. Fog over 0.012 turns the frame blue-grey (the T1415 concept stills used 0.035).
- 70 mm at 9.4 m frames exactly like 85 mm at 11.5 m (T1417 still b = still a): change the distance/lens ratio to widen.
- f/1.4 at 9.4 m left the floating props sharp and busy. f/0.6-1.0 with the field kept out of the subject's box fixed it.
  For two depths (island + wordmark), f/1.0 at 12 m holds about 1.2 m in focus.
- `bpy.ops.object.transform_apply()` defaults to location + rotation + scale. T1415's `rounded_box` baked the location into
  the mesh, so every object origin sat at the world origin. In T1417 the spinning blox orbited the origin and the seam popped
  (SSIM last→first 0.884 against 0.956 for a normal step). Fixed in `prims` (scale only); test `smoke.test.sh` covers it.
  After the fix: 0.950 against 0.948. `hero-encode` prints WARN when the seam is 0.03 under a normal step.
- Final 1080² with 32 samples and raytrace: 10.4 s/frame (T1415, 300 frames in 52 min at 42 % CPU), 9.3 s/frame (T1417, 150 frames in 23.3 min). Draft
  480/8: 1.4-1.9 s/frame. The draft caught T1415's only animation fix (the wave was too small).
- A 16-bit 1080² PNG is 5.8 MB, so 300 frames take 1.7 GB: run `hero-encode --clean`.
- The T1415 encode was 3.5 Mbps (4.6 MB for 10 s), so Discord's 25 MB is never the limit at 1080². The CRF loop only matters
  at 4K or 30 s+.
- T1450 film: 1600x1125 open gate, 12 samples + raytrace + `--fast` = 3.4-4.2 s/frame (Iris Xe, `heavy run`); 1920x1350 at 24 samples
  was 12 s/frame. CPU work beside the render (numpy, encodes) slows it ~15 %, because `heavy` gives Blender idle CPU weight.
- Emitters keyed to 0 render black (rings, orbs), and area lights mirror as rectangles in the glossy floor from a high camera:
  scale emitters to 0.0001 while off and fade the rig before a crane-up (T1450 storyboard pass).
- The spot shaft (the one volume light) left at 35 % showed as a stack of grey 8 px blocks (`--fast` volume tiles) above the
  horizon once the crane brought black sky into frame (T1450 final, frames 1205-1300): fade it to 0 before the horizon enters.
- `bmesh.ops.create_icosphere` x 3200 into one bmesh took over 3 min; one icosphere tiled through `from_pydata` with point attributes takes under 1 s.
- libass: no fontconfig family "Inter Display Bold" (fell back to Noto Sans): use `Inter Display` with Bold -1.
- End card over a bright bokeh field read busy (lanterns through the letters): a layer-0 libass `\p1` black box,
  `\1a&H48&\blur60`, behind the text fixes it with no re-render; only the caption pass reruns (T1450 `make_subs.py`).
- `mv-encode --finish film` halation runs after `--burn` and puts a red halo on white captions: finish first, burn in a second pass.
- Seam check: measure it on the lossless PNGs, not the mp4. The H.264 file biases it: T1417's final measured 0.923
  last→first against 0.960 first→second in the mp4, while the same frames as 720 px PNGs gave 0.9827 against 0.9823. T1415's
  0.914 against 0.924-0.932 was measured on its mp4. `hero-encode` compares f_N→f_1 with f_1→f_2 at 540 px before encoding.
- Never play the audio on this machine: `hero-audio` prints LUFS and peak from ffmpeg ebur128 only.
- Film sound (T1451): the T1450 bed sat 14.7 dB under the VO (worst line 5.4), with bells up to MIDI 110 and 187 cue events;
  the owner heard it "too loudy and high pitch". The calm rule (bed >= 18 dB under speech, 7 kHz low-pass, bells <= MIDI 81,
  one layer per beat, every Kokoro clip leveled to -16 LUFS) is in SKILL.md pitfalls and `templates/film/score.py`.

## Links
- Skill: `~/.claude/skills/code-hero-render/` (SKILL.md, reference/recipe.md, scripts/, templates/shot.py, tests/)
- Tests: `python3 tests/loop.test.py`, `bash tests/audio.test.sh`, `bash tests/smoke.test.sh` (96 px Blender, about 15 s), `bash tests/encode.test.sh`
- Results: `~/drop/T1415/` (reference), `~/drop/T1417/` (Mooblox proof), postmortem `~/agent-work/research/2026-10-27/T1417/POSTMORTEM.md`
- Example shot: `~/agent-work/motion/T1417/mooblox/shot.py`
