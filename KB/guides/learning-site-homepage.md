# ailearning homepage: shared content JSON, promise copy, path map data, mockup lessons

Ticket: T78 (1a content; 1b mockups add their lessons below), T82 port, T83 sheet set, T96 smooth sheet changes · Last verified: 2026-10-20 (T846: paths, `package.json` scripts, content JSON counts, hygiene/bundle-check rules read; no run); 2026-09-25 (T96: frame capture + press trials, no suite run); 2026-09-24 by `npm run ci` green (incl. `tests/e2e/sheet-change.mjs`)

## When to use
Building or changing the `ailearning` homepage, its path map, or any mockup of it: read the copy and the 43 path entries from the
content JSON, never retype them. Not for unit pages (`unit.json`, ticket 4a) or the plate art (guide `cutaway-style`).

## Content (ticket 1a)
**The path we took.** `T76/lanes/curriculum-graph.json` (43 units, 9 rings) + the plan §1.4 fixes + owner decisions, rewritten as
public copy. JSON Schema 2020-12 (ajv-loadable later) + a Python validator (jsonschema 4.19 was already installed; ajv was not).
Checks are small functions in `CHECKS`; private names come from an external deny-list file, never from the repo.
**Source of truth (T82 on):** `~/projects/personal/ailearning/content/homepage.json`, checked by `tools/content-check.mjs` (ajv, same `CHECKS`)
in `prebuild`. The T78 copy + `validate.py` are history and have drifted (U01 `game`): never edit them.

| Key | What a mockup reads |
|---|---|
| `site.promise[]` | 3 promise lines, ≤ 12 words each; pick one per mockup |
| `site.subline`, `site.trust`, `site.sound` | arc line, "Free · no account · open source", narration note |
| `site.cta.{new,returning,phone}` | the one primary per `?state=`; `returning` is a template with `{plate}` and `{beat}` |
| `site.strip[]` | Watch · Drive · Play, one line each |
| `site.credits.drawn` | always `Claude` (owner: credits go to Claude, never his name or handle) |
| `site.licence` | MIT code, CC BY-NC 4.0 plates and narration, OFL fonts, Kokoro Apache-2.0 |
| `rings[]` | 9 rings, `n` + name |
| `silhouettes{}` | 12-part phantom library: id → name + what to draw (dash-dot-dot outline) |
| `units[]` | `id n plate slug ring kind title line minutes requires game silhouette status` |

Rules baked into the data:
- **No questions anywhere.** The plan's per-unit "open question" became `line`, a declarative one-liner; the validator fails on any `?`.
- `game` is set only where a Challenge is designed (U01–U05); every other unit shows its `line` and silhouette.
- `status`: `drawn` (U01 only: a finished plate exists) or `in-preparation` (phantom). `minutes` are estimates: 25 / 20 / 10 lens.
- `requires` feeds "uses: II, IV"; map numerals with `plate` of the required unit. U38 requires U14 (§1.4 fix).
- Side tunnels S1–S8 are not in the file.

**Exact commands**
```bash
cd ~/projects/personal/ailearning
node tools/content-check.mjs                          # schema + path + copy rules (also runs in prebuild)
HYGIENE_DENY=<file outside the repo> npm run hygiene  # generic hygiene plus private names, one regex per line
node --import ./tests/lib/register.mjs --test tests/unit/content.test.mjs   # each check fires on a planted fault
```

**Pitfalls (measured)**
- A 13th silhouette is caught by the schema (`maxProperties: 12`) first, so semantic checks never run on it; a test that adds a
  spare silhouette to prove "unused" fails for the wrong reason. Test "unused" by re-pointing the only user of one (`gears`, U06).
- `hygiene.mjs`'s wording tier includes `\bT\d{2,}[a-z]?\b` and `\bdrop\b(?!-shadow)`: plate copy like "T71" or "drop" fails; write "drops"/"falls".
- The validator returns schema errors alone when there are any; fix those before reading semantic output.

## Mockups (ticket 1b)

