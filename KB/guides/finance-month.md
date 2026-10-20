# Monthly finances: bank export (.xlsx) → categorised ledger → private spending page (T147)

Ticket: T147, page redesign T149, page actions T150 · Last verified: 2026-10-20 by T846 audit (`finance-month --help`, paths, units active, 11 + 7 tests defined); 2026-10-01 by `tests/test_finance.py` (4/4) and `tests/test_web.py` (7/7) on synthetic fixtures and the September 2026 run
(76 rows, 0 running-balance gaps, net matches closing − opening balance).

## When to use
He sends his monthly bank export ("Movimientos", .xlsx) for spending analysis and tracking. Skill `/finance-month`.
Not for invoices (`/invoice`), budgets, forecasts or bank sync (not built; ask first).

## The path we took
- Survey: Firefly III (PHP + DB + separate data importer: heavy for one user), Actual Budget (one Node container, good
  UI, but its own rules/import UI, no xlsx, phone layout not ours to verify), Beancount + Fava and hledger (light,
  plain-text, but still need a custom importer for this export and their web UIs fail the responsive rule).
  Chosen: stdlib Python + PyYAML CLI, JSON ledger, static page, the `invoice` CLI's shape (T134). No service, no DB.
- Modules and data flow: `~/.claude/skills/finance-month/ARCHITECTURE.md`.
- Serving: tailscaled serves the folder itself, no extra process: `sudo tailscale serve --bg --https=8474
  --set-path=/<token> ~/finance/site` (token in `~/finance/.token`, 600). Tailnet-only, `/` and wrong tokens 404,
  `../` traversal 404 (tested with `curl --path-as-is`). Chosen over `eye link` of a file because `eye link` takes only
  http(s) URLs and he opens it on the phone.

- Page redesign (T149) survey: Copilot leads with one month number and a category list you tap into; Monarch pairs
  in/out/net with a category breakdown and cash-flow bars; YNAB/Actual/Firefly reports are denser tables. Chosen:
  Copilot-style single headline + Monarch-style tappable categories, built from the T147 page (no chart lib: inline
  SVG from Python is lighter than any bundled lib and makes no requests). Modules: `fmt`, `charts`, `blocks`, `render`.

- Page actions (T150) survey: Actual Budget imports from a file picker then runs its rules and shows an import
  preview; Firefly III needs its separate Data Importer app; both add expenses through a full form. Chosen: a stdlib
  `http.server` service (no Flask/FastAPI: zero deps, ~0 idle cost) behind the existing `tailscale serve` port, calling
  the CLI's own `finlib/ops.py`; quick-add as a one-screen sheet; categorisation by a headless Claude turn through
  `agent-exec` with `AGENT_WRAP=claude-bare` (no tools, `--no-session-persistence`).
- Serving changed (T150): `tailscale serve --https=8474 http://127.0.0.1:8475` (whole port to `finance-web`); the
  service checks the token in the path, so `/` and wrong tokens still 404.

## Exact commands
```bash
finance-month <export.xlsx>            # import + dedup + balance check + rebuild + headline
finance-month label "<Merchant>" <cat> # rule appended to ~/finance/rules.yaml, history relabelled
finance-month cash <date> <amount> <category> "<note>" [--approx] | cash list | cash rm <id>
finance-month oneoff <date> <amount> "<category>"   # out of regular totals, comparison and recurring
finance-month link                     # private link; never paste the token into a command
python3 ~/.claude/skills/finance-month/tests/test_finance.py
sudo tailscale serve --https=8474 off  # undo the serving
systemctl --user restart finance-web     # after editing finlib (the service imports it once)
python3 ~/.claude/skills/finance-month/tests/test_web.py
```

## Pitfalls (measured)
- The export has no extension: copy it, `file` says "Microsoft Excel 2007+". Strings are shared strings; amounts are
  text ("-1.999,00€"), dates dd/mm/yyyy, newest row first. Parsed with zipfile + ElementTree (no openpyxl here).
