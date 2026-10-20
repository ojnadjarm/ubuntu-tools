# AI Avatars world pipeline: build, validate and render a Godot game world from a spec

Ticket: T714 · Last verified: 2026-10-20 by `world-pipeline/tests/selftest.sh` (7/7) and the round-2 integration numbers in T714/NEXT.md (suite 21/21, tour 98.6 s)

## When to use
Rebuild, check or extend a world of the AI Avatars game (`godot/agent-world`: Magic Forest, Darkwood, later interiors). Not for one plant (`/pixel-foliage`), one character (`/pixel-avatar`) or a standalone scene outside the game (`/pixel-scene`).

## The path we took
- Exists: `/pixel-scene` (T703/T709) makes lit, walkable map art from a scene.json, `/pixel-foliage` (T715) makes rigid-piece plant atlases. Tiled/TileMaps were dropped: grid look, no per-prop normal maps, no code-made art (PLAN decision 2).
- Chosen: a world spec = pixel-scene scene.json + a `game` block (spawn, zones, landmarks, props, extras, terraces). `build_world.py` runs the skill build, the walker check (`reach.py`), the foliage atlases (`world_foliage.py`), the extras hooks, then `export_world.gd` writes `world.tscn` (Background, Art, Walls, Props, SpawnPoints, Zones, Landmarks). At runtime `world_art.gd` builds layers, lights, shaders and particles; images load with `Image.load_from_file` (no import step).
- Gates: `validate_world.gd` (MAPSCALE: >= 3840x2160, >= 10 zones, landmarks per screen, reachability with FOOT_RADIUS 6, >= 2 raised levels, night lights, density), the suite (`tests/run_tests.tscn`), stills under headless weston (`tools/render/run.sh`).

| Piece | Path (under the project) |
|---|---|
| spec, generator, hooks | `tools/worldgen/worlds/<id>.json`, `<id>.py`, `<id>_extras.py` |
| build | `tools/worldgen/build_world.py`, `export_world.gd`, `world_foliage.py`, `terrace.py` |
| runtime | `scripts/world_art/*.gd`, `shaders/world/`, `scripts/world_builder.gd`, `scripts/pixel_zoom.gd` |
| checks | `tools/worldgen/validate_world.gd`, `tools/render/{run.sh,fps_walk.sh,mf_check.sh,dw_check.sh,water_probe.py}` |
| all assets | `tools/build_assets.sh` |

## Exact commands
```bash
W=~/.claude/skills/world-pipeline/scripts/world.sh     # each verb = heavy run --ticket T<n> -- nice -n 19 <cmd>
$W --dry all darkwood ~/drop/T<n>/                     # print the plan
$W --ticket T<n> build darkwood
$W --ticket T<n> validate darkwood                     # MAPSCALE pass|fail
$W --ticket T<n> still darkwood 2230,870 2 ~/drop/T<n>/pool.png
$W --ticket T<n> tests                                 # once per ticket
cd ~/projects/personal/ai-avatars/godot/agent-world
heavy run --ticket T<n> -- nice -n 19 bash tools/render/dw_check.sh /tmp/dw         # Darkwood stills + probe + p99 <= 16.7 ms gate
heavy run --ticket T<n> -- nice -n 19 bash tools/render/mf_check.sh /tmp/mf         # Magic Forest readability
```

## Pitfalls (measured)
- Owner works on this machine: every build, render, tour and suite goes through `heavy run` + `nice -n 19` (T775); one full suite per ticket.
- Tests: use `res://tests/run_tests.tscn`; `-s tests/run_tests.gd` hangs (it extends Node). Child boots use `-- --offline` so McpServer does not fight for port 8975.
- Build cost: `build.py` on a 1920x1080 spec = 80 s wall, 0.5 GB RSS (PLAN). Foliage atlases reached 778 MB (Magic Forest) and 353 MB (Darkwood) at 108 frames per big tree, risky on the Iris Xe. r3: big trees tracked at 4 fps (36 cells), cells trimmed to the opaque union, 4 conifer variants, normals loaded as RG8 (Godot's canvas shader reads only .xy) -> 253.5 MB MF / 107.9 MB DW (`python3 tools/render/atlas_bytes.py assets/worlds/*`, budget 256 MB, also fails on a static reed). Next lever: shrub variants 6 -> 4 (about -14 MB). Reeds are the pixel-foliage `reed` preset.
- Agent paths: Theta* line-of-sight cut 3 px (FOOT_RADIUS*0.5) into walls; the nav grid had no bridge cells, so the Mirror Lake goal moved from (2090,893) to (1975,893) (NEXT item 3).
- Map size vs window: PixelZoom grew the widest view with the stretch factor (a 2560x1440 window saw 2.25x a map); it is now capped at 1920x1080 art px (r3 zoom-1).
- fps "min" counted frames per whole second: min 77 hid a 60 ms frame; gate on p99 frame time <= 16.7 ms.
- `assets/` is gitignored and rebuilt; `assets/worlds/<id>/world.json` is hand-written prose and is not regenerated: back it up first.
- Darkwood glow is ON (owner, 2026-10-20); interiors and audio slots are planned, not built: `T714/INTERIORS-PLAN.md`.

## Links
- Code: `~/projects/personal/ai-avatars/godot/agent-world/tools/worldgen/`, `scripts/world_art/`; repo notes `~/projects/personal/ai-avatars/CLAUDE.md`
- Tests: `~/.claude/skills/world-pipeline/tests/selftest.sh`; `godot --headless --audio-driver Dummy --path . res://tests/run_tests.tscn`
- Design / results: `~/agent-work/research/2026-10-19/T714/{PLAN.md,NEXT.md,INTERIORS-PLAN.md}`; owner picks `T697/PICK.md`
