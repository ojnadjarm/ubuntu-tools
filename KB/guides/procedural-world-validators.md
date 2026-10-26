# Procedural world validators (z-fight, floating, overlap, stairs, materials) and hallway streaming

Ticket: T1405 (from Mooblox T1374 r20, T1382, T1386, T1389, T1394, T1397) · Last verified: 2026-10-27 by `test -e` on the test files
below and the before/after counts in their commit messages

## When to use
- Generated content shows a glitch: flicker or z-fighting, props floating or cutting into each other, stairs facing the wrong way,
  wrong materials on model parts, or a pop or stutter when the next area loads.
- Applies to any procedural world or scene: three.js (Mooblox), Godot (/world-pipeline), pixel scenes (/pixel-scene).
- Not for hand-built levels: there, fix the instance.

## The path we took
- **One validator per glitch class, over every seed and shape.**
  - Validators run as unit tests in Node on the generated layout, with no browser.
  - Each counts the class, the test asserts 0, and the commit message carries before → after.
- **Widen the audit to the whole class** the first time. Count every surface kind against every other one (terrain, path, plaza,
  stair landing, cliff, beach, props), not only the pair in the still.
- **Fix the generator, not the instance.**
  - Stairs climb from the low walkable level to the high one, face their approach, and keep a 1.5 m clear landing at both ends.
  - Props stand only where the ground holds their whole footprint, and keep clearance from other clusters; designed attachments
    are listed as exceptions.
  - Each coplanar pair is separated by a layer offset or merged.
- **Hallway streaming** (owner's idea: "literally the 'hallway' load").
  - Measure the worst build time of the next area, and make the corridor or bridge walk at run speed longer than it, plus a margin.
  - Start building on entry, and post worker results in parts to keep the main-thread peak small.
  - Fog or haze holds the far end until the build is ready; then the swap happens out of sight.
  - A crossing check asserts 0 pops and 0 inline builds.

## Exact commands
```bash
cd ~/projects/personal/mooblox/client
npx vitest run test/world/coplanar.test.ts test/world/placement.test.ts test/world/stairs.test.ts \
  test/world/kerb.test.ts test/world/surface-audit.test.ts test/world/hallway.test.ts
node tools/surface-audit.mjs            # every kit triangle's atlas layer vs its material family
node tools/perf.mjs ...                 # crossing check (<= 34 ms worst, 0 pops, 0 inline builds); engine class only, under the lock
```

## Pitfalls (measured)
- **The coplanar audit took 3 rounds because each fix covered only the reported pair:**
  - T1382 ground decals: 616/1121/9615 → 0
  - T1386 props: tent see-through 209 → 1, sign flicker gone
  - T1389 every terrain surface kind: 513/475/890 → 0
  - The owner found each gap by eye.
- **Placement validators (T1386, T1389):**
  - stairs: 0 wrong-facing and 0 unwalkable on 7 worlds
  - kerbs: 0 gaps, overlaps or crossings
  - floating props, flags and landmark rims: 11 → 0
  - prop-prop intersections: 19 → 0
  - Seeded terrace centrepieces then reused the same rules (T1397, validator 0/0).
- **The material audit found what stills missed** (T1374 r20): 535 wrong-layer parts (38.3k tris in 59 of 97 models: roofs as brick,
  frames as shingles), plus one runaway vertex that made house E a 98 km vertical line since round 2.
- **Validating orientation alone is not enough.** A stair facing an activity prop head-on is unusable even when it points the right
  way. Check reachability (walk up and down), not only direction (FLAWS2 item 9c).
- **Hallway numbers (T1394):**
  - bridges 6 → 38 m (worst low-tier build 1.9 s + 1 s at run speed)
  - build pump peak 36 → 7.6 ms/frame
  - low-rig pops 1/3/5/5 → 0
  - 20x30 worst frame 50 → 33 ms
  - Owner: "the last part of the puzzle".
- **Render only the current area.** Kids drawn on far islands looked wrong against far stand-ins (owner, round 1). Draw characters
  only in the current area; far areas get HLOD on high tiers and cards on low.
- **These are content tests:** tier `content` in `change-class`, so `tsc` + `vitest related`, no perf gate. Only the hallway and
  streaming changes are `engine`.

## Links
- Code: `~/projects/personal/mooblox/client/src/world/` (placement, stairs, kerb, hallway, far-real, span-layer)
- Tests: `~/projects/personal/mooblox/client/test/world/{coplanar,placement,stairs,kerb,surface-audit,hallway,island-streamer}.test.ts`
- Evidence: `~/agent-work/research/2026-10-26/playtest/FLAWS2.md`, `FLAWS3.md`; commits 89d0062 (T1382), dca01c7 (T1386), 3e13a08 (T1389), e962011 (T1394), a2b8f97 (T1374 r20)
- Related guides: owner-playtest-rounds, world-pipeline, pixel-scene, threejs-tsl-perf