- Header "Saldo" is the balance at download time, not after the last listed row: September differed by -157,39 €
  (movements after 30/09 or card holds). The CLI reports it; the running-balance chain inside the file had 0 gaps.
- Identical twin movements exist (two 39,99 € on 01/09): the dedup key includes the balance, so both are kept.
- Concepts carry the full card number on "COMPRA … TARJETA" rows: masked to ****last4 at import, before the ledger.
- Playwright MCP writes a page snapshot (.yml) of every page it opens into `~/agents/browser/out/`: delete them after
  screenshots, and serve on 127.0.0.1 for screenshots so the token never enters the tool log.
- CSS `columns: 3 min(100%, 420px)` is ignored by Chrome (one column); `columns: 420px 3` works (masonry, no dead gaps).

- Approx-dated cash (dated the 30th) sits inside a trip that starts the 28th: approx entries are kept out of trips and
  the daily chart. Fixed costs paid during a trip (TGSS, accountant) are kept out with `not_trip_categories`.
- The bank's header balance includes movements after the last listed row: the page shows it as a warning, no guess.

- A card class must not reuse a hero class: `.big` (hero number) on the "biggest" card blew every row up to 6rem,
  `.trip` (card) also styled the `trip` badge. Card classes are now `biggest`, `card.trip`.
- `pkill -f "http.server <port>"` inside the same bash command kills that shell (the pattern is in its own argv);
  use `timeout 200 python3 -m http.server` so the server ends by itself.
- Screenshots: node Playwright from `~/.npm/_npx/*/node_modules/playwright` with `~/.nvm/versions/node/v24*/bin/node`
  (node is not on a non-login PATH), headless, `--mute-audio`, bound to 127.0.0.1.

- CSS `columns` masonry left ~270 px dead under the shortest column (T149). Fix without JS: `layout.py` estimates
  each card's height from its HTML and brute-forces the 3-column split (3^9 options) in reading order; ≥ 1100 px
  the columns are flex stacks whose last card grows, so column ends match to 0 px; below, `.col {display: contents}`
  and `order` keep the phone reading order. The estimate's remaining error (fixture 39–69 px, real 139–179 px)
  sits inside the last card of a column.

- T150: removing a `--set-path` mount needs the exact mount with its trailing slash (`/<token>/`); without it `off`
  exits 1 and the old static mount keeps winning over a new `/` proxy (longest prefix).
- T150: a 413 sent before the client finishes a large body shows up as "broken pipe" in urllib; test the cap with
  headers only (`http.client` putrequest + Content-Length), the page JS refuses > 5 MB before sending.
- T150: `agent-exec`'s adapter forces `--tools ${AGENT_TOOLS:-…}` (an empty value falls back to the default set); the
  `claude-bare` wrap rewrites it to `--tools ""` and adds `--no-session-persistence`, so no transcript is saved.
- T150: real pages need a `finance-month build` after a template change before the page buttons exist.

- T151: `finance-web` runs in bwrap via `finance-web.socket` + `scripts/finance-web-sandbox` (net unshared, only the Claude API through `code-review-netproxy`; `finance-web-sandbox -- <cmd>` runs a probe inside). Undo: `cd ~/.config/systemd/user && systemctl --user disable --now finance-web.socket && mv finance-web.service.pre-bwrap finance-web.service && systemctl --user daemon-reload && systemctl --user restart finance-web`.
- F54 (2026-10-03): `finance-web`'s threading lock did not cover the CLI; two writers kept 71 of 80 rows. Every
  `ops` mutation (and `finance-month build`) now holds `flock` on `~/finance/.lock`; tmp names are unique and
  `rules.add` rewrites `rules.yaml` atomically. Test: `test_concurrent_writers_keep_every_row`.

## Links
- Code: `~/.claude/skills/finance-month/`, CLI symlink `~/agents/bin/finance-month`
- Tests: `~/.claude/skills/finance-month/tests/{test_finance,test_web}.py`
- Data (private, 700): `~/finance/` (inbox, ledger.json, rules.yaml, site, shots)
