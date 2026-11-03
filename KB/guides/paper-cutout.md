# Make a paper cut-out stop-motion diorama with code (layered card, real shadows, a narrated paper film)

Ticket: T1464 · Last verified: 2026-11-03 by T1464 (84 s narrated film "Which way is time going?", 2013 frames per cut, both cuts native; `tests/smoke.test.sh` 4/4)

## When to use
The owner wants a still or film that must look like a paper cut-out diorama or stop-motion papercraft: hand-cut card on layers,
real shadows between them, kraft and watercolour paper, light through holes. Not for riso print (`/riso-print`), ink wash
(`/ink-wash`), clean-line comics (`/ligne-claire`), true 3D (`/code-hero-render`).

## The path we took
Surveyed: Blender NPR paper setups and After Effects paper-craft templates (a filter over a 3D or flat render), the craft in
Reiniger's silhouettes, Norstein's multiplane and the game Tearaway. Chosen: skill `/paper-cutout`, numpy + pycairo + OpenCV,
because a diorama is flat cards at depths, so planar shadows are exact by construction, CPU-only and deterministic.
| Piece | One job |
|---|---|
| `cut`, shapes, `glyphs` | hand-cut outlines in mm (knife wobble, rounded corners), cut letters |
| `Piece`, `Cam` | a card on a z plane; a pinhole camera with a shift lens (parallax, pull-backs) |
| `_draw_plane` | one plane's colour, paper texture and emission over its ROI (cairo, then numpy) |
| `render` | front-to-back: each plane's alpha warped by the gap (scale + light slope), blurred by the gap, as shadow on the planes behind; contact AO, rim light, curl, lamp pool, DOF |
| `finish` | the photograph: bloom, vignette, exposure flicker and grain per pose |
A film's scene returns pieces, a camera, a light and a background; puppets move on twos, the camera on ones.

## Exact commands
```bash
PY=~/.local/opt/inkwash/bin/python; S=~/.claude/skills/paper-cutout
bash $S/tests/smoke.test.sh                                   # 4 PASS lines, about 10 s
cd ~/agent-work/motion/T1464/film
$PY render.py look/s1 16x9 "t=2,9,25,46,66" 12 && $PY sheet.py look/s1 look/s1.jpg 4 480
heavy run --ticket T<n> -- ./render_all.sh                    # frames/16x9 and frames/4x5, frame_key dedupe
$PY audio/score.py && ./encode.sh ~/drop/<T> && ./deliver.sh ~/drop/<T>
python3 ~/agent-work/motion/T1451/measure.py audio/mix.wav audio/vo.wav 0.8 timeline.json   # bed under the voice
```

## Pitfalls (measured)
- A glow piece on top read blown white at glow >= 1, then dull tan as plain card; a hole in the dark card with backlit vellum
  behind it (glow 0.5) reads as light. A lamp pool on the night card looked wrong: `Light(pool=None)` there.
- DOF and a pan's motion blur smeared the screen-space captions: screen pieces skip DOF; restore the caption box after the blur.
- A 5-plane 1080p frame took 2 s; per-plane ROI, downsampled large blurs, caster bbox culling and `maxgap=160` made it 0.6 s.
  Busy scenes (a kitchen set, 560 atoms) run 3-5 s a frame per worker.
- Init (paper textures plus a top-down table render) costs about 16 s: run it before the fork pool. `frame_key` dedupe on twos:
  1295 unique of 2013 frames in the 16:9 cut.
- A table seen in perspective: render it once top-down (`Cam(dist=1e6)`) and warp it per frame with a homography.
- The 4:5 pull-back saw past the table image's far edge (black band): pad it with a mirrored strip of plain boards
  (`BORDER_REFLECT` mirrored the cutting mat into view).
- Frame each cut on its own: the 16:9 framing dropped the falling cup out of the 4:5 frame; a 4:5 view wider than the set's
  350 mm height showed black under the floor. Contact-sheet both full renders.
- Labels in the bottom 22 % hid under the captions; IR-photon wiggles drifted onto the next subject until faded by distance.
  `sheet.py` crashed on a dir mixing 16:9 and 4:5 frames.
- Full render, 12 fork workers under `heavy`: 16:9 634 s (0.32 s a frame wall), 4:5 487 s; fixes re-render only their range.

## Links
- Code: `~/.claude/skills/paper-cutout/scripts/papercut.py`; film `~/agent-work/motion/T1464/film/film.py`
- Tests: `bash ~/.claude/skills/paper-cutout/tests/smoke.test.sh`
- Design / results: `~/drop/T1464/script.md`, `~/drop/T1464/index.html`
