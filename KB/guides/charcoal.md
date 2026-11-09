# Make a charcoal and chalk drawing on black paper with code (pastel, Kentridge-style animation, a black hole image)

Ticket: T1466 · Last verified: 2026-11-03 by T1466 (73 s narrated film "Every clock is honest", 1746 frames, crop-only 16:9 and 4:5 cuts from one open gate; `tests/smoke.test.sh` 7/7)

## When to use
The owner wants a still or a film that must look hand-drawn in chalk, pastel or charcoal on dark paper: broken chalk strokes
on the paper's tooth, smudged glow, red chalk accents, William Kentridge's erase-and-redraw animation with ghosts, chalkboard
lettering. Also the place for a physically right black hole image (Schwarzschild shadow, lensed thin disk, redshift). Not for
engraving (`/copperplate`), ink wash (`/ink-wash`), riso (`/riso-print`), clean-line comics (`/ligne-claire`), paper cut-out
(`/paper-cutout`) or real 3D (`/code-hero-render`).

## The path we took
Surveyed: Bleser, Sibert and McGee, "Charcoal sketching" (ACM TOG 1988); Majumder and Gopi, real-time charcoal rendering (NPAR
2002); Sousa and Buchanan's graphite model (deposit set by pressure against paper tooth, 1999); libmypaint and Krita charcoal
brushes; Kentridge's erasure films as the master reference; Luminet 1979 and DNGR (*Interstellar*, 2015) for the hole.
Chosen: skill `/charcoal`, numpy + OpenCV + pycairo (inkwash venv), CPU-only and deterministic.
| Piece | One job |
|---|---|
| `Paper` | equalised tooth 0..1, soft tooth, relief, mottled black base, raking light |
| `deposit` / `stump` / `hatch` | pressure -> coverage on the tooth; smudged chalk; LOD strokes along world coordinates |
| `Frame` | trois-crayons composite (chalk, charcoal, sanguine, ember on black) and the photograph of the sheet |
| `Sheet` | cairo chalk-stick lines with tapered ends, Caveat lettering, erase discs |
| `schwarzschild.Hole` | orbit table u(b, phi) -> per-pixel disk radius, azimuth, image order, redshift, intensity, shadow |
| film (T1466) | scenes draw into sheets; the hole into coverage maps; ghosts; captions chalked per cut |

## Exact commands
```bash
PY=~/.local/opt/inkwash/bin/python; S=~/.claude/skills/charcoal
bash $S/tests/smoke.test.sh                                   # 7 PASS lines, about 6 s
cd ~/agent-work/motion/T1466/film
$PY render.py look/a "t=1,12.5,24,44" 4 && $PY sheet.py look/a.jpg 2 960 look/a/16x9/*.png   # look-dev stills
$PY render.py draft 0:1746:12 12                              # 2 fps draft, about 3 min
heavy run --ticket T<n> -- $PY render.py frames all 12        # both crop-only cuts from the 1920x1350 open gate
$PY audio/score.py && ./encode.sh ~/drop/<T> && ./deliver.sh ~/drop/<T>
$PY ~/agent-work/motion/T1451/measure.py audio/mix.wav audio/vo.wav 0.8 timeline.json   # bed under the voice
```

## Pitfalls (measured)
- Zero pressure must leave bare paper: `smooth(-soft, soft, P - (1 - tooth))` inked about 10 % of the sheet as white speckle.
- A laid-line term at 0.22 in the tooth broke every stroke into horizontal dashes; 0.07 keeps a hint of Ingres paper.
- Strokes at 6.5 px spacing read as fingerprints; s 9-10 px, width 1.1, pressure x1.25 read as chalk. Strokes without a
  smudge under them read as scratches.
- Dim caption words at alpha 0.42 broke up on the tooth; deposit at full pressure and lay the coverage at 0.46.
- Stylised light bending `vy += 2y/r^3 dx * k` bends by 4k/b in total: k = 9 sent a "passing" ray through the hole and out.
- Speed: about 2 s a frame with OpenCV threads, 10-13 s single-threaded. 12 fork workers without `cv2.setNumThreads(1)`
  oversubscribed (load 18, draft 0.85 frames/s); capped, the final ran at 1.34 frames/s (1746 frames in 1303 s, `heavy run`).
- A nested `( ... ) &` inside a background shell died with the shell after 44 frames; make the render the background command.
- Sound: the falling watch's ticks drop in pitch and level as it reddens (an audible redshift); bed median 34.6 dB, minimum
  21.6 dB under the voice, bed above 6 kHz -56 dB.

## Links
- Code: `~/.claude/skills/charcoal/scripts/{charcoal,schwarzschild}.py`, film `~/agent-work/motion/T1466/film/`
- Tests: `bash ~/.claude/skills/charcoal/tests/smoke.test.sh`
- Result: `~/drop/videos/every-clock-is-honest-16x9.mp4`, `~/drop/videos/every-clock-is-honest-4x5.mp4`; script.md (beats, facts and sources, survey) pruned with the T1466 drop folder (T1505)
