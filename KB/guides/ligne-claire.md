# Draw a ligne claire comic with code (Hergé clean line, flat colour, panels that ink themselves, a narrated comic film)

Ticket: T1462 · Last verified: 2026-11-03 by T1462 (86.5 s narrated film "What makes you you", 2076 frames per cut, both cuts native; `tests/smoke.test.sh` 5/5)

## When to use
The owner wants a film or still that must look like a clean-line European comic: even ink contours, flat colour, panels, narration
boxes, balloons, "TOK!". Not for 3D renders (`/code-hero-render`), ink wash (`/ink-wash`), blueprint cutaways (`/cutaway-style`).

## The path we took
Surveyed: Blender Freestyle / Line Art with toon shading (3D with outlines, reads as a render with a filter), rough.js-style sketch
renderers (wobbly, wrong for ligne claire), pycairo / Skia vector drawing (the medium's own form). Chosen: skill `/ligne-claire`,
pycairo + numpy:
| Piece | One job |
|---|---|
| `lc.py` | kit: Catmull-Rom shapes, even contours, brush-pen strokes, clouds, water ticks, narration boxes, balloons, SFX, paper grain, draw-on |
| `art.py` | subjects: a galley built plank by plank (any plank old or new), a profile figure (planks or dressed), skies, sea, quay, Athens, props |
| `film.py` | the page: panel grid per cut, camera moves between panels and the whole page, one scene function per panel, captions, the red thread |
Every panel is inked (lines grow, staggered) and then coloured when the camera reaches it; future panels stay blank.

## Exact commands
```bash
PY=~/.local/opt/inkwash/bin/python; S=~/.claude/skills/ligne-claire
bash $S/tests/smoke.test.sh                                   # 5 PASS lines, about 2 s
cd ~/agent-work/motion/T1462/film
$PY render.py look/s1 16x9 "t=2,9,25,46,66" 12 && $PY sheet.py look/s1 look/s1.jpg 3 640
heavy run --ticket T<n> -- ./render_all.sh                    # frames/16x9 and frames/4x5
python3 audio/score.py && ./encode.sh ~/drop/<T> && ./deliver.sh ~/drop/<T>
```

## Pitfalls (measured)
- Multiply-blended flat fills fail where shapes overlap (a white cloud on blue sky stayed blue). Fill OVER; multiply the paper grain
  once over the finished frame, in page space so it travels with the page.
- Clouds as one polygon of overlapping arcs showed every inner arc; the upper envelope of the circles gives one clean contour.
- A closed Catmull-Rom through a rectangle's corners overshoots (the square sail bulged above its yard): build straight edges explicitly.
- Sea drawn behind a hull left the underwater planks showing: draw the fore water after every floating hull.
- Line-art pass: coloured strokes (wood grain) read as brown smudges and filled dots popped in before the lines; skip non-ink strokes
  and gate dots with `dots_ok()`.
- Close-ups magnify local-unit dots: trenails at a fixed local radius became blobs at 2.75x; use `2.4 / scale`.
- Sparse panels read as clip art; a harbour town, amphorae, rope coils and tools on the wall made them read as Hergé.
- Speed with 12 fork workers under `heavy`: one-panel views 0.05 s/frame wall, the 12-panel page view about 0.15 s/frame.
- `mv-review` failed holds as "frozen" (3 holds of 2.3-4.4 s): a slow push-in on every panel view (zoom +3 % over 10 s from its draw
  time) cleared them. A 0.95 s pan into a dark panel that inked on bright paper counted 4 flashes/s; a 1.25 s pan, inking on arrival
  and a 1 s colour flood for that panel gave 3 (the limit; 4:5 gave 1).
- `-color_trc`/`-color_primaries` were dropped on a PNG-sequence x264 encode (tags read bt709/unknown/unknown); add
  `-bsf:v h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1`.
- Sound (film rule): bed 27.2 dB under the VO on the worst line, bed above 6 kHz at -58.6 dB.

## Links
- Code: `~/.claude/skills/ligne-claire/scripts/{lc,art}.py`, film `~/agent-work/motion/T1462/film/`
- Tests: `bash ~/.claude/skills/ligne-claire/tests/smoke.test.sh`
- Result: `~/drop/T1462/` (script.md has the beats and sources)
