# Metal display lettering on the web that reads as real in a still: SDF shading in WebGL2 (also three.js extrude, CSS/SVG, Blender)

Ticket: T335 · Last verified: 2026-10-12 by headless GPU Chrome shots at 400–2560 px, idle CPU over the browser tree, Blender 4.2 Cycles renders

## When to use
Headings, card titles or a wordmark must look like cast, enamelled or extruded metal letters standing on a wall (game title screen look), with real, selectable, translatable DOM text. Not for frames, bars or icons (use `cast-metal-css-svg`), not for a 3D object the user orbits (plain three.js scene).

## The path we took
- Four techniques built on the same words and wall (spikes under `~/drop/T335/spikes/`): S1 CSS `text-shadow` extrusion + SVG lighting filter, S2 SDF in WebGL2, S3 three.js `ExtrudeGeometry` with PBR, S4 Blender Cycles PNG. S2 won: closest to the references, smallest, text stays live. `~/drop/T335` is gone since 2026-10-13 (a copy is in `~/.local/share/Trash/files/T335/`); the S2 port survives as `~/projects/personal/sinners-day-web/mockups/neon-sin/js/lettering.js`.
- S2 pipeline (`spikes/s2-sdf/sdf-letters.js`, ~250 lines, no deps): for each `[data-lt]` element, find every word's DOM box (`Range.getClientRects`), draw the words with the element's computed font into an OffscreenCanvas at 2× → alpha → signed distance field (Felzenszwalb EDT, as in mapbox/tiny-sdf) → two separable 3-tap blurs → R16F texture → one fullscreen-triangle fragment shader: height = bevel profile of the distance (chamfer or quarter-round), normal = finite differences of the height, copper GGX + an analytic "room" env (raking warm key high left, warm ceiling, dim space behind the viewer, pink tube below, red bounce), patina from noise on the flat face, bright worn crest, AO and a soft offset shadow drawn into the alpha around the glyphs. One shared WebGL2 context renders each heading once and `drawImage`s it into a per-heading 2D canvas over the transparent DOM text.
- Render once on load, after `document.fonts.ready`, and on width change (debounced 160 ms). No frame loop: the light is fixed (owner rule: the material must not depend on the mouse).
- Modes: `raised` (chamfer, patina), `round`, `enamel` (copper rim + sunk, domed glossy wine core that reflects the neon). Small sizes (< ~30 px) use `raised`: enamel needs strokes ≥ 3× the rim.
- S3 path when real depth/parallax is wanted (`spikes/s3-three/three-letters.js`): TTF → typeface JSON offline (`ttf2typeface.mjs`, Latin + Spanish subset, 46–52 KB), one `ExtrudeGeometry` per glyph placed at its DOM `Range` box (exact kerning and letter-spacing), faces and sides as two materials (group 0 caps, group 1 sides incl. bevel), PMREM env from a scene of emissive panels, 2D-canvas `drop-shadow` for the wall shadow, three r170 subset built with esbuild.

## Exact commands
The `~/drop/T335` paths below are gone since 2026-10-13 (a copy is in `~/.local/share/Trash/files/T335/`); restore it before the server line, which the `shot.js` and `measure.js` lines need. Only the esbuild line runs as is.
```bash
cd ~/drop/T335 && python3 -m http.server 8771 --bind 127.0.0.1 &                       # serve spikes and protos
node ~/agent-work/research/2026-10-12/T335/tools/shot.js http://127.0.0.1:8771/proto/1/ out.png 1366 900 2 0 "#h-prog|30"   # 2x clip of one heading
node ~/agent-work/research/2026-10-12/T335/tools/shot.js http://127.0.0.1:8771/proto/1/ full.png 1366 900 1 2                # full height (viewport = page, so the fixed wall covers it)
node ~/agent-work/research/2026-10-12/T335/tools/measure.js http://127.0.0.1:8771/proto/1/ 1366 900                      # KB, render ms, pointer and idle CPU
node ~/drop/T335/spikes/s3-three/ttf2typeface.mjs Font.ttf font.json                                                     # three.js typeface JSON
~/agent-work/research/2026-10-12/T335/tools/node_modules/.bin/esbuild entry.js --bundle --minify --format=esm --outfile=three.text.sub.js
blender -b -P ~/drop/T335/spikes/s4-blender/render.py -- "Programa" Font.ttf out.png                                    # S4, Cycles CPU
```

