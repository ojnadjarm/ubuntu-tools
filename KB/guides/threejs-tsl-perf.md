# three.js WebGPU/TSL performance: shader codegen stalls, warm-up, shared materials, on-demand render, MSAA

Ticket: T69 (Atelier perf), T70 web-precompiled · Last verified: 2026-09-24 by T69's adversarial re-measure (`perf/verify.md`) and T70's pixel-identical 8-beat diff

## When to use
- A three.js r18x `WebGPURenderer`/TSL page loads slowly, freezes on first frames or mid-play, or keeps the GPU busy
  when nothing moves. Also before building any new TSL scene: apply the rules up front.
- Not for WebGLRenderer-only apps (the third-party threejs skills cover those; T72 rejected them for TSL work).

## The path we took
- Three diagnosis lenses in parallel (load, frame time, secure context), one fixer on a **copy**
  (`mockups/atelier-perf/`), one adversarial verifier. The look is the product: no lever that changes pixels.
- Causes found, in order: (1) TSL `NodeBuilder.build` on the main thread, ~5–7 s CPU, every visit, no browser cache;
  (2) `warm()` compiled the wrong variant (4 vs 5 lights, wrong render target), so play recompiled 23 pipelines;
  (3) a render every vsync forever, identical frames included; (4) MSAA 4× on a 2-attachment HalfFloat MRT plus an
  MSAA canvas; (5) plain http → no secure context → no WebGPU.
- Fixes, in `atelier-perf/src/`: Flyweight material families (`directions/atelier/kit.ts`, per-part values read with
  `materialReference('userData.…')`), a fixed light set (off = intensity 0, never removed or re-parented),
  `compileAsync` per shot in the exact render context (`scene/host.ts`), a `FrameGate` digest that skips identical
  frames (`scene/gate.ts`), an 11.5 ms tick floor (60 fps on 120–165 Hz), Rapier sleeps when dials rest,
  MSAA only on the scene pass, `?perf=1` overlay (`shell/perf.ts`).
- T70 went further: per-object uniforms via `uniform(0).onObjectUpdate(...)`, `compileInPass` forcing call depth 1,
  and a build-time pipeline snapshot replayed at t=0 (`web-precompiled/app/tools/shader-snapshot.mjs`, `scene/prewarm.ts`).

## Exact commands
```bash
cd ~/agent-work/research/2026-09-23/T65/mockups/atelier/dist && python3 -m http.server --bind 127.0.0.1 18795   # background it
cd ~/agent-work/research/2026-09-23/T65/perf/frame
node run.mjs webgl2 2560 1440 gl-1440 && python3 analyze.py frames-gl-1440.json   # full playthrough, per beat
node bench.mjs webgpu 2560 1440 twist 1       # per-pass GPU cost, A/B variants in one page
node idle.mjs webgl2 1920 1080 1              # does it render while idle?
node why-compile.mjs webgl2                   # which state change triggers recompiles (4 vs 5 lights)
```
Test on `http://localhost` / `[::1]` (secure) or the https drop (`/drop-link`), never `http://<tailnet>:8070`.

## Pitfalls (measured)
- **Unique node graphs = unique pipelines.** Fresh `uniform()`/`color()` per part made ~80 materials → 100–150 programs.
  Families: 153 → 76 programs, GL links 104 → 44; T70: 213 → 52 builds.
- **Warm the exact frame.** Hiding the wall (whose SpotLight was its child) dropped to 4 lights: first frame stalled
  0.46–1.65 s and the wall reveal 1.15–2.18 s (WebGL2). A sync `render()` after `compileAsync` = one 4.4 s task.
- **Render on demand.** Paused and end-screen frames were byte-identical yet redrawn at 144–165 Hz (est. 65–100 % of
  an RX 7800 XT). FrameGate: 0 GPU work while paused, 0 of 4048 changed frames skipped.
- **MSAA** on the MRT scene pass is 40–55 % of GPU time (no MSAA: 30 → 15 ms at 1080p on Iris Xe). The canvas only gets
  a full-screen quad, so its MSAA is pure resolve cost: turn that off. Scene 4× → 2× was not applied (edge pixels change).
- **http kills WebGPU** (`isSecureContext:false`, `navigator.gpu` undefined). WebGL2 costs 20–30 % more GPU here and
  links programs synchronously (`_completeCompile` 4.2 s).
- **What caches:** Chrome's Dawn/ANGLE/driver caches make second loads 7–15× faster on the GPU side. TSL codegen reruns
  every visit and cannot move to build time in r186 (NodeBuilderState is live JS objects).
- **Measure under contention carefully.** Sibling agents inflated wall times 5–10×. The fixer's "37 → 50 fps at 2560"
  was a 12 s window; the verifier measured 31 → 34 over the whole watch. Use GPU timestamp queries and A/B in one page.
- WebGL2 still showed 0.5–1.5 s freezes every ~6–7 s on this Iris Xe in both builds (not long tasks). They are open,
  and may be ANGLE-Vulkan-only.
- Not causes: shadows 0.2–0.3 ms, Rapier step 0.04–0.1 ms, ≤195 draw calls, ≤154 k triangles, GC ≤30 ms per ~3 s.
- Loading: start clip fetch/decode, fonts and Rapier WASM before warm-up. Make Begin clickable at once and queue the click.
  Ready: 4.3 → 2.1 s (WebGL2), 4.7 → 2.5 s (WebGPU).

## Links
- Code: `~/agent-work/research/2026-09-23/T65/mockups/atelier-perf/src/{scene/host.ts,scene/gate.ts,directions/atelier/kit.ts,shell/perf.ts}`,
  `~/agent-work/research/2026-09-24/T70/web-precompiled/app/src/{scene/host.ts,scene/prewarm.ts,directions/atelier/kit.ts}`
- Tests / benches: `T65/perf/frame/*.mjs`, `T65/perf/fix/{load-ab.sh,frames-ab.sh,same.mjs,diff.py}`, `T65/perf/verify/*.mjs`,
  `T70/web-precompiled/bench/`
- Design / results: `T65/perf/{load,frame,context,architecture,verify}.md`, `T65/perf/fix/results.md`,
  `T70/web-precompiled/ARCHITECTURE.md`, `T70/web-ceiling.md` (PlayCanvas/Babylon practice, shipped examples)
