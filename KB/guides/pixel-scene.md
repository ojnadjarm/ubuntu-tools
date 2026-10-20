# Lit, living pixel-art map scene in Godot from a scene.json (pixel-scene skill)

Ticket: T709 · Last verified: 2026-10-20 by building the Blossom Ford Shrine from the template (make-scene, walker 7/7, selftest PASS)

## When to use
Use it for a whole map or level as lit, animated pixel art with collisions: night forest, shrine, river, waterfall, camp. Not for single plants (`/pixel-foliage`), characters (`/pixel-avatar`) or title/key art (T704 README).

## The path we took
Survey:
1. Tiled/LDtk with asset packs needs art we do not have.
2. A Godot TileMap gives a grid look and no per-prop normal maps.
3. The fleet's T703/T707 slice is drawn entirely by code, and the owner judged its quality.

Chosen: generalise T703/T707 into a pipeline driven by scene.json. T704's techniques (phase loop, night lighting on bright albedo, haze) stay in the template.

Flow:
1. `scene.json` feeds `terrain.py`, `props.py`/`flora.py` and `/pixel-foliage` (through `foliage_bridge.py`).
2. `placers.py` places everything; `graph.py` writes `godot/art/built.json` and the PNGs.
3. `templates/godot/main.gd` builds nodes, lights, particles, shaders and collision at runtime.
4. `render.sh` renders under headless weston, `reach.py` runs the walker check, and `loop.py` makes the crossfaded MP4.

## Exact commands
```bash
S=~/.claude/skills/pixel-scene/scripts
$S/new-scene ~/agent-work/research/<date>/<T>/myscene             # template: templates/shrine.json
python3 $S/build.py <dir>/scene.json <dir>/godot && python3 $S/preview.py <dir>/godot /tmp/p.png 2
$S/render.sh <dir>/godot still /tmp/s.png 120
python3 $S/reach.py <dir>/scene.json <dir>/godot /tmp/s.png /tmp/walk.png
$S/make-scene <dir> ~/drop/<T>                                     # still.png, walker.png, loop.mp4
~/.claude/skills/pixel-scene/tests/selftest.sh                     # 17 s, no GPU
```

## Pitfalls (measured)
- Cost: the shrine builds in 8 s with pixel-foliage (3 s with the T707 stand-in). A still takes 9 s. `make-scene` takes 74 s wall and 3.3 min CPU.
- Godot can stall at start under headless weston. One `make-scene` took 210-218 s instead of 45-74 s. `render.sh` retries 3 times and fails red if no file appears.
- A light inside a stone prop washes it white (stone lanterns at energy 1.3). Fix: lower the prop's detail by 0.14 and use energy 0.7, radius 56.
- The hokora light (energy 1.6, radius 130) plus the moon pool (2.0) blew the plaza out to white-green. Hokora 1.0/100 with the moon pool at 1.3/140 reads right.
- GPUParticles do not repeat with the period, so the loop is a 30-frame crossfade. With `t = j/fade` the seam was 0.92 against a 0.77 max step. With `t = (j+1)/fade` (last frame = head) it was 0.88 against 0.87, and 0.89 against 0.81 in the final build.
- The tilt-shift `post.gdshader` blurs the top 14%, so crowns there go soft. Set `look.dof` to 0 (the shrine template does) or keep crowns lower.
- pixel-foliage draws a whole tree as one sprite (crown, trunk and contact shadow; pivot = ground). The T707 stand-in splits trunk and canopy layers. `PFPlacer` scales trees x1.25 to match the T707 sizes.
- Steep plateau edges leave gaps between the per-column face bands. `terrain.plateau` adds 6 px side walls; without them the walker climbs the cliff.
- `pkill -f` patterns must be bracketed (`'[g]odot'`).
- `new-scene` and `make-scene` have no `--help`: usage is their line-2 comment (T846: `new-scene --help` fell through to `mkdir --help`).

## Links
- Code: ~/.claude/skills/pixel-scene/ (SKILL.md, scripts/, templates/, reference/scene-spec.md)
- Tests: ~/.claude/skills/pixel-scene/tests/selftest.sh
- Design / results: ~/agent-work/research/2026-10-19/T709/shrine/, ~/drop/T709/; sources T703, T707, T704 under ~/agent-work/research/2026-10-19/