### A · Key Plan (T78 1b)
Source (mockups deleted, T320) (`node build.mjs <out>`: validator → pure renderers → one inline HTML, 3.1 kB gz JS).
Drop `~/drop/t76/home-a/` + `ledger/` (gone since 2026-09-25; rebuild from source). Checks: `node tools/shots.mjs <url> <dir>` (18 viewport×state rows, exit 1 on a fault),
`node tools/perf.mjs <url>`, `node tools/interact.mjs <url> <png>`.
- **Walls with no double lines:** each room pads only top+left with the hatch showing through; the plan container pads right+bottom.
  `flex: n 1 calc(n*(cell+gap)+2.6rem)` rows always fill, so no dead gaps at any width; doors move to the top wall on row-start rooms (JS, on resize).
- **CLS 0.106 → 0** by preloading all 5 kit fonts (only 2 were preloaded; the swap reflowed the page).
- **Styles inside `<use>` symbols:** only inherited props and custom properties cross in; drive phantom dashes with `--cd`/`--bw` vars.
- **SVG term labels on phones:** bump font-size in viewBox units under a media query (23 → 34) so terms stay ≥ 13 px at 400.
- **Full-page stills skip IntersectionObserver effects:** scroll the page through before the shot.
- Details row as flex-wrap (not auto-fit grid): a 2+1 grid left a dead cell at 768.

### C · Folio (T78 1b)
Source (mockups deleted, T320) (`node build.mjs <out>`: pure part modules in `lib/` → one inline HTML, JS 3.0 kB gz).
Drop `~/drop/t76/home-c/` + `ledger/` (gone since 2026-09-25; rebuild from source). Checks: `node tools/shots.mjs <url> <dir>` (18 rows, exit 1 on a fault), `node tools/perf.mjs <url> <w> <h>`
(FCP, LCP element, CLS, bytes, DrawFrames in 3 s over a trace), `node tools/interact.mjs <url> <png>` (keys, drag, first-touch callout).
- **T71 plate as static SVG:** porting `layout.ts`/`meters.ts`/`sheet.ts` geometry to strings (y-up helpers, hatch = clipPath even-odd)
  keeps the finished plate in the first paint with 0 three.js; `vector-effect: non-scaling-stroke` holds the 4 weights at every width.
- **Label floor via one CSS var:** a ResizeObserver sets `--lbl = max(30, 12.5 × viewBoxW / px)`; SVG `font: calc(var(--lbl) * 1px)` keeps
  terms ≥ 12 px at 400 without a second composition. Leave viewBox room for the biggest label (Fig. 1 needed −905…815).
- **Hint text on a centre line reads as struck through:** put pencil hints outside the casing with a leader.
- **Dead gap on the verso** beside a tall plate: a flex column with `margin:auto` on a real block ("Explanation of the plate", from U01's
  `line`) splits the space; a wider recto (1 : 1.62, a fold-out plate) grew Fig. 1 by 40 %.
- **Pencil ticks via IntersectionObserver on a tall list never fire** (threshold 0.35 of a phone-long `<ol>`): observe each entry.
- CLS 0.0008 → 0 by preloading all 5 kit fonts. The drop server does not gzip: count 271 kB raw, 39.2 kB gz document.

### B · Exploded Assembly (T78 1b)
Source (mockups deleted, T320) (`node build/build.mjs`: pure `draft`/`parts`/`layout`/`figures` modules → one inline HTML, JS 2.7 kB gz;
`src/assembly.js` is shared by build and runtime). Drop `~/drop/t76/home-b/` + `stills/` (gone since 2026-09-25; rebuild from source). Checks: `node tools/shots.mjs <url> out` (18 rows,
exit 1 on a fault), `node tools/perf.mjs <url> <state>`, `node tools/dial-check.mjs <url>`, `node tools/frames-selftest.mjs <url>`.
- **Draw each part once, reuse by `<use>`:** parts live in a hidden defs SVG; phantom/ink/seated looks are custom properties on the slot
  `<g>` (`--wb --da --hx --core`…) that cross the `<use>` boundary. 3 layout SVGs (1/2/5 rows) picked by media query, joined by match lines.
