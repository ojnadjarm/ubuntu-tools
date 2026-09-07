---
name: browser
description: Drive a web page with the Playwright MCP - persistent logins, headless by default, headed on the real desktop with PW_HEADED=1. Use for web scraping, web app testing and any Moodle UI work. Not for native apps or the owner's Chrome profile (use the `desktop` skill / `pc` CLI).
---

# Browser automation (Playwright MCP, T12)

## Which tool
- **Playwright MCP** — any web page: navigate, snapshot, click, fill, screenshot. Default choice.
- **`pc` CLI (`desktop` skill)** — native apps, GNOME dialogs, "look at my screen", or the owner's own Chrome profile.
- Never script `google-chrome` by hand for web work.

## How it is wired
- Launcher `~/agents/bin/playwright-mcp` (sources nvm, execs pinned `@playwright/mcp` 0.0.80),
  config `~/.claude/playwright-mcp.json`. Registered user-scope; config changes affect **new** sessions only.
- Viewport 1280x720. Downloads/screenshots/traces land in `~/agents/browser/out`.
- Profile `~/agents/browser/profile-default` is persistent: **logins survive across sessions**.

## Switches (env vars, set when starting the session)
- `PW_HEADED=1` — visible window on the physical desktop (1366x768). Default is headless.
  Verify with `pc shot` and read the PNG. The headed browser closes when the session ends; if one
  is stranded, close it with `pc win close` on the automation window — never `killall chrome`,
  it would also kill the owner's Chrome.
- `PW_PROFILE=clean` — a second, persistent profile that is currently logged out (it is reused
  across runs, so it stops being "clean" if an agent ever logs in on it); `PW_PROFILE=<name>`
  creates `~/agents/browser/profile-<name>` on first use. Names must match `[A-Za-z0-9_-]+`,
  otherwise the launcher exits 2.

## Working rules
- One browser at a time per profile: a second concurrent session on the same profile hits the Chromium profile lock.
- `browser_snapshot` before clicking; act on refs from the snapshot, not on guessed coordinates.
- Log in once per profile, then reuse it — do not re-enter credentials every run.
- Moodle 5.2 test site: `http://$HARNESS_TAILNET_FQDN:8052` (admin / Admin1234!), already logged in on `profile-default`. `moodle-envs` lists the envs and their ports.

## Claude in Chrome (T14) — the owner's real browser — NOT AVAILABLE
- **Status: pending owner sign-in to the Claude extension.** The extension is installed but is not
  signed in to claude.ai in the owner's Chrome profile, so no Claude Code session can pair with it.
  **Use Playwright (above) for all browser work until this is fixed.** Do not attempt to sign in.
- One-line check before spending a session on it:
  `claude --chrome -p "list my open Chrome tabs"` — while it is still signed out this reports
  *"the claude-in-chrome MCP reports no browser extension connection"* and opens no tab.
- Once the owner has signed the extension in: Chrome must already be running in the GNOME session
  (`pc open google-chrome`; Cancel the GNOME keyring prompt if it appears), then start the session
  with `claude --chrome` (or `/chrome` inside a session for status, reconnect and site
  permissions). Only OAuth (`/login`) sessions can use it — API keys cannot.
- Artifacts in place: extension `fcoeoabgfenejglbffodgkkbkcdhcgfn` ("Claude") in the default Chrome
  profile, native host manifest at
  `~/.config/google-chrome/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json`.
