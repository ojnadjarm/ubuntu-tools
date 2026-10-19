# Bevy (Rust) spike: port a scene, warm pipelines behind a dark screen, cross-build a Windows .exe

Ticket: T70 (Bevy spike) · Last verified: 2026-09-24 by `cargo test --profile fast` (9/9 pass, cached build 0.3 s) and the run JSONs in `T70/bevy/runs/`

## When to use
- Evaluating or starting a Bevy 0.19 port, or any Rust/wgpu app that must ship a Windows .exe built on this Linux laptop.
- Not the pick for the Atelier game: T70 chose Godot (Bevy is pre-1.0, has no editor and few assets or UI kits).
  So this guide is a one-off record with no skill. Start from the spike's code, not from a template.

## The path we took
- Toolchain: rustup in `~/.cargo`, `~/.rustup` (stable 1.98.1), targets `x86_64-pc-windows-gnu` and
  `wasm32-unknown-unknown`. apt: `mingw-w64 libasound2-dev libudev-dev libwayland-dev libxkbcommon-dev vulkan-tools weston wine64 binaryen`.
  `.cargo/config.toml` sets `linker = "x86_64-w64-mingw32-gcc"` for the Windows target. No cargo-xwin, no MSVC.
- Same patterns as the web build, in ECS form: `A01State` resource (single source of truth), a pure ~80-line `Timeline`
  seeked from the voice clock, `AtelierKit` resource of shared material handles (Flyweight), `Beat` as Bevy `States`
  (Warm → Title → Watch → Drive → Done), pure modules (timeline, camera, captions, neuron) unit-tested without a GPU.
- Stutter: Bevy compiles pipelines async on a task pool (a mesh without a ready pipeline is not drawn: pop-in, not a
  stall). A **Warm** beat renders the scene dark until `PipelineCache::waiting_pipelines()` is empty
  (`src/beats.rs` `warm`, `src/perf.rs`). Result: 63 pipelines, **0 compiled after Warm in all 7 runs**.
- Look: HDR + `KhronosPbrNeutral`, Bloom on emissive, MSAA 4×, a procedural room cubemap for
  `GeneratedEnvironmentMapLight`, `ExtendedMaterial` for engravings and pipe flow, masks rasterised by `tools/masks.py`.

## Exact commands
```bash
export PATH=$HOME/.cargo/bin:$PATH; cd ~/agent-work/research/2026-09-24/T70/bevy/atelier
cargo build --profile fast                                    # dev loop: 26–37 s incremental, thin-LTO release is 4–7 min
cargo test --profile fast                                     # 9 pure tests
cargo build --release --target x86_64-pc-windows-gnu          # 18.6 min on a loaded machine; imports system DLLs only
# end-to-end on a private headless compositor (never the owner's screen):
export XDG_RUNTIME_DIR=/run/user/$(id -u)
setsid weston --backend=headless --renderer=gl --width=1920 --height=1080 --socket=bv --idle-time=0 >weston.log 2>&1 </dev/null &
WAYLAND_DISPLAY=bv BEVY_ASSET_ROOT=$PWD target/fast/atelier --mute --autoplay --exit-at-end --log run.json
target/fast/atelier --at 14 --shot out.png                    # deterministic frame at timeline t=14 s
# wine smoke test: weston with --xwayland (prints "xserver listening on display :N"), then
DISPLAY=:N WGPU_BACKEND=vulkan WINEPREFIX=$PWD/wp WINEDEBUG=-all wine atelier.exe --mute --at 14.0 --shot 'Z:\abs\shot.png'
```

## Pitfalls (measured)
- **System rustc is 1.93.1** (`/usr/bin`). Bevy 0.19's dependencies refuse it. Put `~/.cargo/bin` first in PATH.
- **Wine picks DX12 and dies**: `ComputePipeline(Internal("Call failed"))`, then `RequestDeviceError … Device(Lost)`.
  Force `WGPU_BACKEND=vulkan` under wine. Under Xvfb it hit a winit monitor-mode assertion; weston `--xwayland` worked.
  The zip ships `run-dx12.bat` (`set WGPU_BACKEND=dx12`) for the owner's PC. Neither backend has run on real Windows.
- Bevy passes `cache: None` to wgpu, so second launches rely only on the driver cache: Warm 1.5–3.6 s first launch,
  0.6–1.9 s second (Mesa cache). DX12 uses FXC unless `dxcompiler.dll` ships or the `statically-linked-dxc` feature is on.
- GPU cost is not lower than the web build: 23 ms at 900p and 35 ms at 1080p on Iris Xe, vs ~20 ms for WebGPU three.js.
  Idle still renders every vsync: add a reactive or fps-capped loop.
- Bevy's default ambient light washes the dark studio: insert `GlobalAmbientLight::NONE`.
  Intel ANV drew speckle pixels, lavapipe was clean (`runs/shot-w20-*.png`).
- Disk and time: `target/` is 7.4 GB. Cold Windows cross-build 18.6 min, wasm 10.6 min (while sibling agents compiled).
- Web: 12 MB wasm (2.7 MB gzip, 1.6 MB brotli). It compiles pipelines synchronously, and WebGL2 has no compute. Not viable here.
- Subagents may not write `report.md`: the spike's findings live in its StructuredOutput and `architecture.md`.

## Links
- Code: `~/agent-work/research/2026-09-24/T70/bevy/atelier/` (`src/{beats,perf,timeline,kit,materials,voice}.rs`, `Cargo.toml`, `.cargo/config.toml`)
- Runs: `T70/bevy/runs/` (`e2e.json`, `f-*.json`, `m-*.json`, `measure.txt`, build logs, shots)
- Design / results: `T70/bevy/architecture.md`, `T70/options.md` (scores, rejection reason, critic) · build: `~/drop/t70/bevy/atelier-bevy-win64.zip` is gone since 2026-09-25 (a copy is in `~/.local/share/Trash/files/`)