- **CSS transforms on SVG `<g>` in px equal user units:** sliding parts home by `--dx` keeps CLS 0 and needs no geometry rebuild.
- **Prove the idle-frame zero:** count `DrawFrame` in a 3 s trace, and selftest the counter on a running animation (74 frames) first.
- **Reserve label overhang at row ends** (`over` per part) and caption room under the dimensions, or labels spill past the viewBox.
- **Detail views clipped to their circles** read as drafting details; loose text inside them collides with ticks, so move it to the caption.
- HTML lettering looked small at 2560: `@media (min-width:2200px){.sheet{zoom:1.32}}` fixed it without a second composition.

### Port into the repo (T82, plan ticket 8, 2026-09-24)
Live at `~/projects/personal/ailearning/src/site/homepage/`; preview https://<tailnet-fqdn>:8472/ailearning/ (guide local-sites). Notes `~/agent-work/research/2026-09-24/T82/ARCHITECTURE.md`.
- **Vite plugin, not B's build.mjs:** `plugin.mjs` fills `<!--home:head-->`/`<!--home:body-->` in the root `index.html` with `transformIndexHtml`
  `order:'pre'`, so Vite's own HTML pass hashes the thumbnail `<img>` and puts `/fonts/` preloads under the base. Dev = build, no generated file in git.
- **Live rule:** `status:"drawn"` + `u/<slug>/index.html` exists → `href`; otherwise a phantom, never a link (plugin throws on a drawn unit with no page).
  `tools/link-check.mjs` proves every built href resolves. B's fixture `release` list (U02/U03) was removed: progress never makes a phantom live.
- **Phone fold, don't drop:** parts list + notes in `details[data-fold]`, closed before first paint by an inline script on ≤ 639 px; header on one
  line; smaller how-strip + colophon. 400×860: 5.98 → 3.46 screens. 768 needed 3 detail columns (C sat alone = dead gap).
- **Pitfall: Playwright `fullPage` screenshots drop finished CSS draw-on callouts** (DOM is fine). Set the viewport to the page height, then a normal screenshot.
- **Pitfall: the hygiene leak pattern `/home/` matched `src/site/home/`** — the folder is `homepage`. Ticket numbers are banned in the repo, so
  code TODOs name the feature (`progress store`, `desktop gate`, `stills + path map`); the number map lives in `CLAUDE.local.md`.
- **Pitfall (T94, 2026-09-25): per-row grids can't share a `max-content` track.** Each `.u` row is its own grid, so a fixed Plate track
  (48–72 px) let XXXVIII (4.15 em) overrun its title. Fix: track `max-content` + a hidden zero-height `::before{content:var(--pw)}` ghost of the
  widest numeral in every cell and the header, `--pw` set from content. `home.mjs` "parts list" checks every row at 400–2560.
- Budget (`node tests/e2e/home-perf.mjs [url]`): LCP 72–264 ms (element = H1, the hero is inline SVG), CLS 0, HTML+CSS 25.3 kB gz, JS 2.8 kB gz,
  first visit 136.7 kB / 10 requests, idle DrawFrames 0 (counter selftest 2), 0 audio/three.js. `tests/e2e/home.mjs`: 3 states × 6 views + 8 behaviours.

### Sheet set + sheet change (T83, 2026-09-24)
Notes `~/agent-work/research/2026-09-24/T83/ARCHITECTURE.md`. Every page of the set shares one frame: `src/site/sheet/{sheet.css,frame.mjs,plugin.mjs}`.
- **New unit page = a sheet for free:** link `../../src/site/sheet/sheet.css` before the unit CSS, body `<div class="sheet app"><!--sheet:frame--><div class="field">`
  `#stage` + `#shell` `</div></div>`. `sheetPlugin()` fills the rail from `content/homepage.json` by slug ("Sheet I · The neuron", back link, "Sheet 1 of 43")
  and throws on an unknown slug. The way back is `back(base)` in `frame.mjs`: a drawn outline button ("← Sheet 0", sibling of `.primary`, ink fill on hover,
  blue focus ring) at the start of the rail, outside `.field`; `site.mjs` checks it is ≥ 44 px and uncovered (`elementFromPoint`) in watch, drive and end. The lesson chrome is `position:absolute` in `.field` with `%` widths (not `100vw`). ≤ 639 px: frame chrome off, bare plate as before.
