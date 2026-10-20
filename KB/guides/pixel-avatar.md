# Build pixel-art character sprites (NPC avatars) with lit sheets, normal maps, portraits and real walk cycles (`/pixel-avatar`)

Ticket: T705 (method from T702), hands T712 · Last verified: 2026-10-20 by `tests/selftest.sh` PASS (now with hand checks) + rebuilding DarkSaddler, Luna, Grok and Mira with the hand model (408 frames + 16 portraits, 266 s wall, 3347 s CPU)

## When to use
A game needs character sprites at T702 quality: 4 directions, idle/walk/talk/signature rows, normal + emissive maps for Godot 2D
lights, 96 px portraits. Not for tiles or maps (T703), title/key art (T704), or image-model sprites (T701, rejected by the owner).

## The path we took
Survey: the T701 "universal" recipe builder (lost to T702 in the owner's pick), image models (no consistent 4-direction volume),
and the T702 hand-built SDF characters (chosen by the owner: "702 wins"). Chosen: package T702 as-is and refine only its walks.
Architecture (skill `~/.claude/skills/pixel-avatar/scripts`):
| Module | Job |
|---|---|
| `core.py` | SDF primitives, `Model` (smooth groups, stamps, lines, dots), sphere-tracing renderer -> ramp-quantised pixels, outlines, normal map |
| `hands.py` | `add_hand()`: palm + two-segment fingers + thumb per grip state (open/relaxed/hook/fist/grip on a prop axis), wrist bend `point`, cuff; returns the forearm end |
| `rig.py` | palette ramps, `ik`, `gait` (keyed walk), `foot` (heel-toe roll), `swing_hand`, `yaw`, `follow` (spring-damper), `root_path` |
| `<char>.py` | data + `pose(anim, f)` (all knobs) + `build(anim, f)` (geometry from the pose); `templates/villager.py` is the start |
| `build.py` | multiprocessing render of every row x 4 directions + portraits -> PNG sheets + `layout.json` (rows, frames, `step_px`, glow track) |
| `preview.py`, `sheet.py`, `new-avatar` | iterate one anim; owner review sheet/maps/MP4; scaffold |
Walk design: the classic 4 key poses per step (contact, down, passing, up) at 8 frames; the stance share and the springs give each
character its own gait (elder: stance 0.64 + cane staff + robe; ranger: 0.55, long stride; knight: 0.66, deep down pose, rolling shoulders).

## Exact commands
```bash
S=~/.claude/skills/pixel-avatar/scripts
$S/new-avatar mira ~/agent-work/research/<date>/<T>/chars
python3 $S/preview.py --src ~/agent-work/research/<date>/<T>/chars --zoom 4 mira walk /tmp/mira-walk.png
python3 $S/build.py --src ~/agent-work/research/<date>/<T>/chars --out ~/agent-work/research/<date>/<T>/out mira
python3 $S/sheet.py --src ~/agent-work/research/<date>/<T>/out --out ~/drop/<T> mira
~/.claude/skills/pixel-avatar/tests/selftest.sh
```
T702 sources (3 NPCs) rebuild: `~/agent-work/research/2026-10-19/T702/rebuild.sh <scratch>` (sheets, Godot lit scene, drop).

## Pitfalls (measured)
- Render cost: without culling a villager frame took 3.2 s CPU; the coarse 1-ray-per-pixel pass (`core.CULL`) made it 0.66 s, pixel-identical on 7 test frames (Mira walk/wave, DarkSaddler cast/walk, Luna draw/walk, Grok guard). Before culling, Mira's build was 1008 s CPU at load 20; after it, 318 s.
- Load matters: the 3-NPC build (312 frames + 12 portraits, before culling) took 11 min wall at load ~21. Check `uptime` first.
- A solid SDF robe hides the feet whatever the stride: DarkSaddler showed 0 boot px until the hem cut was raised by 6 units over the leading foot (now about 9 px).
- Springs whose f0 is near 2 per cycle resonate with the bob: Grok's plume at f0 1.9 swung by about ±4.5 units and flickered in the front view; at f0 2.6 with gain 1 it swings by ±1.1.
- New pose knobs must default to the old pose: a shoulder shift tied to `hipx` changed Luna's idle and talk rows and her portraits. A pixel diff of the non-walk rows caught it. After the fix, only the walk rows differ (3/3 NPCs, albedo, normal and emissive).
- T702 `preview.py` ignores `SIZE` (Luna renders 8% small); the skill's `preview.py` applies it.
- T714 r2: a cuff or vambrace wider than the palm (Grok `dsteel` 2.25, forearm 2.1) hides the hand under the 22 deg camera whenever the swing puts the hand behind the elbow (walk_down hand px went 22 -> 0 on 4 of 8 frames). Keep the walk rest hand forward of the elbow (Grok rest z 2.0 -> 4.6: 20-23 px on every frame). The hand probe gate is every frame >= 8 px, not half.
- T714 r2: in a Godot canvas shader, `TEXTURE` read inside a helper function does not compile (the rim drew nothing), and passing it as a `sampler2D` argument renders but logs `custom_samplers.has(...)` from shader_compiler.cpp; inline the read with `#define`.
- `pkill -f preview.py` is blocked by the fleet hook (it matches its own shell); bracket the pattern: `pkill -f '[p]review.py'`.
- Stamps, lines and dots are drawn after projection, so they do not turn with the yaw. Keep them a few pixels in size and give them a `facing` vector so they hide on back views.

## Hands (T712)
Survey: no pixel-level hand tutorial for 60-80 px sprites turned up (Lospec has 0 under the "hands" tag; saint11 gives only GIFs). The rules below are craft practice: a mitten at least 1 px wider than the wrist with square ends, a thumb bump, a value break at the cuff, a warm dark selective outline, the fist over the grip with the prop showing above and below, and the same pixel count from frame to frame. Chosen: an SDF mitten in `hands.py` plus a pass in the core (`Model.sel`) that applies to hand materials only.
- Before: sphere hands 1.7-2.2 units across (about 3 px), the same width as the forearm cone, and the sleeve's round tip ate half of each. Mira's linen sleeve and skin were the same value. DarkSaddler's staff and Grok's sword hilt ran through the ball.
- Pitfalls (measured): HAND 0.95 still read as a stump, so use 1.1-1.35. The grip hole must sit inside the fist (`hand - 1.8 d - 0.85 n`); at `0.95*PALM` along d the staff showed in front of the knuckles. Plain skin AO on a 4 px hand makes it brown, so give the hand material `ao=0.25`. A palm-up hand seen end-on from the front stays dark: turn it sideways with `point` and add `bias`. A hand in front of the orb (cast) hid it, so the orb moved up 1.4 units. Stamps (buckle) and lines (bowstring) drew over hands until `overlay` learned the hand mask.
- Diff vs T705 (albedo), near the hands / elsewhere: DarkSaddler 5876/3, Luna 3782/0, Grok 4606/0, Mira 6431/40. The rest are seam pixels from ray-march step changes. Normal maps drift by 1-17 levels near seams.
- Results: `~/drop/T712/` (before/after x8 boards, sheets, 4 MP4s, lit Godot clip). Sources: `~/agent-work/research/2026-10-19/T712/chars` (tools: `crops.py`, `quick.py`, `dbg.py`, `diffmask.py`).

## Links
- Code: `~/.claude/skills/pixel-avatar/` (SKILL.md, scripts/, templates/villager.py, tests/selftest.sh); T702 sources `~/agent-work/research/2026-10-19/T702/`
- Tests: `~/.claude/skills/pixel-avatar/tests/selftest.sh` (gait invariants, follow() periodic, one lit frame + normal map, new-avatar refuses overwrite)
- Results: `~/drop/T705/` (before/after MP4, sheets, Mira); old walk frames `~/agent-work/research/2026-10-19/T705/old-out`, `old-walk/`
