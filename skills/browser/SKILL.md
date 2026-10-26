---
name: browser
description: Drive a web page with the Playwright MCP. Use for web scraping, web app testing; Moodle UI work loads /moodle-web. Persistent logins, headless by default, headed with PW_HEADED=1. Not for native apps or the owner's Chrome profile (`desktop` skill).
---

Triggers: real desktop, pc CLI.

# Browser automation (Playwright MCP, T12)

## Which tool
- **Playwright MCP** — any web page: navigate, snapshot, click, fill, screenshot. Default choice.
- **`pc` CLI (`desktop` skill)** — native apps, GNOME dialogs, "look at my screen", or the owner's own Chrome profile.
- Never script `google-chrome` by hand for web work.

## How it is wired
- Launcher `~/agents/bin/playwright-mcp` (sources nvm, execs the global `@playwright/mcp` 0.0.83 under node v24.20.0; exits 3 below 0.0.81, no idle timeout),
  config `~/.claude/playwright-mcp.json`. Registered user-scope; config changes affect **new** sessions only.
- Viewport 1280x720. Downloads/screenshots/traces land in `~/agents/browser/out`.
  The launcher deletes files there older than 7 days at start: copy anything you keep elsewhere
  (your ticket folder, or `drop-link`).
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
- Call `browser_close` when the task ends: an open page keeps rendering (a WebGL page burned 1-1.6 cores for 2.5 days,
  2026-09-26). `sentinel-runaway` rule 6 closes a hot browser only after 30 min without a Playwright call.
- Moodle UI work: load `/moodle-web` (env URLs, admin login, admin-page table, when to use the CLI instead).
- Playwright Firefox (library, under Xvfb) still opens on the real screen while `WAYLAND_DISPLAY` is set: run it with
  `env -u WAYLAND_DISPLAY` (T1402: 3 windows of ~2 s on the owner's screen; quirks.md).

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
