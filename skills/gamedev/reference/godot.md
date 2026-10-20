# gamedev reference: Godot (engine choice, smoke/RenderDoc, asset pipeline, perf gate, GUT, shaders, CC0, game-ci)

## Engine choice
- **Godot 4.7.2** for everything here: `godot` (GDScript) and `godot-mono` (C#, dotnet 10). Pinned in `~/opt/gamedev/`.
- **Unreal Engine 5: not installed.** Source access needs the owner's Epic-linked GitHub; 60-225 GB; Iris Xe runs the editor only at Low. Say so instead of trying.
- Bevy (Rust) per project with `cargo add bevy` if asked; O3DE not installed.

## Recipes
```bash
S=~/.claude/skills/gamedev/scripts
$S/godot-smoke.sh                                    # fixture: export + 5 s offscreen on Iris Xe, SMOKE fps lines
$S/godot-smoke.sh --seconds 10 path/to/project       # your project (needs a "Linux" preset in export_presets.cfg)
$S/godot-smoke.sh --display xwayland --renderdoc ~/agent-work/gamedev/rdc   # Vulkan .rdc capture
$S/godot-smoke.sh --display xvfb                     # software llvmpipe, only to compare
```
- Without a project the fixture is copied to `/tmp/godot-smoke.XXXX` (71 MB binary): delete it after.
- Project needs a quit path; the fixture's `main.gd` quits after `SMOKE_SECONDS` and prints FPS: copy that pattern.
- Headless only (no rendering): `godot --headless --path P --script res://test.gd` or `--quit-after N`.
- Import first on a fresh project: `godot --headless --path P --import`.
- Validation: run under weston with `godot --path P --display-driver wayland --gpu-validation`.
- C#: `dotnet build` in the project (restores Godot.NET.Sdk 4.7.2), then `godot-mono --headless --path P`.
- RenderDoc inspection: `renderdoccmd thumb -o x.png file.rdc`; open the GUI only for the owner (`qrenderdoc`, X11).

## Pipeline depth (T454)
```bash
$S/asset-pipeline.sh OUT                     # Blender demo -> glb -> gltfpack LOD0/1/2 (+KTX2) -> Godot import check, OUT/report.txt
$S/asset-pipeline.sh --blend a.blend --lods "1 0.25" OUT     # your .blend (or --glb x.glb)
$S/asset-pipeline.sh --glb x.glb --budget b.json OUT        # b.json {"lod0": {"tris": N, "texture_px": N, "bytes": N}}; rc 1 + "ASSET OVER lod0 tris 62976 > 5000" lines
$S/godot-perfgate.sh [--runs 5] [--pin-gpu MHZ] --csv perf.csv [PROJECT]   # settle warm-up (unwritten), 1st call sets baseline; exit 1 if median p50 ms > last-10-PASS baseline x (1+tol) or median p99 ms > x (1+p99-tol, 25)
$S/asset-pipeline.sh --validate a.glb b.ktx2                # T560 Khronos validators: glTF-Validator + ktx validate (also run on every OUT/*.glb); rc 1 on ASSET INVALID
$S/asset-pipeline.sh --uastc-all --min-psnr 35 --max-normal-angle 5 OUT   # T577 KTX2: normals UASTC by default, --uastc-orm/--uastc-all/--etc1s-all, PSNR + normal-angle gate
$S/godot-test.sh [--junit out.xml] [PROJECT]                 # GUT 9.7.1 headless, vendored into addons/gut if absent; rc = failures
$S/shader-check.sh [--out DIR] *.vert *.frag                 # glslang -> spirv-val -> spirv-cross reflect; rc 1 on any failure
$S/cc0-fetch.sh polyhaven|ambientcg|kenney ID OUT [--res 2k] # files + OUT/LICENSES.csv (date,source,id,name,author,licence,url,sha256)
```
- gltfpack: use `~/opt/gamedev/gltfpack-1.3/gltfpack` (upstream, BasisU); apt 0.22 has no `-tc`. Always `-noq`: Godot 4.7 refuses `KHR_mesh_quantization`. Godot reads KTX2 (`KHR_texture_basisu`). Godot also builds mesh LODs on import; gltfpack LODs are for explicit HLOD / other engines.
- Cache (T850): `ASSET_CACHE` (default `${XDG_CACHE_HOME:-~/.cache}/asset-pipeline`, `0` = off) keeps each gltfpack output by sha256(src) + args + gltfpack binary, and the Godot import lines by the glbs + inspect.gd + `godot --version`; a hit prints `ASSET cache hit lod0 <key8>` on stderr, report.txt and rc stay identical. Entries are sha256-checked (a corrupt one is re-made); pruned oldest first to `ASSET_CACHE_MB` (512), staging dirs after an hour. Best-effort: an unwritable or full cache, or an entry pruned mid-hit, never fails a run. Test: `tests/asset-cache.test.sh` (stubs, no encode).
- `--min-psnr-orm DB`: PSNR floor for ORM (occlusion/roughness/metal) KTX2 maps only; default 33 dB for ETC1S and UASTC (`asset_quality.py` MIN_PSNR), `--min-psnr` overrides every class.
- Perf gate exits 3 (SKIP) when load1 >= `--max-load` (8): other agents' GPU renders cost 20-30% fps. Warm-up runs until two consecutive 1 s fps windows agree within 3 % (cap 10 s, `PERFGATE_SETTLE_CAP`). Baseline = median p50 (frame_ms when the scene prints no p50) of the last 10 `PASS` rows; one CSV per project + machine. Rows end `p50_ms,p95_ms,p99_ms,low1_fps,gpu_mhz_p50,throttle_pct,verdict` (gt0 sysfs sampled every 0.1 s, `PERFGATE_GT=` to override/disable; verdict PASS/FAIL/NOISE/ABORT; older CSVs get the header upgraded and their unmarked rows never count). throttle_pct counts only hard gt0 reasons (thermal, prochot, ratl, vr_thermalert, vr_tdc, pl4), not PL1/PL2, which a loaded box sets in most samples (T598); a run with throttle_pct > 20 is written NOISE and re-run once. A smoke run that hangs ends `SMOKE timeout after N s, killed; last output: ...` (output is line-buffered, so `run.log` shows the last stage). `--pin-gpu MHZ` sets rps_min=max via `sudo tee`, restored by trap. The PERFGATE line carries `spread_fps=min-max median_p99_ms= median_p50_ms= gpu_mhz_p50= noise_reruns=`. Test: `tests/perfgate.test.sh`.
- GUT CLI: `-s addons/gut/gut_cmdln.gd -gdir=res://test -gexit -gjunit_xml_file=F`; run `--import` first so `class_name` scripts resolve.
- Shader hot reload: Godot reloads `.gdshader` on save in the editor; at runtime `ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)` and reassign. Native Vulkan: watch with inotify, `glslang -V`, `spirv-val`, then rebuild the VkShaderModule + pipeline after `vkDeviceWaitIdle`. `shader-check.sh` covers GLSL only; check `.gdshader` with a `godot-smoke.sh` run on weston.
- Fixtures: `fixture-assets/` (Blender demo + Godot inspect), `fixture-test/` (Score + 3 GUT tests), `fixture-shaders/` (2 good, 1 broken).

## One-command CI + vertical slice (T479)
```bash
cp -r ~/.claude/skills/gamedev/templates/godot-slice P && P/assets.sh   # CC0 floor/crate/HDRI/sounds -> P/assets (+ LICENSES.csv)
game-ci [--out DIR] [--perf-runs 3] [--capture-seconds 10] [--no-wine] [--keep] P   # = scripts/game-ci, on PATH
```
- Stages: import (rc + ERROR lines) -> GUT -> GLSL check (+ `.gdshader` errors counted from the capture run) -> perf gate -> Linux + Windows export -> Movie Maker capture (`--write-movie` at `--fixed-fps 30`, headless weston, ffmpeg H.264) -> Windows exe `--headless` under Wine 10. `OUT/summary.json`, `OUT/logs/`; exit 1 if any stage fails; perf SKIP is not a failure. `build/` is deleted unless `--keep`.
- Project contract: Linux + Windows presets (with `include_filter=""`, or import logs an ERROR), and the main scene quits after `SMOKE_SECONDS` printing `SMOKE done` (copy `templates/godot-slice/scripts/main.gd`). Autoplay (`Bot`) runs when `SMOKE_SECONDS` is set, so captures show gameplay.
- Export and capture wait (`wait-for`) for load1 < `--max-load` (16). Perf never waits on that: it skips at once (< 5 s) when load1 >= `--perf-max-load` (8), unless `--perf-wait N` waits up to N s for it to drop.

