# Make a risograph print look with code (spot inks, halftone, misregistration, overprint, a narrated riso film)

Ticket: T1463 · Last verified: 2026-11-03 by T1463 (88 s narrated film "Light is two things", 2111 frames per cut, both cuts native; `tests/smoke.test.sh` 7/7)

## When to use
The owner wants a still or film that must look like a risograph print or riso zine: two or three spot inks, halftone dots, grain,
plates off register, a third colour where inks overlap. Not for ink wash (`/ink-wash`), clean-line comics (`/ligne-claire`),
3D renders (`/code-hero-render`).

## The path we took
Surveyed: p5.riso (p5.js, splits art into riso-ready plates: print prep, not emulation), Spectrolite (macOS separations app),
Photoshop riso actions and halftone shaders (one filter over a finished image). Chosen: skill `/riso-print`, numpy + pycairo:
| Piece | One job |
|---|---|
| `Plate` | one ink's master: cairo A8 surface (alpha = ink density) plus merged numpy fields |
| `Press.coverage` | grain-perturbed density against a per-angle halftone threshold map, then starvation, tooth, pinholes |
| `Press.register` | fixed plate offset + per-print jitter + a hair of rotation |
| `Press.print` | Neugebauer overprint of all plates on a textured paper, `OVERPRINT` overrides for fluorescent pairs |
A scene draws into the two plates (shapes, type, physics fields); the press turns them into a print, a new one every 2 frames.

## Exact commands
```bash
PY=~/.local/opt/inkwash/bin/python; S=~/.claude/skills/riso-print
bash $S/tests/smoke.test.sh                                   # 7 PASS lines, about 2 s
cd ~/agent-work/motion/T1463/film
$PY render.py look/s1 16x9 "t=2.4,7.5,22,53,79.5" 11 && $PY sheet.py look/s1 look/s1.jpg 4 480
heavy run --ticket T<n> -- ./render_all.sh                    # frames/16x9 and frames/4x5
$PY audio/score.py && ./encode.sh ~/drop/<T> && ./deliver.sh ~/drop/<T>
python3 ~/agent-work/motion/T1451/measure.py audio/mix.wav audio/vo.wav 0.8 timeline.json   # bed under the voice
```

## Pitfalls (measured)
- Plain multiply of Riso Blue (0,120,191) and Fluorescent Pink (255,72,176) gives navy (0,34,133); a riso overprint reads purple.
  Neugebauer primaries with an override (84,50,148) printed as (90,62,153) in the smoke test.
- `np.random.default_rng` rejects negative seeds (a scene passed `int(ys * 10)` with ys < 0): `wobble` uses `abs(seed)`.
- Full-frame wave fields ran under the captions: clear a print margin and the caption band on every plate after each scene.
- Labels at 22 px over halftone were unreadable at 1080 p; 27-30 px Space Mono on a paper knockout reads.
- A plane wave drawn as vertical crest bands read as "stripes", the film's other motif; wavy rays read as light.
- 18,000 dots drawn as one cairo path (new_sub_path + arc each, one fill) cost well under 0.1 s a frame.
- New grain, jitter and paper on every print made the 88 s 16:9 master 627 MB at crf 16. A 3-state boil over a fixed paper
  (`Press(boil=3)`), content on twos and crf 24 with `-refs 8` and no `-tune grain`: screen scene 57.8 -> 5.8 MB per 10 s,
  moving-wave scene 23.6 MB per 10 s, dots still crisp at 1:1.
- Speed with 12 fork workers under `heavy`: about 0.26 s a frame wall at 1920x1080 with a two-slit field at half resolution.

## Links
- Code: `~/.claude/skills/riso-print/scripts/riso.py`; film `~/agent-work/motion/T1463/film/film.py`
- Tests: `bash ~/.claude/skills/riso-print/tests/smoke.test.sh`
- Design / results: `~/drop/T1463/script.md`, `~/drop/T1463/index.html`
