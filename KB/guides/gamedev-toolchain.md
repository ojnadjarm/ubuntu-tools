# Game dev toolchain: Godot headless export/run on the iGPU, RenderDoc capture, Tracy profile

Ticket: T440, T454, T457 · Last verified: 2026-10-19 by T457 `cpp-vk-run.sh` (120 frames, 0 validation errors), `godot-smoke.sh` runs (wayland/xwayland/xvfb + RenderDoc), a Tracy capture, and T454's 5 pipeline scripts (artefacts `~/drop/T454/`)

## When to use
Building, exporting, running or profiling a game / real-time 3D scene on this machine. Skill `/gamedev` holds the recipes.
Not for Blender (T439) or browser learning games (`/explainer-engine`).

## The path we took
Godot 4.7.2 (std + .NET) official binaries in `~/opt/gamedev/`, symlinked `godot`, `godot-mono` in `~/.local/bin`; RenderDoc 1.46 tarball; Tracy 0.14.1 built from source; the rest from apt (validation layers, glslc, clang/lld/mold/ninja/ccache, dotnet 10, Krita, GIMP, Inkscape, gltfpack, assimp, OpenAL).
UE5 rejected: Epic-linked account, 60-225 GB, iGPU. Full table: `~/agent-work/research/2026-10-19/T440/STACK.md`.
Offscreen display = `weston --backend=headless --renderer=gl` (real GPU), not Xvfb.

## Exact commands
```bash
S=~/.claude/skills/gamedev/scripts
$S/godot-smoke.sh                                   # export fixture + 5 s on Iris Xe, SMOKE fps lines
$S/godot-smoke.sh --display xwayland --renderdoc ~/agent-work/gamedev/rdc
renderdoccmd thumb -o /tmp/t.png ~/agent-work/gamedev/rdc/smoke_frame*.rdc
./app & tracy-capture -a 127.0.0.1 -o run.tracy -f; tracy-csvexport run.tracy
vulkaninfo --summary
$S/asset-pipeline.sh OUT                    # Blender -> glb -> gltfpack LODs + KTX2 -> Godot import check
$S/godot-perfgate.sh --runs 3 --csv perf.csv   # fps gate: exit 1 regression, 3 skip (load1 >= 8)
$S/godot-test.sh --junit out.xml [PROJECT]  # GUT headless
$S/shader-check.sh *.vert *.frag            # glslang + spirv-val + spirv-cross reflect
$S/cc0-fetch.sh polyhaven rock_wall_08 OUT  # + OUT/LICENSES.csv
$S/new-cpp-game --build ~/src/mygame      # C++ SDL3 + Vulkan template (vcpkg, clang+mold+ccache)
$S/cpp-vk-run.sh --frames 120 ~/src/mygame/build/dev/game   # weston headless, validation on, rc 2 on errors
```

## Pitfalls (measured)
- Xvfb: no DRI3 -> llvmpipe, 8.2 fps; weston headless: Iris Xe, 186.5 fps (same scene, 1280x720).
- RenderDoc 1.46 lacks Wayland WSI: Godot drops to OpenGL3 silently; xwayland capture gave a 7.3 MB Vulkan `.rdc` at 132.7 fps.
- No frame-N flag in `renderdoccmd`; `rd-trigger.so` (LD_PRELOAD, in-app API) triggers after `RD_DELAY` s. `qrenderdoc --python` hung headless.
- Tracy GUI cmake needs libssl-dev, libdbus-1-dev, libcapstone-dev, wayland/xkbcommon/egl/freetype dev packages; its GCC `-flto` link fails under `-fuse-ld=mold` (undefined `tracy::OpsList`), default ld works (503 objects, ~20 min at -j12 nice).
- Export 13 s, binary 71 MB; first second of a run is shader compile (fps 1-90).
- `godot-mono --import` aborted once on a fresh C# project; rerun clean.

- T454: apt gltfpack 0.22 has no BasisU (`-tc` errors); upstream 1.3 in `~/opt/gamedev/gltfpack-1.3`. Godot 4.7 aborts import on `KHR_mesh_quantization`: pass `-noq`. Demo: 62976 -> 31488 -> 6296 tris, 1.45 MB -> 0.19 MB, all 3 imported with a 512x512 KTX2 texture.
- T454: same fixture ranged 105-297 fps within 20 min while other agents rendered on the GPU (load1 8-40): compare only quiet-machine CSVs. 2 of ~25 smoke runs hung after Wayland init with no fps (cause not found; perfgate retries once, raw log `PROJECT/run.log`; weston wait now 20 s).
- T454: GUT 9.7.1 runs on Godot 4.7.2 (3 tests, 0.4 s); a failing assert gives rc 1 and `failures="1"` in JUnit.

- T457: package manager = vcpkg manifest (builtin-baseline pinned) over Conan 2 (pip + profiles) and apt libsdl3-dev (not portable). First configure builds SDL3 1.7 min + vk-bootstrap 29 s (142 s total); after that the vcpkg binary cache makes a clean build 4.7 s configure + 5.5 s compile, ccache rebuild 3.8 s + 0.6 s, 1-file edit 0.4 s.
- T457: vcpkg's static volk has no platform defines; the template links the system-independent `volk::volk` and lets SDL3 create the surface, so no `VK_USE_PLATFORM_*` is needed. vk-bootstrap gets volk's `vkGetInstanceProcAddr`.
- T457: clang 21 warns `-Wmissing-designated-field-initializers` on `{.sType = ...}`; the template turns it off.
- T457: one render-done semaphore per swapchain image, not per frame in flight, or the validation layer flags the present semaphore reuse. Negative control (no PRESENT_SRC barrier) gave 10 errors in 10 frames and rc 2.
- T457: MAILBOX under headless weston: clear-only loop runs about 1600 fps, so 120 frames last 0.08 s; use `--frames 3000` for per-second FPS lines.

## Links
- Code: `~/.claude/skills/gamedev/scripts/{new-cpp-game,cpp-vk-run.sh,godot-smoke.sh,rd-trigger.c,asset-pipeline.sh,godot-perfgate.sh,godot-test.sh,shader-check.sh,cc0-fetch.sh}`, fixtures `~/.claude/skills/gamedev/fixture{,-tracy,-assets,-test,-shaders}/`
- Tests: `~/.claude/skills/gamedev/scripts/godot-smoke.sh` (prints `SMOKE done ... avg_fps=`)
- Design / results: `~/agent-work/research/2026-10-19/T440/STACK.md`, `~/agent-work/research/2026-10-19/T454/ARCH.md`, `~/agent-work/research/2026-10-19/T457/ARCH.md`, template `~/.claude/skills/gamedev/templates/cpp-vulkan/`
