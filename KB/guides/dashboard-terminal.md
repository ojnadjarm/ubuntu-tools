# Dashboard terminal: a real shell in the panel, tailnet https only (ttyd + caddy + tailscale serve)

Ticket: T1548 · Last verified: 2026-11-10 by `pytest tests/test_terminal.py` 8/8 (fixture ttyd + caddy), live `echo ok` over wss :8476 (101, output seen), wrong Origin 502, loopback without the header 403, `ss -ltnp` 127.0.0.1:8477 only

## When to use
The owner wants a shell from the dashboard (Library › Terminal) or the terminal page on his phone. Not for agents: they have Bash. Not a second login path for anyone else: one Tailscale login only.

## The path we took
- `dash-terminal-tty.service`: ttyd on a unix socket `%t/dash-terminal/tty.sock` (dir 0700), `-W -O -m 3 -b /tty`, `bash -l` as the user.
- `dash-terminal.service`: caddy `dashboard/terminal/Caddyfile` on 127.0.0.1:8477; passes only `Tailscale-User-Login == $TERMINAL_OWNER_LOGIN` (config.env), else 403; serves `dashboard/terminal/web/` (key bar page) at `/`, ttyd at `/tty/`.
- `tailscale serve --https=8476 http://127.0.0.1:8477`: TLS + identity header.
- Dashboard screen `static/next/js/screens/terminal.js` frames `https://<tailnet-fqdn>:8476/`. Architecture: `~/agent-work/research/2026-11-10/T1548/ARCH.md`.

## Exact commands
```bash
systemctl --user status dash-terminal.service dash-terminal-tty.service
ss -ltnp | grep 8477                  # 127.0.0.1:8477 caddy only
tailscale serve status | grep -A1 8476
# turn it off (owner or a brief that says so):
pc units disable dash-terminal.service --user --apply   # stops the shell unit too (PartOf)
tailscale serve --https=8476 off
# back on:
pc units enable dash-terminal.service --user --now --apply
tailscale serve --bg --https=8476 http://127.0.0.1:8477
# tests (fixtures, never the real units):
cd ~/agents/dashboard && python3 -m pytest -q tests/test_terminal.py
```

## Pitfalls (measured)
- `apt install ttyd` enables a system `ttyd.service` running `login` as root on lo:7681. Disabled with `pc units disable ttyd.service --system --apply` on 2026-11-10; check it after package upgrades.
- Caddy site address `http://127.0.0.1:8477` only matches Host 127.0.0.1; tailscale serve keeps the browser's Host (`<tailnet-fqdn>:8476`), so every request got an empty 200. Use `http://:8477` + `bind 127.0.0.1`.
- ttyd `-O` compares Origin with Host: through serve they agree (101); a foreign Origin fails (502 at caddy). Do not rewrite Host in caddy or the check breaks.
- ttyd `--auth-header` only checks the header exists; the exact login check is caddy's `header` matcher.
- `persist_config` is not a caddyfile global option in this caddy (start fails).
- The dashboard rem is 12 px on phones: frame height is `calc(100dvh - 300px)` ≤ 820 px so the key bar clears the dock (bottom 783 < dock 800 at 400x850).
- `.keys button:active` stuck gold after a touch in Chrome mobile emulation; pressed state is `aria-pressed` only.
- `tests/test_next.js` caps a section at 5 screens: Machine was full, so Terminal sits in Library (`#terminal`).
- Empty `TERMINAL_OWNER_LOGIN`: the front unit exits 78 and does not restart (fails closed).

## Links
- Code: `units/dash-terminal{,-tty}.service`, `dashboard/terminal/{Caddyfile,web/}`, `dashboard/static/next/js/screens/terminal.js`, `dashboard/static/css/terminal.css`
- Tests: `dashboard/tests/test_terminal.py` (unit shape, 200/403/403, websocket origin)
- Design / results: `~/agent-work/research/2026-11-10/T1548/` (ARCH.md, page.mjs, ctrl.mjs), shots `~/drop/T1548/`
