# Godot 4: build a Windows .exe from this Linux laptop, with shaders baked so play never stutters

Ticket: T70 (Godot spike), T70b (Godot web) · Last verified: 2026-09-24 by re-exporting the spike under a private headless weston (baker ran, 332 steps, same size as the spike's .exe) and `tests/run.gd` 11/11 PASS in 0.4 s

## When to use
- Porting a scene or game to Godot 4.7 Forward+ and shipping a Windows zip, or measuring first-launch vs second-launch
  shader cost. Pair it with the installed skills `/godot-export` (presets, CLI) and `/godot-gdscript` (typed GDScript).
- Not for the web: a Godot web export is Compatibility (WebGL2) only, with no WebGPU and no bake (see pitfalls).

## The path we took
- Editor `~/.local/opt/t65/Godot_v4.7.2-stable_linux.x86_64` (reused from T65), templates
  `~/.local/share/godot/export_templates/4.7.2.stable/` (Windows + Linux + web, 360 MB kept). No account, MIT.
- Port of the Atelier opening with the web build's patterns kept: `app.gd` composition root, director (Mediator),
  beats (State), own seekable timeline (state = f(t)), memoised material kit (Flyweight: one pipeline per material kind),
  `voice.gd` clock = playback position + time since last mix − output latency. Architecture: `T70/godot/architecture.md`.
- Stutter: no hand-written warm-up. Godot 4.4+ ubershaders + pipeline precompile at node-add time + the 4.5 shader
  baker at export. Measured: **0 pipelines compiled after frame 1** in all 4 runs.
- `project.godot`: `rendering_device/driver.windows="vulkan"`, `fallback_to_d3d12=true`. Presets `Windows`, `Linux`,
  `Linux-nobake`, `Web` with `shader_baker/enabled=true`, `embed_pck=true` (`project/export_presets.cfg`).
- Built-in probe: `-- --probe=out.json --auto` records first frame, per-frame CPU/GPU ms and pipeline compiles per source.

## Exact commands
```bash
G=~/.local/opt/t65/Godot_v4.7.2-stable_linux.x86_64; cd <project>
$G --headless --import                                    # first time: builds .godot/
$G --headless --path . -s tests/run.gd                    # SceneTree test runner, exit code = result
# export WITH a display, or the baker is skipped. Private compositor, never the owner's screen:
export XDG_RUNTIME_DIR=/run/user/$(id -u)
setsid weston --backend=headless --renderer=gl --socket=gd-exp --width=1280 --height=720 --idle-time=0 >weston.log 2>&1 </dev/null &
WAYLAND_DISPLAY=gd-exp timeout 300 $G --display-driver wayland --path . --export-release Windows /abs/out/Game.exe >exp.log 2>&1
grep -o 'Started Baking shaders ([0-9]* steps)' exp.log   # no line = no bake
# stop weston by the PID from `pgrep -x weston -a`, not `pkill -f` (that also matches your own shell)
# smoke-test the .exe under wine (Vulkan through llvmpipe, slow but complete):
WINEPREFIX=$PWD/wp WINEDEBUG=-all xvfb-run -a -s "-screen 0 1280x720x24" wine Game.exe --resolution 1280x720 -- --probe='Z:\abs\probe.json' --auto
```

## Pitfalls (measured)
- **`--headless` export silently skips the shader baker.** The spike's headless Linux and Linux-nobake binaries were
  byte-identical (73,952,512 B). With a display: "Started Baking shaders (332–344 steps)", 76,122,072 B. The third-party
  `/godot-export` skill shows `--headless` exports: fine for web and servers, wrong for a baked desktop build.
- Under a headless weston the **Linux** export finished writing and then never quit (killed at 300 s, output complete).
  The Windows export quit by itself in ≤10 s. Always wrap exports in `timeout` and check the log.
- Bake value (Iris Xe, GPU contended): first 3D frame cold **17.5 s baked vs 44.2 s unbaked**. Second launch 4.0 vs 7.2 s.
  The cold baked launch is still one **11.2 s frozen frame** (frame 1 compiles 7 specialization + 8 surface
  pipelines). It needs a live loading screen before any user sees it.
- Numbers are thin: one run each, GPU 93–100 % busy from sibling benches before 3 of 4 runs (`measure/contention.txt`).
  Wait for a quiet GPU (`wait-for --until` on `gpu_busy.sh`) before measuring.
- The bake was for Vulkan. D3D12 (the fallback, and the default for new Windows projects since 4.6) was not baked or tested.
- Export time: Linux 19–27 s, Windows 17–32 s, web 25 s. The .exe is 112 MB with the pck embedded. It is unsigned, so SmartScreen warns once.
- Web export (T70b): 10.1 MB gzip wasm and every launch redoes wasm compile + 140 shader compiles (freeze 2.0 s cold,
  1.7 s second). Engraved labels came out blank. Fog, SSR and SSAO are lost. `.pck` is identical with the baker on.
- Wine `--headless --quit-after 30` only proves the binary starts. Use xvfb + `--auto` for a real run (reached `done`).

## Links
- Code: `~/agents/research/2026-09-24/T70/godot/project/` (`src/`, `main.tscn`, `export_presets.cfg`, `src/perf/probe.gd`)
- Tests: `project/tests/run.gd` (11 checks, headless); measuring: `T70/godot/measure/{run.sh,analyse.py,summary.txt}`
- Design / results: `T70/godot/architecture.md`, `T70/options.md` (scores + critic), `T70/godot-web/measure/summary.md`
- Skills: `~/.claude/skills/godot-export/`, `~/.claude/skills/godot-gdscript/` · build: `~/agents/research/2026-09-24/T70/godot/build/windows/AtelierGodot.exe` (the `~/drop/t70/` zip is gone since 2026-09-25)