## Pitfalls (measured)
- The EDT of an anti-aliased mask has stair-steps that show as ripples on diagonal chamfers (the A and M legs): two separable 3-tap blurs of the field and a 2 px finite-difference step removed them.
- The face reflects what is behind the viewer: with an env that is dark there the face goes black; with a broad warm fill there (dot 0.5 to the face direction, width 0.48) it washed to cream. Keep a dim warm term on `r.z` only and put the bright key at a raking angle so it lands on the chamfers, not the face.
- Copper F0 times an already orange env double-tints to red (S3 first pass): env panels near-white, let the metal colour do the tint.
- Neon in the env: a pink band at `r.y ≈ -0.4` painted a pink stripe across every face once the face had any curvature; at `r.y ≈ -0.9` it only lights the down-facing chamfers, which is the believable "tube below" bounce.
- Shadow direction sign: sampling the field at `q - offset` (y down) puts the shadow down-right for a key at upper-left; the first pass had it up-left.
- Hairlines thinner than 2× the bevel turn into a ridge or break (Bodoni Moda "M" in the type sheet): use bevel ≤ 0.06 em with didones, heavier cuts (Playfair Display SC Black, Abril Fatface) for metal.
- three.js: `VSMShadowMap` on a big transparent `ShadowMaterial` wall gave a long dark wedge; PCF gave hard blocks; a 2D `ctx.filter = "drop-shadow(...)"` on the output canvas is softer, free and matches S2. Camera distance 1× the width showed long side walls and ghosts; 1.5× the width shows depth without distortion.
- `ExtrudeGeometry` bevel grows the outline outward: `bevelOffset: -bevelSize` keeps the silhouette equal to the DOM glyph.
- Cost (1366 px, Iris Xe, this machine): S2 page 84–94 KB gzip first load, all 13 letter blocks rendered in 154–348 ms once, idle 0.5–0.8 % of a core; S3 page 237 KB gzip (three subset 128 KB gz + font JSON 16 KB gz), 430–480 ms, idle 0.55–0.65 %. The pointer-relit SVG filters of mockup C cost 107 % of a core while the pointer moves; static light: 27–33 % (the wall alone).
- S4 Blender: 64 s per heading at 1800×420, 64 samples, CPU; text is baked, so every copy change and every language is a re-render, and serif tips spike with large bevels on Abril.
- Full-page headless shots with a `position: fixed` WebGL wall show the wall only in the first viewport: shoot with the viewport set to the page height.

## Links
- Code: `~/drop/T335/spikes/s2-sdf/sdf-letters.js`, `~/drop/T335/spikes/s3-three/{three-letters.js,ttf2typeface.mjs}`, `~/drop/T335/spikes/s1-css/index.html`, `~/drop/T335/spikes/s4-blender/render.py`, prototypes `~/drop/T335/proto/{1,2,3}/` built by `proto/build.py` · all `~/drop/T335` paths are gone since 2026-10-13 (a copy is in `~/.local/share/Trash/files/T335/`); S2 port: `~/projects/personal/sinners-day-web/mockups/neon-sin/js/lettering.js`
- Tests: shot and measure scripts in `~/agent-work/research/2026-10-12/T335/tools/` (headless GPU Chrome, `--mute-audio`)
- Design / results: `~/drop/T335/REPORT.md`, `~/drop/T335/refs/refs.md`, measurements `~/agent-work/research/2026-10-12/T335/measure-*.jsonl`
- Related: `cast-metal-css-svg` (frames and bars), `dashboard-threejs-glyph-eye` (idle CPU method)
