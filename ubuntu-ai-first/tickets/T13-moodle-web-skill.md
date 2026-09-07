# T13 — `/moodle-web`: drive any local Moodle site through the browser

**Phase 2 · must · Model: opus · Estimated agent time: 60 min**

## Goal
An agent can log in to any local Moodle env, reach the usual admin pages (plugin install/upgrade, purge caches, notifications, plugin settings) and verify a plugin in the real UI in a couple of tool calls.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/` (after T05), `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Envs under `~/moodle-envs/<ver>` (5.2 today), URL pattern `http://moodle-lab.tail2ea32e.ts.net:80MM`, admin / Admin1234!, `config.php` holds wwwroot. Shared selenium :4444 (Behat) and mailhog :8025 exist.
- Playwright MCP from T12 (persistent profile). Moodle CLI alternatives already exist inside the container (`admin/cli/purge_caches.php`, `admin/cli/upgrade.php --non-interactive`); the skill should say when the CLI is better.
- Moodle 5.1+ layout: plugins under `www/public`; 4.x at `www`. Harness rules: `~/.claude/moodle-guidelines.md`.

## Steps
1. `~/agents/bin/moodle-envs`: lists envs (version, URL, containers, up/down) by scanning `~/moodle-envs/*/docker-compose.yml` and `config.php`; `--json`.
2. `~/.claude/skills/moodle-web/SKILL.md` (≤ 80 lines): usage `/moodle-web <ver> <task>`; a URL table (login, /admin/index.php, /admin/purgecaches.php, /admin/plugins.php, /admin/settings.php?section=<x>, /my, mailhog); login procedure with the Playwright MCP (navigate → snapshot → fill → click → snapshot, check "You are logged in as"); when to use the CLI instead; how to attach a screenshot path to the report.
3. Optional helper `~/agents/bin/moodle-login-check <ver>`: curl-based check that the site answers and the login page renders (no browser).
4. Machine-specific skill: do not sync to `~/moodle-harness` unless the orchestrator asks.

## Success check
```bash
moodle-envs                                # 5.2 up, URL, ports
claude -p --model sonnet "/moodle-web 5.2 log in as admin, open Site administration > Notifications, tell me if it says 'Your site is up to date' or lists pending upgrades, and give me the screenshot path." | tail -5
```

## Rollback
Delete the skill dir and the two scripts.
