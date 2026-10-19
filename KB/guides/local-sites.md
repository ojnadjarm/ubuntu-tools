# Serve a Vite site locally like GitHub Pages (ailearning, portfolio) at a stable https link

Ticket: T85 · Last verified: 2026-10-19 (T425) by `sites.test.sh` (stale build.json fails verify, fresh passes) and a live publish

## When to use
- **ailearning: the only test site (T271, owner 2026-10-07).** `.local/drop.sh` = `sites publish ailearning` (build env `REVIEW=toggle` from `BUILD_ENV`
  in `bin/sites`); review mode is on by default (every built sheet linked, T309 2026-10-09), `?review=0` the Pages view, `?review` back on. Never a `~/drop/tNNN/` build; `ailearning-index` is retired.
- He wants to open ailearning or the portfolio "as it will be on GitHub Pages": `sites publish <site>`, send `https://<tailnet-fqdn>:8472/<site>/`.
- A new Pages project under `<github-user>.github.io`: add one line to the `REPO` table in `~/agents/bin/sites` (Vite `base: '/<name>/'`).
  For the dashboard Sites screen, add one `(path, name, what)` tuple to `PAGES[8072]` in `~/agents/dashboard/dash/services/sites.py` (T86).
- Not for a one-off file or throwaway build: use `/drop-link` (`~/drop`, :8470).

## The path we took
- Started from `drop.service` (caddy 2.6.2 in bwrap) and the repo's `tests/lib/pages-sim.mjs`; architecture `~/agent-work/research/2026-09-24/T85/ARCHITECTURE.md`.
- `sites.service`: caddy in bwrap, only `~/sites` + the Caddyfile bound read-only, :8072 on LAN IP, tailnet IP, ::1; `tailscale serve --https=8472`.
- `~/.config/sites/Caddyfile` = the Pages rules: dir without slash → 301 (a `redir` with a `file {path}/` matcher, runs before file_server's own 308),
  misses → 404 with `/<first segment>/404.html` else `/404.html` (`handle_errors` + `try_files`), `encode zstd gzip`, `Cache-Control` no-cache for HTML (`*/`, `*.html`) and `build.json`, `public, max-age=31536000, immutable` for `*/assets/*` (Vite-hashed), max-age=600 for the rest (T403),
  explicit `Content-Type` for .opus .m4a .avif .wasm .woff2 (no `/etc/mime.types` inside the sandbox).
- `sites publish`: `npm run build` in the repo → `cp -a dist` to `~/.local/state/sites/stage/<site>` → `mv --exchange -T` with `~/sites/<site>` (renameat2,
  one syscall) → delete the old copy → meta + regenerate `~/sites/index.html`. `flock` per site. `.local/drop.sh` in ailearning is `sites publish ailearning` (T271).

## Exact commands
```bash
sites publish ailearning            # build + swap (0.9 s measured); --no-build snapshots the current dist/
sites verify ailearning             # served /ailearning/build.json == dist/build.json (publish runs it, exit 1 on drift; T403)
sites status                        # service state, link, build time, commit per site
sites check                         # Pages-behaviour check against https :8472 (exit 1 on any failure)
bash ~/agents/bin/tests/sites.test.sh   # fixture: temp root, loopback caddy on the real Caddyfile
systemctl --user status sites.service; tailscale serve status   # want :8472 → http://<tailnet-ip>:8072
```

## Pitfalls (measured)
- caddy 2.6.2 has no `canonical_uris` subdirective (`caddy validate` fails); the explicit `redir @dir … 301` handles it, since redir orders before file_server.
- A plain `mv` cannot replace a non-empty directory; `mv --exchange` (coreutils 9.7) can. 20 swaps under a poll: 3438 requests, 0 non-200.
- Stage must be on the same filesystem as `~/sites` (rename); keep it outside `~/sites` so it is never served.
- Bind the `~/sites` directory, never replace `~/sites` itself: the bwrap bind would keep pointing at the old inode.
- LAN: no ufw rule for 8072 (agents may not edit ufw, FLEET §5.3); tailnet works. Owner command in `KB/machine.md`.
- `sites publish ailearning --no-build` snapshots whatever `dist/` holds: a plain `npm run build` there has no review switch. Rebuild through `sites`.
- `tools/link-check.mjs` read `/u/x/?review=1` as a missing page until T271 stripped the query; `base-check` refuses a bare `?review=1` (use the page's own path).
- A stray `python3 -m http.server 8071` (portfolio preview, 2026-09-21) still runs with a LAN ufw rule; this replaces it, owner's call to stop it.

- Build stamp (T403): ailearning's `src/site/stamp.mjs` writes `dist/build.json` {commit, built to the second} and a `build <hash> · <time>` line in the
  homepage colophon; same-minute builds differ by seconds. Portfolio (T425): `scripts/stamp.mjs` emits only `build.json` (no page change,
  dist otherwise byte-identical); `sites.test.sh` covers both sites with fixture repos. The :8472 front listens on the tailnet IP only: `curl https://127.0.0.1:8472` refuses.

## Links
- Code: `~/agents/bin/sites`, `~/.config/sites/Caddyfile`, `~/.config/systemd/user/sites.service`
- Tests: `~/agents/bin/tests/sites.test.sh`; live: `sites check`
- Design / results: `~/agent-work/research/2026-09-24/T85/ARCHITECTURE.md` · brief `~/agent-work/briefs/T85-local-sites.md`
