# ailearning repo: set up, build, check and preview the public learning site (Vite multi-page on GitHub Pages)

Ticket: T79 (plan T76 ticket 2), homepage T82, U01 full lesson T84 · Last verified: 2026-09-25 by `npm run ci` green (66 node tests, 11 site pages incl. the narrow sheet, 18 home views + 9 behaviours, home budget, sheet-cold, U01 sweep + callout + live + drive → end, the whole lesson played by script (`lesson.mjs`), also from the drop link)

## When to use
Any work inside `~/projects/personal/ailearning` (public repo `<github-user>/ailearning`, site `https://<github-user>.github.io/ailearning/`):
adding a page or unit, re-syncing the kits, fixing a Pages URL, the hygiene check, the local preview. Not for the plate look
(guide `cutaway-style`), the engine (guide `explainer-engine`) or homepage copy (guide `learning-site-homepage`).

## The path we took
- Started from the portfolio (`deploy.yml` unchanged, `check-links.sh`, CLAUDE.md shape) and the explainer kit's `example/`
  (the owner-approved neuron plate) as U01 at `/u/01-neuron/`; only its URLs (fonts, bundle) and ids changed.
- Kits are **vendored**, never aliased to `~/agents`: `tools/sync-kit.sh` copies cutaway `src/**` → `src/kit/cutaway/`,
  explainer `src/` + `adapters/` → `src/kit/explainer/`, fonts + OFL → `public/fonts/`, and writes sha256 per file to `src/kit/VERSION`.
- Root page = the Exploded Assembly homepage (T82): `index.html` is a shell filled at build by `src/site/homepage/plugin.mjs` from
  `content/homepage.json` (guide `learning-site-homepage`). The Sheet 0 title sheet is retired; `title.css` stays for the 404. `404.html` reuses
  `title.css` (`.field.solo`) with one link home via `href="%BASE_URL%"` (Vite substitutes it; relative links break at depth).
- U01 has a `<noscript>` card; `public/THIRD-PARTY-NOTICES.txt` (three.js MIT, GSAP copyright) ships at the site root and
  `tests/unit/notices.test.mjs` fails if a dependency or its installed version is missing from it.
