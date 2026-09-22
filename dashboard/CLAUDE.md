# Dashboard — agents panel (port 19998, https front 8498)

Unit `agents-dashboard.service` (stdlib `http.server`, no framework, no bundler). Restart after
server changes: `systemctl --user restart agents-dashboard`, then read back that 19998 answers.

## Layout

```
server.py            unit entry + facade: `import server` / `server.X = v` reach the dash/ modules (tests use it)
dash/env.py          machine constants, run() for CLIs
dash/http.py         Handler: route lookup, one-write send() (TCP_NODELAY, gzip ≥ 1 KB, ETag/304), pages, /static
dash/routes.py       @route(method, path, prefix=False) registry
dash/cache.py        cached() TTL memo; swr() stale-while-revalidate, blocks refreshed in parallel
dash/services/       system, sites, files, thumbs, notes, search, voice, state — each registers its own routes
index.html           shell only; loads static/js/app.js (module)
static/eye.css       the one design system: tokens, chrome, @component blocks, responsive
static/css/          voice.css (voice + pronunciation), machine.css
static/js/core/      fmt, api, router, poll
static/js/app.js     boot + lazy import() of the active screen
static/js/screens/   sites, services, files, docs, notes, machine, style — each exports render(grid, data)
static/js/ui/        lightbox, head, copy, spark
static/js/voice/     recorder, common, voice, pronunciation (page entries)
tools/perf.py        endpoint timings (5× keep-alive + 5× fresh, raw/gzip bytes); --cold waits 31 s
tests/               pytest (conftest fixes NOTES_VAULT_DIR to fixtures) + node test_pronunciation_page.js
```

## Rules

- New endpoints: `@route` in the owning `dash/services/*.py`. Never an if-chain in http.py.
- No inline `<style>` or `<script>` in any page. CSS in eye.css or `static/css/`, JS as ES modules in `static/js/`.
- Colours, fonts, radii: eye.css tokens only (`var(--…)`), no hex literals in page CSS.
- Slow reads go behind `cached()` / `swr()`; no idle timers (idle cost stays ~0 CPU).
- Tests use fixtures only: temp corpus / fixture vault. Never record into or delete from `~/agents/asr-corpus`.
- Before done: `python3 -m pytest tests -q`, `node tests/test_pronunciation_page.js`, `python3 tools/perf.py`,
  and a check of the touched screens at 1366 and 400 px.

## History

- T30 (2026-09-22): pronunciation path, drill prompts, Kokoro references and floor.
- T32 (2026-09-22): speed + structure refactor, T1–T15 and T33 (Clear attempts, `POST /api/voice/clear`).
  Plan `~/agents/research/2026-09-22/T32-dashboard-plan.md`, results `T32-results.md` next to it.
- T35/T36 (2026-09-22): /pronunciation is one centred fluid column (`--col: min(max(62vw, 900px), 1180px)`, container `.col`): path bar with Back/Resume above the step card, collapsed take/score/trail `<details>` drawers, footer holds only Continue; sentence and Listen buttons scale with `cqi`, Listen grid stays even by button count (`:has`). Spec `research/2026-09-22/T35/spec.md`, shots `T36-shots/`.
- T37 (2026-09-22): responsive pass on every page, audit `research/2026-09-22/T37-audit.md`, shots `T37-shots/{before,after}/` (`shoot.js`). Panel: stepped chrome zoom `--z` (1.1 ≥ 1800 px, 1.3 ≥ 2300 px) and `--wrap` 1880 px, 8-column phone tab bar, `.cell.roomy`, docs card grid; /voice is one `--col` column like /pronunciation; /plans pages use fluid `--pfs` type and width.
- T39 (2026-09-22): Docs cards on a 6-column grid with per-card `--s2`/`--s3` spans (every row full, newest take the wider rows) and `.cell.fill` (≥ 821 px the cell fills the board, cards show a whole-line `##` outline from `plan_excerpt`); Services fleet/yours/desktop are one table with `tr.grp` rows; phone name link keeps 44 px via negative margin; phone facets one scrolling row. Shots `research/2026-09-22/T39-shots/` (`shoot.js`, `docs-fixture.js`).
- T40 (2026-09-22): delete on Files rows and Docs cards (native `confirm()` naming the item, 44 px phone targets); `POST /api/files/delete` {path} and `/api/docs/delete` {slug} move to the freedesktop trash via `gio trash` (hard links: only the link goes), doc index entry removed via temp file + rename, `cache.forget()` drops the `drop`/`plans` blocks; 400 for anything unconfined, hidden, missing or not in the index. Docs card is now `div.doc` (spans) wrapping the `a` plus the button. Tests `tests/test_delete.py` (fixture HOME/XDG_DATA_HOME, so gio never touches the real trash); flow + shots `research/2026-09-22/T40-shots/` (`fixture-server.py`, `flow.js`).
- T41 (2026-09-22): `ui/confirm.js` `ask({title,item,body,action})` → Promise<boolean>, `.cfm` in eye.css (centred card, bottom sheet ≤ 820 px, 44 px targets, alertdialog, focus trap, Esc/backdrop cancel, focus back to the trigger) replaces native `confirm()` on Files and Docs and the inline Clear confirm on /pronunciation (`clearAsk()`); flow + shots `research/2026-09-22/T41-shots/` (`fixture-server.py`, `flow.js`).
- T46 (2026-09-22): `HARNESS_BRAND` (config.env, exported by `bin/env.sh`) → `dash.env.BRAND`, `/api/status` `brand`; header `#host` and `document.title` show it (empty = old uppercased host); `asset(..., brand=True)` appends ` · BRAND` to `<title>` of `index.html` and every `static/*.html` (ETag carries a brand hash); ≤ 1500 px the brand wraps (`contain: inline-size`, the sub line sets the width), phones one line with `clamp()` font + ellipsis. Shots `research/2026-09-22/T46-shots/` (`shoot.js`).
