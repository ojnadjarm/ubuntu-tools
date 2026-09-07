# T12 — Playwright MCP: persistent profiles, config, headed/headless switch

**Phase 2 · must · Model: opus · Estimated agent time: 60 min**

## Goal
Browser sessions keep their logins between runs, screenshots land in a known folder, and an agent can choose headless (fast) or headed (visible on the desktop) with one flag.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/` (after T05), `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Registered MCP (user scope, `~/.claude.json`): `playwright` = `npx -y @playwright/mcp@latest`, no config. Playwright chromium 1243 in `~/.cache/ms-playwright`. Node 24 via nvm (`~/.nvm`) — `npx` is only on PATH in login shells; `claude -p` under systemd (T15) needs an absolute path.
- `@playwright/mcp` supports `--config <json>`, `--user-data-dir`, `--headless`, `--output-dir`, `--viewport-size`, `--browser`, `--isolated`. Check `npx @playwright/mcp@latest --help` for the exact names of the installed version.
- Moodle 5.2: `http://moodle-lab.tail2ea32e.ts.net:8052`, admin / Admin1234!.

## Steps
1. Pin the version: `npm i -g @playwright/mcp@<current>` under nvm, and create `~/agents/bin/playwright-mcp` wrapper that sources nvm and execs the binary (so systemd runs work).
2. Config `~/.claude/playwright-mcp.json`: viewport 1280x720, output dir `~/agents/browser/out`, user-data-dir `~/agents/browser/profile-default`, headless controlled by env `PW_HEADED=1` (wrapper adds/removes `--headless`). Optional second profile `profile-clean` via `PW_PROFILE=clean`.
3. Re-register: `claude mcp remove playwright -s user`; `claude mcp add -s user playwright -- ~/agents/bin/playwright-mcp --config ~/.claude/playwright-mcp.json`. `claude mcp list` must show Connected.
4. Test persistence from a fresh `claude -p` session: log in to Moodle 5.2 with the MCP, quit, start another session, navigate to `/my` and confirm still logged in.
5. Document in `~/agents/KB/quirks.md` and add a short `~/.claude/skills/browser/SKILL.md` (≤ 40 lines): when Playwright MCP vs `pc` vs Chrome; headed switch; where outputs go; snapshot before click.

## Success check
```bash
claude mcp list | grep playwright        # Connected
ls ~/agents/browser/profile-default      # profile files present after first run
claude -p --model sonnet "Use the playwright MCP: navigate to http://moodle-lab.tail2ea32e.ts.net:8052/my and tell me the page title and whether a user is logged in. Do not log in." | tail -3   # logged-in dashboard after step 4
PW_HEADED=1 claude -p --model sonnet "Use playwright to open https://example.com and wait 5 seconds" & sleep 8; pc shot /tmp/t12.png   # Read: a Chromium window visible on the desktop
```

## Rollback
`claude mcp remove playwright -s user` and re-add the original `npx -y @playwright/mcp@latest`; delete `~/agents/browser`, the config and the skill.
