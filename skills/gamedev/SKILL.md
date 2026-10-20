---
name: gamedev
description: Godot 4.7.2 and C++ SDL3/Vulkan games headless here (new-cpp-game, cpp-ci, game-ci). Use for "game", "Godot", "C++ game", "Vulkan", "export a game", "FPS", "RenderDoc", "Tracy", "GUT", "asset pipeline", "CC0 assets". Not for Blender or browser games (explainer-engine).
---

Triggers: 3D scene, frame capture, profile a frame, Vulkan validation, AAA tools, Unreal, LOD, KTX2, perf gate, fps regression, Godot tests, shader validation, SPIR-V, Poly Haven, ambientCG, Kenney, SDL3, Vulkan template, vcpkg, Godot .NET, offscreen GPU run, Intel Iris Xe, Mesa ANV, gltfpack, assimp, Krita, GIMP, Inkscape, Blender to glTF, GLSL, JUnit, licence log, Windows export, gameplay capture, Wine smoke, vertical-slice template, CMake, clang, mold, ccache, weston.

# gamedev: Godot headless loop, captures and profiles

Stack and why: `~/agent-work/research/2026-10-19/T440/STACK.md`. Guide: `guide gamedev-toolchain`.

## Workflow
```bash
S=~/.claude/skills/gamedev/scripts
$S/godot-smoke.sh [--seconds 10] [P]               # export + offscreen run on Iris Xe under headless weston, SMOKE fps lines
game-ci [--out DIR] [--no-wine] P                  # Godot: import, GUT, shaders, perf gate, Linux + Windows export, capture mp4, Wine smoke
$S/new-cpp-game --build ~/src/mygame               # C++ SDL3 + Vulkan template (CMake + vcpkg, clang + mold + ccache)
$S/cpp-ci ~/src/mygame [--stages "configure build golden"]   # C++: build, sanitize, run, perf, profile, tidy, golden (+ opt-in package)
$S/cpp-vk-run.sh --frames 120 build/dev/game       # one validated run, DONE line with avg_fps
```
1. Engine: Godot 4.7.2 (`godot`, `godot-mono`) or the native C++ template. Unreal is not installed (say so); Bevy per project if asked.
2. Run on the real GPU under headless weston, never Xvfb (llvmpipe, 8 vs 187 fps); judge FPS on t >= 2 s.
3. Perf gates skip on a loaded machine (`quiet-gate`); a SKIP is not a failure.
4. No sound, never the TV: Godot `--audio-driver Dummy`, C++ `--frames`/`--replay` (+ `--audio-out F.wav`).
5. At the drop delete `build/`, `vcpkg_installed/` and `/tmp/godot-smoke.*` copies.

## Scripts and knobs
| Script / knob | One line |
|---|---|
| `godot-smoke.sh` | export + timed offscreen run; `--display xwayland --renderdoc DIR` captures a .rdc |
| `godot-perfgate.sh` | fps regression gate on a CSV baseline; exit 1 FAIL, 3 SKIP |
| `godot-test.sh` | GUT headless, `--junit out.xml` |
| `game-ci` | one-command Godot CI, `OUT/summary.json` (template `templates/godot-slice`) |
| `asset-pipeline.sh` | Blender/glb -> gltfpack LODs + KTX2 -> Godot import; `--budget`, `--validate` |
| `shader-check.sh` | glslang -> spirv-val -> spirv-cross reflect |
| `shader-stats` | static SPIR-V cost per shader (instr, arith, tex, branch, loop, barrier); `--baseline` GROW > 10 % rc 1 |
| `cc0-fetch.sh` | Poly Haven / ambientCG / Kenney + LICENSES.csv |
| `new-cpp-game` | scaffold `templates/cpp-vulkan` |
| `cpp-ci` | C++ CI stages: configure, build, sanitize, run, perf, profile, tidy, golden, package |
| `cpp-tidy` | clang-tidy 21, cached per TU (`CPP_TIDY_NOCACHE=1`) |
| `cpp-vk-run.sh` | validated run under weston; `--size WxH`, `--timeout S`, `--no-syncval` |
| `game` flags | `--model`, `--capture N`, `--capture-every DIR`, `--record`/`--replay`, `--audio-out`, `--camera`, `--exposure`, `--aa off` (FXAA default), `--no-shadows`, `--no-ibl`, `--hot`, `--pause-at N` |
| `cpp-ci` gates | `--gpu-tol` 15, `--p99-tol` 25, `--vram-mb`, `--perf-max-load`, `--update-golden`, `--package-max-mb` 60 |
| `rd-trigger.c` | LD_PRELOAD RenderDoc capture after `RD_DELAY` s, or of frame `RD_FRAME` (counts `vkQueuePresentKHR`; cpp-ci perf fail → `OUT/perf/frame.rdc`) |

## Reference (read the one you need)
- `reference/godot.md`: engine choice, smoke/RenderDoc/validation/C# recipes, asset pipeline, perf gate CSV, GUT, shader hot reload, game-ci stages and project contract.
- `reference/cpp-vulkan.md`: Tracy, the C++ template feature by feature (PBR, scene/LOD, shadows, HDR + bloom, GPU zones, collision, audio, skinning, hot reload, packaging, crash stacks) with measured costs and tests.
- `reference/pitfalls.md`: Xvfb, RenderDoc on Wayland, first-second compile, Tracy GUI link, missing apt tools.
