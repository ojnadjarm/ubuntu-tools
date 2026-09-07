# T27 — HTTPS names for Moodle environments via `tailscale serve`

**Phase 5 · nice · Model: opus · Estimated agent time: 60 min**

## Goal
Each Moodle env is reachable at a proper HTTPS URL on the tailnet (e.g. `https://moodle-lab.tail2ea32e.ts.net/` → 5.2, or per-port TLS), so the mobile app, cookies and service workers behave like production.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Tailscale 1.102, `No serve config`. HTTPS certs need "MagicDNS + HTTPS" enabled in the tailnet admin (owner click if not enabled: `tailscale cert` will say so).
- Moodle `wwwroot` is in `~/moodle-envs/<ver>/www/config.php` (installed via `/moodle-install --host`); changing scheme/host requires updating `wwwroot` and running `admin/cli/purge_caches.php`. Keep the plain HTTP port working too (Behat/selenium use it).
- Multiple envs: `tailscale serve --https=8452 http://127.0.0.1:8052` style (one TLS port per env, 84MM convention) avoids path rewriting.

## Steps
1. Check `tailscale cert moodle-lab.tail2ea32e.ts.net` works; if not, stop and report the admin-console step for the owner.
2. `tailscale serve --bg --https=8452 http://127.0.0.1:8052`; verify `curl -I https://moodle-lab.tail2ea32e.ts.net:8452`.
3. Update `wwwroot` to the HTTPS URL for 5.2, purge caches, log in via `/moodle-web` and confirm no mixed-content or redirect loop; ensure `$CFG->sslproxy = true` since Apache still speaks HTTP behind serve.
4. Patch `~/.claude/skills/moodle-install/install.sh` with an optional `--https` flag that adds the serve mapping and sets `sslproxy`; `sync.sh`, tell the owner to commit. Update `moodle-envs` lister to show both URLs.

## Success check
```bash
tailscale serve status                                        # 8452 -> 127.0.0.1:8052
curl -sI https://moodle-lab.tail2ea32e.ts.net:8452/login/index.php | head -1   # HTTP/2 200
grep -E "wwwroot|sslproxy" ~/moodle-envs/5.2/www/config.php
claude -p --model sonnet "/moodle-web 5.2 log in as admin over the HTTPS URL and confirm the dashboard loads without warnings" | tail -3
```

## Rollback
`tailscale serve reset`; restore `wwwroot` to the HTTP URL, purge caches; revert `install.sh` from `~/moodle-harness`.