- Checks: `hygiene.mjs` (scans what git would commit, `git ls-files -co --exclude-standard`, or every file outside a repo, plus `dist`;
  leak tier everywhere; wording tier `T\d{2}`/fleet/atelier/orchestrator/drop/"the owner"/ticket on everything except vendored
  `src/kit/`; raw audio .wav/.flac/.aiff/.mp3; private names from `HYGIENE_DENY`), `bundle-check.mjs` (postbuild: every cue-sheet
  clip as .opus AND .m4a; Chromium only fetches .opus, so e2e never sees a missing .m4a), `base-check.mjs` (sources: no root-absolute href/src, no literal `fetch`/`loadBundle`/`url()`;
  dist: every URL under `/ailearning/`), `tests/lib/pages-sim.mjs` (Pages 301/404 behaviour), `tests/e2e/site.mjs` (home + 404 at 5 widths, U01 without JS),
  `tests/e2e/unit.mjs` (frozen sweep of the whole watch at 0.25 s, live Begin + audio, `__rec.go('drive')`, turn both dials, end card),
  `tests/e2e/lesson.mjs` (T84: the whole lesson by script, run with `--import ./tests/lib/register.mjs` since it imports the sim's TS; ~3 min).
- Machine-only notes live in `CLAUDE.local.md` and the preview script in `.local/drop.sh`, both git-ignored; public `CLAUDE.md` is neutral.
- T82 added: `tools/content-check.mjs` (ajv 2020-12 + path/copy rules, `prebuild` and inside the plugin), `tools/link-check.mjs` (postbuild and
  `check-links.sh`: every internal href/src/`#id` in `dist` resolves, nothing outside the base), `tests/e2e/home.mjs`, `tests/e2e/home-perf.mjs`.
- `deploy.yml` runs `npm run typecheck` and `npm test` before `npm run build`.

## Exact commands
```bash
cd ~/projects/personal/ailearning
npm run ci                                            # once a day (timer), not per change: typecheck, kit:verify, node tests, build (+hygiene, base-check), e2e (tests/run-e2e.mjs, parallel lanes)
npm run test:changed [-- --dry] [path ...]           # only the checks covering the changed files (default: git status); map in tools/test-changed.mjs
HYGIENE_DENY=~/agent-work/research/2026-09-24/T79/hygiene-deny.txt npm run hygiene     # plus private names (keep the file outside the repo)
CUTAWAY_KIT=~/agents/kits/cutaway EXPLAINER_KIT=~/agents/kits/explainer npm run kit:sync   # after a kit change; then npm run test:changed
.local/drop.sh                                        # https://<tailnet-fqdn>:8472/ailearning/ (sites publish, review switch ?review; T271)
node tests/e2e/unit.mjs https://<tailnet-fqdn>:8472/ailearning/u/01-neuron/   # 0 failed requests
node ~/agents/kits/explainer/tools/e2e.mjs <u01 url> out/run.json                  # full watch → drive → end run
npm run cue-check -- --clip c4b --mark graph --key graph --part graph                # one cue: key changes on the word, part drawn
KOKORO_PY=… KOKORO_RENDER=… tools/narrate.sh 01-neuron c4c                         # render + merge only the named clips (/kokoro-narration)
```
New page: `u/<NN-slug>/index.html` (relative `../../units/...` paths) + one line in `build.rollupOptions.input` in `vite.config.ts`.

## Pitfalls (measured)
- `npm run build` fails in a copy without `.git` (a sandbox rsync): outside a git repo `hygiene` scans every file, so the ignored
  `CLAUDE.local.md` and `.local/` hit the wording tier. Build the copy with `node tools/content-check.mjs && npx vite build && npm run postbuild`
  (verified 2026-09-26: exit 0, dist hygiene 0 hits). `hygiene` itself stays as is: its selftest relies on the git-less walk.
- The example fetched `bundles/a01/` and `url(fonts/…)` page-relative: 404 under `/ailearning/u/01-neuron/`. Fixed with
  `import.meta.env.BASE_URL`; base-check flags the original `main.ts` (2 faults) and a root-absolute `href="/x"`.
- Vite rewrites `url(/fonts/x.woff2)` in CSS to `/ailearning/fonts/x.woff2`, so CSS may use root-absolute public paths; scripts may not.
- The hygiene selftest's own fixture strings must be split (`'.ts' + '.net'`), or the repo scan flags the test file.
- The vendored cutaway kit has "T71" in 2 comments: the wording tier skips `src/kit/` (kit files are hashed, never edited; fix it
  upstream in `~/agents/kits/cutaway` and re-sync). The minifier strips it from dist.
- The checker's own patterns must not match themselves: `ateli[e]r`, `orchestrat[o]r` in `hygiene.mjs`.
- Global git identity on this machine is the owner's real name: the push steps make a repo-local handle + noreply email step 1
  (critic T79, high). Never set it for him; it is his git state.
- pages-sim's built-in 404 went out as `application/octet-stream` (a download) because `extname('.html')` is `''`; fixed.
- Planted faults the ci now catches (all verified): deleted `twin.m4a`, a throw in `afterWatch()`, a throw at watch t = 60 s.
- A title set in `vw` spilled out of the sheet at 1920 (h1 wider than its column); `.name` is a size container and h1 uses `cqi`;
  `site.mjs` fails on any element outside the sheet's box.
- `drop-link` serves `.txt` as a download; web previews must be a folder with `index.html`.
- A hygiene leak pattern `/home/` fails any path containing `/home/`: name folders `homepage`, never `home`.
- The repo is ~3.3 MB untracked (audio 2.6 MB); no LFS.
- Browsers ask `/favicon.ico` at the host root (a console 404 on every page). The pages link `%BASE_URL%favicon.svg` (Vite's env
  replacement in HTML); a plain `/favicon.svg` fails base-check as root-absolute.
- The landing check in `site.mjs` was a camera-width ratio; once the landing framed Fig. 1 for the pre-Begin inset it measured the wrong
  thing. It now checks the paper spans ≥ 99.9 % of the field and the landing box is centred within 2 px (`SHEET` parsed from `layout.ts`).
- Plate JS 227.68 kB gzip (one chunk, a recorded decision in the T76 plan); `sheet-cold` still turns with 0 blank frames.

## Links
- Code: `~/projects/personal/ailearning` (`tools/`, `tests/`, `CLAUDE.md`)
- Tests: `npm test` (hygiene selftest, pages-sim), `npm run e2e`
- Design / results: `~/agent-work/research/2026-09-24/T79/{architecture.md,findings.md}`, plan `~/agent-work/research/2026-09-24/T76/plan.md` §4, §5.1
- Owner push steps: `~/drop/AILEARNING-PUSH-STEPS.txt` is gone since 2026-09-25 (a copy is in `~/.local/share/Trash/files/`)
- Critic reports: `~/agent-work/research/2026-09-24/T79/critic-{public,pages}.md`
- **Credits (T81, 2026-09-24, owner's choice):** "Drawn by Claude · Directed by Oscar Nadjar" (name → https://<github-user>.github.io/portfolio/,
  `rel="author"`) in README, title sheet and 404 title blocks; plates sign DRAWN Claude / APPROVED Oscar Nadjar; `LICENSE` and
  `LICENSE-content` name him as holder. The deny-list still blocks `oscar`/`nadjar`: its `allow <path-glob> <regex>` lines exempt only
  those exact spans (sources + `dist/`), and only from the deny-list, never the leak tier. A new credit spot = a new `allow` line;
  a new unit's title block needs its own. U01's plate code is a lazy chunk, so its title block span needs an `allow dist/assets/main-*.js` line. `tests/e2e/site.mjs` reads the expected link from the README credit line.
  Homepage spots (T82): `allow src/site/homepage/credits.mjs` (the one source) + 2 `dist/index.html` spans (APPROVED cell, colophon line);
  `tests/unit/hygiene.test.mjs` plants them both ways (allowed spot passes, the name elsewhere fails).
- **Cold first sheet change (2026-09-24):** a cross-document view transition reveals the new page at its first render and waits only for
  render-blocking CSS/fonts; a unit drawn by a 705 kB module showed an empty sheet for ~3.7 s at 1.6 Mbit/s (warm: 0). Fix: `blocking="render"` on the
  unit module (Vite drops the attribute from the entry tag, so the sheet plugin adds it in a `post` pass) + preload `cues.json` and the plate font.
  Over ~4 s Chrome skips the turn instead (one ~175 ms empty frame while WebGL starts). Measure with `node tests/e2e/sheet-cold.mjs [url]`.
- **Desktop-only unit pages (T84, 2026-09-24):** below 1024 px `units/<slug>/entry.ts` marks `html.is-narrow` and the page shows the
  narrow sheet the plugin renders (`<!--sheet:narrow-->`, `src/site/sheet/narrow.mjs`); the plate chunk is never fetched (site e2e checks the
  requests) and widening the window imports it. A lazy `import()` is not render-blocking (the turn revealed Sheet I with 22 of 55 blank frames),
  so the plugin's head gate fetches the plate chunk and its CSS with `blocking="render"` from 1024 px (0 blank frames, card at 2.0 s).
  Vite's `__vite__mapDeps` line lists base-relative files; `base-check` skips that line. Don't name the html class like a component
  (`.narrow{display:none}` hid `html.narrow`: blank page).
- **Leader/label geometry:** `tests/e2e/home.mjs` clips each leader segment against every label box and checks label overlap (inner 60 %
  across the line, so stacked caption lines pass), per layout, state and all-seated. It also caught OUTPUT touching MATCH LINE A on phones.
