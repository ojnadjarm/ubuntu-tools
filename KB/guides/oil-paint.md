# Make an Impressionist oil painting with code (visible brushstrokes, impasto, a grey-to-colour reveal, a narrated oil-paint film)

Ticket: T1468 · Last verified: 2026-11-03 by T1468 (77 s narrated film "Mary's room", 1848 frames per cut from one open-gate render; `tests/smoke.test.sh` 8/8)

## When to use
The owner wants a still or a film that must read as oil paint made by a master hand: Monet's poppy field, a Hammershøi grey
interior, Van Gogh or Loving Vincent strokes, impasto under a gallery light, black-and-white to colour. Not for watercolour
or sumi-e (`/ink-wash`), charcoal (`/charcoal`), engraving (`/copperplate`), stained glass (`/stained-glass`) or real 3D
(`/code-hero-render`).

## The path we took
Surveyed: Litwinowicz (SIGGRAPH 1997, strokes clipped at edges), Meier (SIGGRAPH 1996, strokes anchored in the world),
Hertzmann (SIGGRAPH 1998, coarse to fine), Baxter's IMPaSTo (NPAR 2004); filters (anisotropic Kuwahara, OpenCV
`xphoto.oilPainting`) give the "photo with a filter" look. Chosen: skill `/oil-paint`, numpy + OpenCV + pycairo plus a 77-line C
compositor (gcc, ctypes), CPU-only, deterministic. Every picture is a cairo source; strokes are seeded on it once and laid
again every frame.
| Piece | One job |
|---|---|
| `BrushBank` | 18 bristle masters (alpha, second-colour streak, paint height) with pyramids |
| `seed_strokes` | one layer of strokes in plane px: structure-tensor angle, length cut only for crossing strokes, detail gate |
| `broken`, `grey` | broken colour (value, warm/cool, chroma, violet shadows, warm lights); lead white + ivory black |
| `oilc.c` `paint_strokes` | inverse-warps every sprite of a frame in one call (per-row span of the rotated rectangle) |
| `Frame.finish` | raking light on the height map (normals, gloss), linen weave fixed to the screen, vignette |
| `film.py` (film) | planes at depths (room z=1, garden z=2), camera (X, Y, D) eased in 1/(z - D), per-stroke reveal and opacity |

## Exact commands
```bash
PY=~/.local/opt/inkwash/bin/python; S=~/.claude/skills/oil-paint
bash $S/tests/smoke.test.sh                                   # 8 PASS lines, about 2 s
cd ~/agent-work/motion/T1468/film
$PY look.py 3,22.5,28,36,67 look/a && $PY sheet.py look/a.jpg 4 480 look/a_*.png   # look-dev stills, ~0.6 s each + 4 s init
$PY gapcheck.py 6                                             # frames where bare linen would show through the doorway
heavy run --ticket T<n> -- $PY render.py frames all 12        # frames/16x9 and frames/4x5 from one 1920x1350 gate
python3 audio/score.py && ./encode.sh ~/drop/<T> && ./deliver.sh ~/drop/<T>
$PY ~/agent-work/motion/T1451/measure.py audio/mix.wav audio/vo.wav 0.8 timeline.json   # bed under the voice
```

## Pitfalls (measured)
- Per-stroke numpy compositing cost 35-280 us a stroke (0.9 s for 8k strokes); the C compositor does 7.7k strokes in 0.16 s.
- Heights in master px gave cliffs at every stroke edge (an emboss filter, "cobblestones"). Height in units of the half-width
  x 0.14, blurred W/18, and `level` 0.8 (new paint levels the old) read as paint. Round caps read as toothpaste worms; random
  RGB jitter read as rainbow confetti; `broken()` light tints on grey work made white dust: `tints=0` for grey layers.
- A figure dissolved stroke by stroke (rank-wise) looked like confetti or dirt; a uniform opacity fade over 0.5 s reads as a
  ghost walking into the light. Figures that appear do it off screen.
- A wide view through a doorway needs far more of the back plane than the doorway suggests: the 2600x2000 garden ran out by
  up to 218 screen px at the bottom in 231 frames. A reflected "apron" layer (copyMakeBorder REFLECT, strokes seeded only in
  the border, own rng so nothing else re-rolls) took it to 0 (`gapcheck.py`).
- The back plane peeks through gaps between wall strokes (coloured specks on a grey wall): cull its strokes to the doorway's
  projected rectangle (+ half a stroke's reach) while the wall is drawn.
- White flood + impasto = bubble wrap: lower the relief with the flood (0.9 x (1 - 0.75 flood)).
- Depth eased in 1/(z - D) puts a doorway crossing in the last 4 % of a long segment (a 0.75 s whip); add a key at the doorway
  (D 0.86, jamb just on screen) so each plane gets its own ease.
- Speed: init 4 s; about 0.5 s a frame single-process at 1920x1350 (60-80k strokes in view at most); 12 workers under
  `heavy` rendered 1848 frames, both cuts from one gate, in 495 s (0.27 s/frame wall, 5563 s CPU); 8.3 GB of PNGs, deleted
  after the encode (87 + 64 MB mp4).

## Links
- Code: `~/.claude/skills/oil-paint/scripts/{oilpaint.py,oilc.c}`; film `~/agent-work/motion/T1468/film/film.py`
- Tests: `bash ~/.claude/skills/oil-paint/tests/smoke.test.sh`
- Result: `~/drop/videos/marys-room-16x9.mp4`, `~/drop/videos/marys-room-4x5.mp4`; script.md and index.html pruned with the T1468 drop folder (T1505)
