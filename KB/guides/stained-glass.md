# Make stained glass with code (a lit cathedral window, light through coloured glass, a narrated stained-glass film)

Ticket: T1467 · Last verified: 2026-11-03 by T1467 (82 s narrated film "The light never went out", 1958 frames per cut from one open-gate render; `tests/smoke.test.sh` 8/8)

## When to use
The owner wants a still or a film that must look like a real leaded window with light passing through it: Chartres or
Sainte-Chapelle medallions, a rose window, grisaille painting, coloured shafts and pools of light in a church. Not for
engraving (`/copperplate`), ink wash (`/ink-wash`), charcoal (`/charcoal`), paper cut-out (`/paper-cutout`) or real 3D
(`/code-hero-render`).

## The path we took
Surveyed: Mould, "A stained glass image filter" (EGSR 2003); Brooks, "Image-based stained glass" (TVCG 2006); Setlur and
Wilkinson, "Automatic stained glass rendering" (CGI 2006); Voronoi shaders on Shadertoy. All turn a photo into leaded cells;
none model pot-metal glass, grisaille or the light through it. Chosen: skill `/stained-glass`, numpy + OpenCV + pycairo,
CPU-only and deterministic. Pieces are polygons in world units, rasterised to a label map; everything else is per-pixel
arithmetic on that map.
| Piece | One job |
|---|---|
| `labels` | cairo, no antialiasing, piece id as a 24-bit colour -> int label map |
| `render` | per-piece sheet window, density and tint; Beer-Lambert on thickness; lead = distance to a label change; grime; paint; iron; backlight; halation; stone spill; ACES |
| `Paint` | grisaille trace, matte (blurred + stipple), stickwork cleared out of the matte, painted letters (IM FELL) |
| `lancet.py` | Chartres lancet: block-and-pearl border, diamond mosaic with gold nodes, ruby + pearl medallion frames, Voronoi grounds, quarries, saddle bars |
| `church.py` (film) | pinhole camera before the wall plane: cached wall render, floor pools projected along the sun direction, ray-marched shafts, additive motes |

## Exact commands
```bash
PY=~/.local/opt/inkwash/bin/python; S=~/.claude/skills/stained-glass
bash $S/tests/smoke.test.sh                                   # 8 PASS lines, about 4 s
cd ~/agent-work/motion/T1467/film
$PY lookset.py 4,24,40,57,74 look/a 16x9 && $PY sheet.py look/a.jpg 2 960 look/a_*.png   # look-dev stills, ~1.2 s each
heavy run --ticket T<n> -- $PY render.py frames all 12          # frames/16x9 and frames/4x5 from one 1920x1350 gate
$PY audio/score.py && ./encode.sh ~/drop/<T> && ./deliver.sh ~/drop/<T>
$PY ~/agent-work/motion/T1451/measure.py audio/mix.wav audio/vo.wav 0.8 timeline.json   # bed under the voice
```

## Pitfalls (measured)
- Backlight 5.0 washed every colour to pastel; 1.7-1.75 with lead width 0.8 units and a dark lead ambient kept the jewel depth.
- The blue read cyan until linear G was under 0.15 of B (0.026, 0.080, 0.58) and each piece got its own density exp(0.34 u).
- Halation fills thin dark lines: the smoke test measures a lead seam at 0.35-0.53 of the glass beside it and a grisaille trace
  at 0.57, not black. That is the look of a real window; iron bars stay the darkest thing.
- A slanted band edge left no-glass triangles between scene pieces: build full cells, then clip every scene piece to the
  medallion field polygon.
- Border blocks vanished on the straight sides when the outline walk dropped its end points (`o[1:-1]`).
- Captions drawn twice in the 4:5 cut: the 16:9 crop was a numpy view of the open gate; `.copy()` each crop first.
- Church: the wall cache showed as a rectangle and black outside it; a 25-unit feather into procedural masonry with the same
  stone albedo (0.024) fixed it. Ramping the spill and shafts in over 2.8 s stopped the cut opening on haze. Motes drawn as
  alpha were dark dots: add them as light. The floor went black outside the pools: 0.07 ambient plus a blurred bounce.
  Ghost rings in the shafts: blur the shaft glass map (sigma 5 at 1/4 res).
- Unlit glass faded to black reads as a hole; fade it to a dim blue mix.
- Speed: about 1.2 s a frame single-process at 1920x1350; 12 workers under `heavy` (load 12-14) rendered 1958 frames, both
  cuts from one gate, in 1112 s (0.57 s/frame wall, 12620 s CPU). The score measure ran past 120 s on the busy CPU; run it
  in the background.

## Links
- Code: `~/.claude/skills/stained-glass/scripts/{stainedglass,lancet}.py`; film `~/agent-work/motion/T1467/film/{film,church}.py`
- Tests: `bash ~/.claude/skills/stained-glass/tests/smoke.test.sh`
- Design / results: `~/drop/T1467/script.md`, `~/drop/T1467/index.html`
