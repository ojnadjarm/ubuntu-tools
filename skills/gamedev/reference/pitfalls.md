# gamedev reference: measured pitfalls

Each line: symptom → measured number → fix or knob (T-id). `tests/gamedev-docs.test.sh` keeps the names real.

## Measured pitfalls
- **Xvfb has no DRI3 -> Vulkan falls back to llvmpipe: 8 fps vs 187 fps on Iris Xe** under `weston --backend=headless --renderer=gl`. Use weston. (T440)
- **RenderDoc 1.46 has no Wayland WSI**: under Wayland Godot loses `VK_KHR_wayland_surface` and silently drops to OpenGL3. Capture under `weston --xwayland` + `--display-driver x11`. (T440)
- RenderDoc has no "capture frame N" flag; `scripts/rd-trigger.c` (LD_PRELOAD, built to `~/opt/gamedev/rd-trigger.so`) calls the in-app API after `RD_DELAY` s (default 2), or at frame `RD_FRAME` (interposes `dlsym` to wrap volk's `vkQueuePresentKHR`). RenderDoc 1.46 has no Wayland WSI (`cpp-vk-run.sh --x11`) and exposes lavapipe as Vulkan 1.2, so 1.3 games capture only on the Iris Xe. `qrenderdoc --python` hung headless (only the xcb Qt plugin exists) - do not use it. (T673)
- First second of every run is pipeline compile (fps 1-90); judge FPS on t >= 2. (T440)
- `godot-mono --import` aborted once (core dump) on a fresh C# project; the rerun was clean. (T440)
- Audio: Godot always `--audio-driver Dummy`; the C++ template always `--frames` or `--replay` (+ `--audio-out F.wav` to hear it offline). No sound, never the TV. (T440)
- Tracy GUI: GCC LTO + `-fuse-ld=mold` fails to link; build it with the default linker. (T440)
- `vkconfig`, `hotspot`, KTX tools are not in Ubuntu 26.04 apt; use env vars (`VK_INSTANCE_LAYERS`, `VK_LOADER_DEBUG=all`) and `perf report`. (T440)
- **VMA default 32 MiB blocks** → template VRAM 22 → 86 MB → keep the defaults (real games fill blocks); set the gate with
  `scripts/cpp-ci --vram-mb`, do not shrink blocks to 4 MiB. (T610)
- **FXAA as a 2nd full-screen pass** → 1080p post zone +0.24 min / +0.30 median ms vs a 0.15 ms budget on Iris Xe; a
  discard-only pass costs the same → `--aa off` for timing runs; folding it into the post pass is T784. (T688)
- **Absolute paths in compile flags** → cpp-golden recompiled 3/19 TUs every run; a 2nd copy hit 69.5 % → `scripts/cpp-ci`
  sets `CCACHE_BASEDIR`, `CCACHE_NOHASHDIR=1`, `-fdebug-prefix-map`, exe-relative data dirs: 386.5 → 15.7 CPU s, 98.3 %. (T667, T680)
- **Raw `cmake --preset` builds missed that cache** → cpp-play/audio/collide 151.9/164.3/167.9 CPU s a nightly run → the
  template dev preset carries `CCACHE_BASEDIR=${sourceDir}`, `CCACHE_NOHASHDIR=1` and the prefix map. (T718)
- **gcc C++20 module scan flags** → ccache `unsupported_compiler_option` ×20, warm sanitize tree 159.6 CPU s (42 %) →
  `CMAKE_CXX_SCAN_FOR_MODULES=OFF` + ccache + mold: warm build 462.6 → 8.8 CPU s (1.9 %). (T665)
- **clang-tidy uncached** → 35-63 s per template run → `scripts/cpp-tidy` keeps a per-TU `$BUILD_DIR/.tidy-cache`: warm
  0.31 s; `CPP_TIDY_NOCACHE=1` forces a full run. (T591, T649)
- **A temp `XDG_CACHE_HOME` rebuilds vcpkg from source** → cpp-hot > 170 s a run, run.sh 2280.1 CPU s → keep the temp dir but
  read the real archives: `VCPKG_BINARY_SOURCES=clear;files,<archives>,read`: 386.1 CPU s. (T692, T698)
- **Timing gates skip on a low GPU clock or a busy machine** → the cpp-hdr ≤ 0.6 ms post gate skipped twice (only at ≥ 90 %
  clock), FXAA above load 4; a `skip … GPU clock` line is not a pass → quote ms only from a quiet rerun. (T674, T688)
- **One flat PSNR floor fails ETC1S colour** → `scripts/asset-pipeline.sh` demo rc 1: 32.8 dB < 35 → per-class defaults
  (ETC1S colour 31, UASTC 38); `--min-psnr` overrides every class, so set `--min-psnr-color` instead. (T577, T584)