- **Sheet change** = cross-document View Transitions, CSS only, a flat-fold book page turn (turn.js soft-page idea): the earlier sheet is hinged on its
  left edge; forward it turns right to left showing its paper back, back it turns left to right; 1 s, `cubic-bezier(.6,.04,.26,1)`; reduced motion 150 ms
  crossfade. Direction: inline `pagereveal` script compares sheet numbers of `navigation.activation.from` and `location` (`/u/NN-` → NN, else 0) and adds
  type `forward`/`back`. The turning page gets `html.turning` (name `front`, alone in its group); the `.leaf` div (name `leaf`) is always added by the
  new page at `pagereveal` and shows only under `:active-view-transition` (T96: on the old page at `pageswap` it painted one blank frame).
- **Compositor-only turn:** `::view-transition-image-pair(front|leaf)` is a 300vw × 300vh `overflow:hidden` window whose edge is the fold (translateX(P)
  rotate(8deg)); the image inside counter-turns (rotate(-8deg) translateX(-P)) about the same page point so it stays put; the leaf group reflects about the
  fold (`translate(P,50vh) rotate(98deg) scaleY(-1) rotate(-98deg) translate(-P,-50vh)`). All linear in P → two keyframes are exact.
- **Page-turn sound:** CC0 Freesound 119126 (esperri), high-passed 140 Hz, faded, -30 LUFS (narration -16), back variant slowed 6 %; `public/sound/`
  Opus 48k + AAC 64k, 6-9 kB; `bundle-check` requires both and ≤ 20 kB. New page plays it at `pagereveal` (`new Audio().play().catch(()=>{})`).
- **Registration:** header rail and frame of both sheets sit at the same px (checked 768/1366/1920; 1 px at 2560, where both zoom 1.32).
- **Landing framing:** landscape field → the casing across the full width (`stage.across()`), portrait → whole plate; watch timeline untouched.
- Checks: `node tests/e2e/sheet-change.mjs [site url]` (types, animation names, 900-1100 ms, reduced 150 ms, sound per direction, no audio on Sheet 0
  before the click, compositor frames per turn at 1366/1920 from a trace (`PipelineReporter` presented frames between `turn-start`/`turn-end` marks,
  ≤ 2 gaps over 20 ms), rail + way back, frame strip
  `out/shots/sheet-change-{forward,back}-{start,mid,end}.png`); `site.mjs` checks U01 rail, margins, plate span ≥ 99 % on landscape, phone bare.

**Pitfalls (measured)**
- **Opt-in must be inline:** `@view-transition` only in the external CSS fired 1/8 times into U01 (module script before the stylesheet lost the race to the
  first reveal); an inline `<style>@view-transition{navigation:auto}</style>` injected by the plugin: 16/16.
- **Vite's CSS minifier rewrote `animation:.52s cubic-bezier(…) both` to `animation:none`** on `::view-transition-*`: use longhands.
- `document.getAnimations()` after `viewTransition.ready` includes the VT pseudo animations: pause + set `currentTime` for a deterministic frame strip.
- **clip-path animations run on the main thread** (Chromium, trace `compositeFailed` for clip-path): the clip-path turn stalled 2-4 frames at 1920 while
  U01 booted (long tasks 87-137 ms); the transform-only windows: 0-1 frame over 20 ms in 7 runs. rAF deltas are no measure of it (main thread only).
- **Autoplay at `pagereveal`:** Chromium with the real policy (`--autoplay-policy=document-user-activation-required`) plays it (sticky activation carries
  over a same-origin navigation), 10-90 ms after reveal; Playwright WebKit (Safari 26.6 UA) rejects with NotAllowedError → silent, no console error.
  Playing on the old page is no answer: it unloads as the turn starts. `tests/lib/browser.mjs` launches with `no-user-gesture-required`.
