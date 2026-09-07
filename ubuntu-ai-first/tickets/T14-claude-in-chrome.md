# T14 — Claude in Chrome integration in the owner's real browser

**Phase 2 · nice · Model: opus · Estimated agent time: 45 min**

## Goal
Interactive sessions can drive the owner's own Google Chrome (their logins, extensions) through `claude --chrome`, for tasks where a real logged-in browser beats Playwright.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/` (after T05), `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Claude Code 2.1.261 has `--chrome` / `--no-chrome` (Claude in Chrome integration; needs the "Claude in Chrome" extension installed in Chrome and Chrome running in the GNOME session). Check current docs with the `claude-code-guide` agent or `claude --help` before assuming the pairing flow.
- Chrome: `google-chrome-stable`, first-run dialogs already suppressed (`~/agents/README-pc-control.md`). Chrome must be launched with the session env (`~/agents/bin/env.sh`).
- The orchestrator's tmux session may need a restart with `--chrome` to pick it up (coordinate with the orchestrator; T03 service makes restarts safe).

## Steps
1. Install the extension in the default Chrome profile (use `pc` to click through the Web Store if needed; screenshot proof).
2. Create `~/.config/systemd/user/chrome-session.service` (optional, `WantedBy=default.target`) that starts Chrome minimised at login with `--restore-last-session`, so the extension is always reachable. Enable only if the owner said yes to a permanently open Chrome; otherwise document `pc open google-chrome`.
3. Verify with `claude --chrome -p "list my open Chrome tabs"` (or the equivalent tool in an interactive session).
4. Note in `~/.claude/skills/browser/SKILL.md`: Playwright = default and headless-safe; Chrome integration = only when the owner's logins are needed.

## Success check
```bash
claude --chrome -p "Using the Chrome integration, open https://example.com in a new tab and report the tab title." | tail -3
pc shot /tmp/t14.png     # Read: Chrome shows example.com
```

## Rollback
Remove the extension, disable `chrome-session.service`, drop the skill note.
