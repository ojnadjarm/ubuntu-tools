# Godot 4 web export for GitHub Pages (single-threaded, raw PNG art, offline mode)

Ticket: T1031 · Last verified: 2026-10-20 by export + headless Chromium (Iris Xe, ANGLE Vulkan): title in 2.4 s, world loaded, 0 console errors

## When to use
Putting a Godot 4.x game in a browser page on a static host with no COOP/COEP headers (GitHub Pages, the local `sites` mirror).
Not for a desktop export (`/gamedev`), not for hosts that can set cross-origin isolation headers (threads export is faster there).

## The path we took
Survey: Godot's own `web_nothreads_*` templates (installed with 4.7.2) run without SharedArrayBuffer; Pages limits are 100 MB per file
(GitHub warns at 50 MiB) and about 1 GB per site; the game already had an `--offline` mode, passed through `GODOT_CONFIG.args`.
The export runs on a temp copy, so the project tree never gets `.import` files or imported textures.

| Step | Why |
|---|---|
| `variant/thread_support=false` preset | no COOP/COEP on Pages |
| `importer="keep"` .import for every art PNG (temp copy) | the game reads PNGs with `Image.load_from_file`; imported PNGs ship only as .ctex |
| `include_filter="assets/*.png, assets/*.json, *.json"` | non-resource files are not exported otherwise |
| `exclude_filter` second world, tools, tests, unused specs | keeps `index.pck` < 50 MB |
| sed `"args":[]` → `["--","--offline"]` in index.html | no LLM gateway on the web; `OS.get_cmdline_user_args()` sees it |

## Exact commands
```bash
# the script is archived (owner chose video + stills, 2026-10-20); copy it back into <project>/tools/web/ and the preset to <project>/
cp ~/agent-work/archive/T1031-web-export/tools-web/export_web_lite.sh <project>/tools/web/ && cp ~/agent-work/archive/T1031-web-export/export_presets.cfg <project>/
bash <project>/tools/web/export_web_lite.sh <outdir>   # nice -n 19, ~15-60 s
python3 -m http.server 8791 --bind 127.0.0.1 -d <outdir>   # any static server; no special headers
```

## Pitfalls (measured)
- First export imported 4,822 PNGs into `.godot/imported` and shipped .ctex: `Image.load_from_file` then fails on export. Fix: keep-imports on a copy.
- `FontFile.load_dynamic_font(res://…ttf)` reads the raw .ttf, which an export never ships (include_filter does not add sources of imported files): title text rendered as boxes. Web-lite patch: `f.data = (load(path) as FontFile).data`.
- `ProjectSettings.globalize_path("res://x")` still works inside the pck (resource_path is empty, the relative path resolves through PackedData).
- Sizes, Magic Forest only: wasm 39.5 MB, pck 50.1 MB → 49.7 MB after excluding the unused 0.43 MB `scene.json`. Lossless PNG recompression saved 0.4 MB of 52 MB: not worth it.
- Playwright MCP's default browser renders WebGL on the CPU: screenshots time out (5 s) and load hits 11. Use a standalone chromium with `--use-angle=vulkan --enable-gpu --ignore-gpu-blocklist`: 50-60 fps.

## Links
- Code: `~/agent-work/archive/T1031-web-export/` (export_web_lite.sh, export_presets.cfg); not in the ai-avatars repo
- Tests: portfolio kit in T1031 (`gallery/#ai-avatars` → Load and start → `[world] Loaded`)
- Design / results: `~/projects/personal/portfolio/CLAUDE.md` (gallery section)
