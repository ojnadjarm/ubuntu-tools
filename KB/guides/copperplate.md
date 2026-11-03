# Make a copperplate engraving with code (line hatching, Escher-like, a narrated engraved film)

Ticket: T1465 · Last verified: 2026-11-03 by T1465 (89 s narrated film "Room for one more?", 2135 frames per cut, both cuts native; `tests/smoke.test.sh` 7/7)

## When to use
The owner wants a still or a film that must look like a copperplate or steel engraving: burin lines that follow the surfaces,
cross-hatching, an old print with a plate mark, Escher, Doré or Piranesi line work, banknote-style hatching. Not for riso print
(`/riso-print`), ink wash (`/ink-wash`), clean-line comics (`/ligne-claire`), paper cut-out (`/paper-cutout`) or real 3D
(`/code-hero-render`).

## The path we took
Surveyed: Ostromoukhov, "Digital Facial Engraving" (SIGGRAPH 1999; lines along a parametric grid, width set by tone); Praun et al.,
"Real-Time Hatching" (SIGGRAPH 2001; tonal art maps, line insertion by mip level); Blender Freestyle and Line Art, and
screen-space engraving filters over 3D renders (shower-door lines). Chosen: skill `/copperplate`, numpy + pycairo + OpenCV.
A scene gives each pixel a tone and two world coordinates. The burin lines are iso-lines of those coordinates, with
level-of-detail line insertion, so they move with the world and stay evenly spaced to the vanishing point. It is CPU-only
and deterministic.
| Piece | One job |
|---|---|
| scene (film.py) | analytic raycast (corridor: walls, floor, barrel vault; street: facade, coach, wheels, ground, sky) or a 2D camera (register) -> T, a, b, contour ink |
| `family` | one line family: LOD from the coordinate gradient, odd lines fade as they crowd, width from tone, flicks, wobble |
| `engrave` | tone -> line family + oblique cross family (T > 0.5) + lozenge dots (T > 0.8) |
| `Sheet`, `Overlay` (film) | cairo figures, plaques, ribbons, per-glyph perspective lettering, tapered `swell` cuts |
| `Press` | laid paper, plate tone, plate-mark emboss, ink spread and sheen, fixed paper with boiling ink |

## Exact commands
```bash
PY=~/.local/opt/inkwash/bin/python; S=~/.claude/skills/copperplate
bash $S/tests/smoke.test.sh                                   # 7 PASS lines, about 2 s
cd ~/agent-work/motion/T1465/film
$PY look.py 16x9 2,9,26,38.8 look/a && $PY sheet.py look/a.jpg 2 960 look/a_*.png   # look-dev stills, ~1 s each
heavy run --ticket T<n> -- ./render_all.sh                    # frames/16x9 and frames/4x5
python3 audio/score.py && ./encode.sh ~/drop/<T> && ./deliver.sh ~/drop/<T>
python3 ~/agent-work/motion/T1451/measure.py audio/mix.wav audio/vo.wav 0.8 timeline.json   # bed under the voice
```

## Pitfalls (measured)
- The anti-aliased line `clip(w + 0.5 - d)` still inks 50 % at zero width: blank paper filled with ghost lines until it
  became `clip(min(w + 0.5 - d, 2w))`.
- Width noise ±10 % at 11 px and ink-density noise ±6 % at 24 px read as cloudy dirt in the darks (small gaps change a lot);
  ±3 % at 28 px and ±2.5 % at 90 px are clean.
- Cross lines at 90 degrees to the first family gave a mechanical grid of white dots; an oblique family (b = z + 0.55 y) gives lozenges.
- Converging contours made a black star at the vanishing point: scale contour width by fog and by bay density
  (`clip((P/|grad z| - 4)/10)`), and fade tone to paper by 1/(1 + (t/16)^2).
- One affine text matrix for a long name on a receding wall squeezed it into its neighbours: one matrix per glyph.
- Wide "snowman" figures read as clip art; slim frock-coat silhouettes with the head at 1/9.5 of the height read as staffage.
- A queue walking along the camera's line of sight merged into one black blob, even 1 m to the side. A paper-white gap
  (hpx/50, 1.2-3.5 px) stroked round each dark figure, drawn far to near, cut out of the figures behind, separates them.
- Fading figures out near the camera left half-transparent ghosts over the hatching: let side figures leave the frame, and bring
  walkers in out of the fog at the vanishing point instead of from behind the camera.
- Oblique cross lines at b = z + 0.55 y beat against the first family into moire on long side walls; b = z + 0.18 y on walls is calm.
- File size: lines that boil on twos make every frame new. CRF 20 gave 192 MB for 89 s at 16:9; CRF 24 gave 107 MB with
  SSIM 0.983 against the PNGs (CRF 28: 0.978, but the dots in the figures and the fine vault lines smeared).
- Speed: about 1 s a frame single-process at a 1790x887 plate, but only 1.8 frames/s wall with 12 fork workers
  (memory-bound numpy): 2135 frames took 1200 s for 16:9 (0.56 s/frame wall) and 814 s for 4:5 (0.38 s/frame wall) under `heavy`.

## Links
- Code: `~/.claude/skills/copperplate/scripts/copperplate.py`; film `~/agent-work/motion/T1465/film/film.py`
- Tests: `bash ~/.claude/skills/copperplate/tests/smoke.test.sh`
- Design / results: `~/drop/T1465/script.md`, `~/drop/T1465/index.html`
