# Paint sumi-e ink and watercolour on rice paper with code (ink blooms, washes, brush strokes, a narrated ink film)

Ticket: T1461 · Last verified: 2026-11-02 by T1461 (85 s narrated film "Everything from one point", 2040 frames at 1920x1350, `tests/smoke.test.sh` 6/6)

## When to use
The owner wants a film or still that must look hand-painted in sumi-e ink or watercolour: ink drops blooming on wet paper,
washes, dry-brush strokes, an ensō, a seal. Not for 3D renders (`/code-hero-render`), blueprint cutaways (`/cutaway-style`)
or pixel art (`/pixel-avatar`).

## The path we took
Surveyed: Curtis et al. 1997 watercolour fluid sim (too heavy for one night), MoXi 2005 ink dispersion on paper fibres (lattice
Boltzmann; we borrowed its look, not its solver), Tyler Hobbs' layered-polygon watercolour. No headless package does this, so
skill `/ink-wash` is a small numpy + OpenCV + scikit-image + cairo engine:
| Piece | One job |
|---|---|
| `Paper` | albedo with fibres, flecks and relief; `tooth` for dry brush; `cost` map where ink runs fast along fibres |
| `arrival` | geodesic arrival time from a seed through `cost` (skimage `MCP_Geometric`): the shape of every bleed |
| `bloom` | core, tide line, inner tide ring, feathered fibre halo from an arrival map and a front `R` |
| `brush` | bristle stroke with ink load per bristle running dry (flying white), press and lift |
| `composite` | Beer-Lambert pigments on paper: sumi, indigo, ochre, vermilion |
The film (`~/agent-work/motion/T1461/film/film.py`) owns the beats: precomputed assets in the parent, `frame(t)` per worker,
moving things as cached sprites with round windows.

## Exact commands
```bash
PY=~/.local/opt/inkwash/bin/python; S=~/.claude/skills/ink-wash
bash $S/tests/smoke.test.sh                                   # 6 PASS lines, about 3 s
cd ~/agent-work/motion/T1461/film
$PY render.py look/s1 "t=0.5,12,30,44" 12 && $PY sheet.py look/s1 look/s1.jpg 4 480
heavy run --ticket T<n> -- $PY render.py frames/final all 12
python3 audio/score.py && ./encode.sh ~/drop/<T> && ./deliver.sh ~/drop/<T>
```

## Pitfalls (measured)
- Kokoro mark syntax is `{name}word`: writing `{point}.` dropped the word from the audio in all 10 clips of the first T1461 render.
  A one-word sentence (`{stars}Stars.`) has no timed word and stops the renderer.
- Single noise fields look digital: the first fog (fbm mottle) read as smoke, the first wash (thresholded Gaussian field) as
  camouflage. Overlapping blooms (6 for the fog, 80 for the wash) read as painted, through their tide lines.
- Summed fog blooms at c0 0.28-0.42 turned the page black; 0.09-0.15 each over a 0.3 base keeps structure.
- Resized arrival maps must be multiplied by the resize factor; dividing made sprites fill their square patch.
- Polar-remapped noise left a seam at ±π; a sum of `sin(k θ + φ)` is periodic.
- Brush bristles drawn in a few clumps read as 3 parallel lines; even offsets with 1 % jitter read as one stroke.
- Speed at 1920x1350 with 12 fork workers: 0.21 s/frame wall; 2040 frames in 420 s under `heavy`; assets 16 s once.
- `mv-encode --finish film` halation tints a bright paper frame; use `--finish clean`.
- Captions on ink: dark text on paper, light text (`CapL`) only while the fog is dark; T1461's light window ran 2 s past the
  clearing and the caption vanished on pale paper. Unspoken words at alpha `&H8C` read as missing on paper; `&H60` reads.
- mv-review flags a painted hold over 2 s as `frozen` (T1461: blank page 2.2 s, ensō 4.1 s, end card): intended, not a stall.

## Links
- Code: `~/.claude/skills/ink-wash/scripts/ink.py`, film `~/agent-work/motion/T1461/film/`
- Tests: `bash ~/.claude/skills/ink-wash/tests/smoke.test.sh`
- Result: `~/drop/videos/everything-from-one-point-16x9.mp4`, `~/drop/videos/everything-from-one-point-4x5.mp4`; script.md (beats and sources) pruned with the T1461 drop folder (T1505)
