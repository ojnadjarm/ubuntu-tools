# Cast metal (brass, copper) on web text, frames, keys and bars with one SVG lighting filter

Ticket: T332, T334 · Last verified: 2026-10-12 by headless GPU Chrome shots at 400–2560 px, idle CPU pairs and trace counts

## When to use
Display text, card frames, icons or ornaments must read as real cast metal (bevel, brushed or hammered surface, specular that follows the pointer, patina, wall shadow) while staying crisp, selectable text. Not for a full 3D object you orbit around: use three.js there.

## The path we took
- One SVG filter family built in JS (`metal-l/m/s/bar`, scale only): height = `feGaussianBlur(SourceAlpha)` + `feTurbulence` grain → `feDiffuseLighting` (multiply with the base fill, plus an ambient term) + `feSpecularLighting` (add) + a second coloured specular for a fixed bounce light → patina flood in the edge band (`SourceAlpha − blur`) → wall shadow (`feOffset` set from the light) + contact shadow.
- Applied with CSS `filter: url(#metal-m)` to text with `background-clip: text`, to a `::before` ring (border + `border-image: conic-gradient(...)` for reflection bands + corner castings as background images), and to SVG groups.
- One `feDistantLight` aimed from screen centre toward the pointer; the JS updates azimuth/elevation and the shadow offsets, quantised (6°, 4°) and throttled to one relight per 80 ms. CSS vars `--lx/--ly` on `:root` drive gradients, shadows and a tiny parallax.
- Example: `mockups/neon-sin/js/metal.js` + the "Cast metal" CSS block in the sinners-day-web repo; WebGL bar in `js/metalgl.js`.

## Going further (T334): copper and a WebGL-lit bar
- Copper reads as copper only with low diffuse (`lit = SourceGraphic × diffuse × ~1.1 + 0.04`) and strong specular; with T332's 1.15/0.38 it turns flat salmon. Match a reference by measuring mean hue/saturation of bright pixels (target hue 23, sat 0.46 for the owner's pick).
- Extra filter terms that pay off: streaked specular (multiply spec by a thresholded brushed-noise alpha), fingerprint smudges (low-frequency noise subtracting from spec), a grazing-elevation specular masked to the edge band (Fresnel rim), two coloured speculars whose azimuth follows the light at fixed offsets (neon reflections), verdigris only where a wide blur says the groove is enclosed. Rotate the fill gradient (`gradientTransform`) with the pointer so flat faces change too.
- For one hero ornament, a baked height atlas lit in WebGL2 looks clearly more real than any filter: bake the SVG paths in headless Chrome (blur 7 px for height, 22 px for shadow/occlusion), compute normals from height in the shader, Fresnel with copper F0, env strip, Kajiya-Kay highlight along rods. Redraw only on pointer, scroll, resize. Idle cost equal or lower than the filter (it stops re-running a filter on relight).
- Keep the canvas inside the viewport: a shadow pad that pokes past the right edge adds horizontal scroll even with `body { overflow-x: clip }`.

## Exact commands
```bash
# trace a raster logo to one SVG path (3x upscale, red mask) and keep its shapes
python3 -c "…threshold R>110 and R>G+60 into mask.pbm at 3x…"
potrace mask.pbm -s -o logo.svg --flat -t 12 -a 1.0 -O 0.6
# bake the bar ornaments' height atlas from the page's own SVG paths (sinners-day-web mockups/neon-sin)
node tools/bake-bar.mjs index.html img/bar-height.png
```

## Pitfalls (measured)
- Thin hairlines (Bodoni at high opsz) vanish: a strong patina band (k 1.6) and bevel depth 4 darkened every hairline; use k 1, depth ≤ 2.6, a lower optical size, and the smaller filter below 700 px.
- `text-shadow` on `background-clip: text` paints over the metal face: put glows on a positioned `::before` with `content: attr(data-t)` behind an inner filtered span.
- `border-image` ignores `border-radius`: use it only on square frames; pills and arches take a plain border.
- Idle cost is flat (no Paint/Raster events at rest, 10 vs 10 in a 10 s trace); every relight re-runs the filters on screen (about +15 ms per relight on an Iris Xe), so throttle and quantise the light, and do not transition `transform`/`box-shadow` that depend on the light vars (each relight restarted ~40 transitions: style recalc 1.1 s in a 4 s sweep).
- Register `--lift`/`--soft` with `@property` and transition those, not `box-shadow`, so hover animates but pointer relights do not.

## Links
- Code: sinners-day-web `mockups/neon-sin/js/metal.js`, `index.html` (Cast brass block)
- Design / results: `~/agent-work/research/2026-10-12/T332/`