- Playwright WebKit on this machine needed `sudo apt-get install libevent-2.1-7t64 libmanette-0.2-0` then `npx playwright-core install webkit`.
- Hygiene's WORDING rule flags the word "drop" (`drop-shadow` is excused by a lookahead): name helpers `clear`, not `drop`.
- The homepage zooms the whole `.sheet` at ≥ 2200 px; a unit sheet cannot (WebGL canvas + pointer maths): scale inset/padding by 1.32 and zoom only `.top` and `.zones`.

### Smooth sheet changes (T96, 2026-09-25)
Notes and numbers `~/agent-work/research/2026-09-25/T96/` (`ARCHITECTURE.md`, `tools/measure.mjs` + `tools/analyze.py`: CDP screencast of every
frame, page events, first-press trials by fold geometry; `tools/run.sh <dist> <label>`). Code: `src/site/sheet/{turn.js,press.js}` inlined by
`plugin.mjs`, `sheet.css` (`html.hold`, `.leaf`, `.btn.pressed`); e2e `tests/e2e/transitions.mjs` (written, not yet run).
- **Hold:** the new page adds `html.hold` at `pagereveal` (all `::view-transition-*` animations `paused`) and removes it after two frames +
  `document.fonts.ready` + `sheet:ready` when `html[data-hold]` is set (U01 from 1024 px); cap 2.5 s. The sound plays at the release.
- **Press guard:** `.pressed` at the click (in the old snapshot), later presses `preventDefault` until `pageshow` (bfcache) or `navigateerror`;
  same-path link = scroll to top. **Turn input:** a click on `<html>` during a turn (the overlay takes every click) after the first 300 ms sets
  `playbackRate` so the turn ends in ~150 ms, then `elementFromPoint(x,y).closest('a,button,…').click()`.

**Pitfalls (measured)**
- A `.leaf` appended to the old page at `pageswap` can be presented before the capture: a whole frame of blank paper (1920, +51 ms, ink 0).
- An on-demand WebGL canvas with `preserveDrawingBuffer:false` is captured **white** in the old snapshot (1366 back: 21 white frames in 2 of 6
  runs). Rendering one frame at `pageswap` did not help (30 white frames at 1920); `preserveDrawingBuffer: true` did (0).
- `blocking="render"` on a module script ends at evaluation start, not at its top-level await: the plate drew 173–401 ms (1×) / 774–1123 ms (4×)
  after the reveal. The frame fonts also finished after the reveal on both sheets (5 faces). Hence the hold + `sheet:ready` + all 5 frame fonts preloaded.
- During a transition hit testing goes to `<html>`: a click on a visible button did nothing (30/50 answered at 1366, old method). A `:active` press
  lasts one frame and the turn's ease-in hides ~250 ms, so people click twice (2 navigations per double click before the guard).
- Speculation Rules prerender can't be verified under Playwright/CDP ("PrerenderingDisabledByDevTools"): left out.
- Keyframes carry their own easing (`cubic-bezier(.6,.04,.26,1)`): `getComputedTiming().progress` is linear; solve the bezier for the fold position.
- Measuring: `Page.startScreencast` survives navigations; re-send `Emulation.setCPUThrottlingRate` on every navigation; luminance maths in int32
  (int16 overflowed to ink 1.0); never `pkill -f` a pattern that is in your own command line.

## Links
- Content: `~/projects/personal/ailearning/content/{homepage.json,homepage.schema.json}` + `tools/content-check.mjs`
- Tests: `~/projects/personal/ailearning/tests/unit/content.test.mjs` (in `npm test`)
- History (T78, drifted, do not edit): `~/agent-work/research/2026-09-24/T78/content/{homepage.json,validate.py,tests/}`
- Design: `~/agent-work/research/2026-09-24/T76/plan.md` §3, §5.1, Owner decisions; brief `~/agent-work/briefs/T78-ailearning-home-mockups.md`
