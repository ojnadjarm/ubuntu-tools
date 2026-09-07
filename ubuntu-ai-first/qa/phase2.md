# Phase 2 QA report — 2026-09-05

Independent verification of T12–T14 (browser automation) by the QA agent. Every command was
re-run by QA; tests went beyond the tickets' Success checks (minimal-environment launch,
concurrent profile lock, fresh-profile creation, down-env code paths, plugin count cross-checked
against `core_plugin_manager`). Screen 1366x768, lid closed, on AC, desktop unlocked, QA the only
agent on the desktop.

## Verdict

| Ticket | Success check | Goal met | Verdict |
|---|---|---|---|
| T12 playwright-mcp-hardening | PASS (4/4 steps) | PASS | **PASS with defects** (D3, D4, D5) |
| T13 moodle-web-skill | PASS | PASS | **PASS** (D6 minor) |
| T14 claude-in-chrome | **FAIL** (extension signed out) | not met | **FAIL** (D1 — HIGH) |

## Evidence

### T12 — PASS with defects

- `claude mcp list` → `playwright: /home/oscar-nadjar/agents/bin/playwright-mcp --config
  /home/oscar-nadjar/.claude/playwright-mcp.json - ✔ Connected`. Registration in `~/.claude.json`
  is user-scope stdio with exactly those args.
- **Persistence.** Fresh `claude -p --model sonnet` → `/my` on the 5.2 site:
  `Page title: "Dashboard | moodle52". Logged in as Admin User … a persisted session, no login was
  performed.` (12 s). Verified again later in the run (still logged in after 6 further sessions,
  a headed run and a profile-lock collision).
- **Clean profile.** `PW_PROFILE=clean claude -p …/my` → `Redirected to the login page — page
  title: "Log in to the site | moodle52". No user is logged in.` Correct isolation.
- **New profile on demand.** `PW_PROFILE=qatest claude -p …` → worked, created
  `~/agents/browser/profile-qatest` (2.3 MB). Removed by QA afterwards.
- **Headed.** `PW_HEADED=1 claude -p "navigate to example.com, wait 25 s"` → `pc shot` during the
  run shows a **single-tab** Chrome window on the physical desktop rendering example.com (read the
  PNG; the "unsupported command-line flag: --disable-blink-features=AutomationControlled" info bar
  is Chromium's normal automation banner). The `Sessions` deletion in the wrapper works: no tab
  pile-up. The window **closed cleanly** when the session ended — `ps` showed zero `chrome`/
  `chromium` processes 3 s later.
- **Minimal environment (systemd-shaped).**
  `env -i HOME=$HOME PATH=/usr/bin:/bin ~/agents/bin/playwright-mcp --config … --help` → exit 0,
  full usage. Stronger test: `env -i HOME=$HOME PATH=/usr/bin:/bin:$HOME/.local/bin claude -p …`
  drove a real headless browser to `/my` and reported `Dashboard | moodle52` — nvm sourcing and
  the persistent profile both survive an empty environment. T15 timers can call it.
- **Concurrency.** Session A (navigate + 20 s wait on `profile-default`) running, session B started
  12 s later on the same profile → B fails fast with:
  `Error: Browser is already in use for /home/oscar-nadjar/agents/browser/profile-default, use
  --isolated to run multiple instances of the same browser`. A completed normally. The message is
  understandable and names both the profile and the fix; the skill documents the limit. No profile
  corruption, no orphan process.
- `bash -n` clean on `playwright-mcp`, `moodle-envs`, `moodle-login-check`.
- Docs: `~/.claude/skills/browser/SKILL.md` (39 lines) and the Playwright section of
  `~/agents/KB/quirks.md` match observed behaviour, including the non-obvious
  `--restore-last-session` cookie finding.

### T13 — PASS

- `moodle-envs` → `5.2  5.2.2+  up  http://moodle-lab.tail2ea32e.ts.net:8052  moodle52-app-1
  running,moodle52-db-1 running`. Cross-checked: `docker ps` shows both containers running and
  `0.0.0.0:8052->80/tcp`; `config.php` has `$CFG->wwwroot = 'http://moodle-lab.tail2ea32e.ts.net:8052'`.
  `--json` emits valid JSON with the same values (`state":"up"`, `containers_up":"2/2"`).
  `--bogus` → usage error, exit 2. `shared` correctly excluded.
- `moodle-login-check 5.2` → `http: 200`, `login: OK (form rendered)`, **exit 0**.
  `moodle-login-check 9.9` → `no env 9.9 (missing …/9.9/www/config.php)`, **exit 1**.
  No argument → usage, exit 2.
- **Stopped/unreachable env** (tested with a throwaway `~/moodle-envs/qa-tmp` pointing at an unused
  port, removed afterwards — the running 5.2 env was never touched): `moodle-envs` lists it as
  `down` with `0/0` containers and still shows its URL; `moodle-login-check qa-tmp` → `http: 000`,
  `login: FAIL`, exit 1 (curl's own connect error is shown). The skill's step 1/2 then tells the
  agent to `docker compose up -d` and to stop if the probe fails — sensible, no browser is opened
  against a dead site.
- **Skill end-to-end, fresh session:** `claude -p "/moodle-web 5.2 open Site administration >
  Plugins > Plugins overview and report the count of plugins shown, plus the screenshot path."` →
  `**410 plugins** ("All plugins 410", 0 additional)` + `~/agents/browser/out/page-2026-09-05T18-23-27-505Z.png`.
  - Count **verified independently**: `core_plugin_manager::instance()->get_plugins()` inside
    `moodle52-app-1` returns **410**.
  - Screenshot **verified by reading it**: real rendered Moodle 5.2 admin page, Plugins tab, "All
    plugins 410 / Additional plugins 0", `AU` user menu and "Edit mode" toggle present → genuinely
    logged in as admin, not a login page.
- **No hardcoded hostname** anywhere in `moodle-web/SKILL.md`, `moodle-envs` or
  `moodle-login-check`; the URL always comes from `config.php`. (The `browser` skill mentions the
  5.2 URL once as a machine fact — appropriate for a machine-local skill.)
- Correctly **not** synced to `~/moodle-harness`: `ls ~/moodle-harness/skills` has no `browser`,
  `moodle-web` or `desktop`.

### T14 — FAIL

- Artifacts are all in place: extension `fcoeoabgfenejglbffodgkkbkcdhcgfn` v1.0.91 ("Claude", "Claude
  in Chrome") installed **from the Web Store** in the default Chrome profile, `state` enabled, no
  disable reasons, site access "On all sites"; native host manifest
  `~/.config/google-chrome/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json`
  → `path: ~/.claude/chrome/chrome-native-host` (present, executable, 159 bytes), origin restricted
  to that extension id.
- `pc open google-chrome` started Chrome; the GNOME "Choose password for new keyring" dialog
  appeared and was dismissed with `pc click-text "Cancel"` (as the skill documents).
- The native host **does** launch: `/tmp/claude-mcp-browser-bridge-oscar-nadjar/121988.sock` exists,
  owned 0600, with `claude --chrome-native-host` running.
- **But the ticket's Success check fails, twice, reproducibly:**
  `claude --chrome -p "Using the Chrome integration, open https://example.com in a new tab and
  report the tab title."` → the session reports *"the claude-in-chrome MCP reports no browser
  extension connection"*; no tab is opened (verified by screenshot). Same with
  `claude --chrome -p "list my open Chrome tabs"`.
- **Root cause found visually:** opening the extension's side panel (Extensions menu → Claude) shows
  **"Iniciar sesión — Claude en Chrome está disponible para todos los suscriptores de planes pagos"**
  with a Sign in button. The extension is **not signed in to claude.ai** in the owner's Chrome
  profile, so it never pairs with a Claude Code session. QA did **not** click Sign in (owner's
  account; see owner-review items).
- Consequence: the T14 Goal ("interactive sessions can drive the owner's own Chrome") is **not met**
  today. Playwright (T12) covers every browser need meanwhile, so Phase 2 is not blocked — T14 is
  the "nice" ticket of the phase.

### Cross-cutting

- **Leftover processes:** none. After every test (headed run, concurrency collision, Chrome close via
  `pc win close google-chrome`) `ps -eo pid,comm | grep -Ei 'chrome|chromium|playwright'` is empty
  and `pc win list` shows no windows. Desktop left clean, Chrome closed.
- **`bash -n`** clean on the three new scripts. No Python added by this phase.
- **`~/moodle-harness` git status:** only the pre-existing Phase 0/1 modifications
  (`settings.example.json`, `skills/moodle-install/{SKILL.md,docker-compose.shared.yml,install.sh}`,
  `sync.sh`). **Nothing from T12–T14 leaked into the harness repo**; nothing committed or pushed by QA.
- **Skill consistency:** `browser`, `desktop` and `moodle-web` agree on the split — Playwright MCP is
  the default for web work, `pc` is for the real screen and native apps, the Chrome integration only
  when the owner's own logins are needed. `moodle-web` defers to `browser` for the browser mechanics
  and to the Moodle CLI for non-visual work. No contradictions found.
- **Temp files:** `/tmp` holds 15 leftovers from the T14 implementation session (`t14.png`,
  `t14-a…n.png`, `chrome-t14.log`, `chrome-t14b.log`, ~1.5 MB). QA removed its own text/PNG scratch
  files; the T14 ones were left for the owning agent (D7). `$HOME` is clean — no new stray files
  (`~/Pictures/Screenshot.png` predates this phase, 17:52).

## Defects

**D1 — HIGH — T14 — Chrome integration does not work: extension is signed out.**
Repro: `pc open google-chrome`, cancel the keyring dialog, then
`claude --chrome -p "Using the Chrome integration, open https://example.com in a new tab and report
the tab title."` → "no browser extension connection", no tab opened. Extensions menu → Claude shows
the **Iniciar sesión** panel.
Cause: the extension was installed and permitted, but never signed in to claude.ai inside Chrome
(and the panel states Claude in Chrome requires a **paid plan** account sign-in).
Fix: the owner (or an interactive session with the owner watching) clicks **Sign in** in the
extension side panel and completes the claude.ai login in Chrome; then re-run the Success check.
Until then the `browser` skill should say the Chrome integration is **not available**, so agents do
not waste a session on it. Owning ticket: T14.

**D2 — MEDIUM — T14 — the ticket was reported done without its Success check actually passing.**
The Success check (`claude --chrome -p …` + `pc shot`) fails today and there is no evidence it ever
passed end-to-end: `/tmp/chrome-t14b.log` only shows the native host answering `ping`/`get_status`,
which happens even when the extension is signed out. Suggested fix: re-run the check after D1 and
record the screenshot path in the ticket report; more generally, a "success check output pasted"
rule the orchestrator can grep for. Owning ticket: T14.

**D3 — MEDIUM — T12 — `~/agents/browser/out` grows unbounded, nothing prunes it.**
Repro: `ls ~/agents/browser/out | wc -l` → 70 before this QA run, **88** after (~9 browser
sessions): 43 `console-*.log`, 43 `page-*.yml`, 2 `page-*.png`, 832 KB. Every session writes a
console log and a page dump whether or not the agent asked for output. No timer, cron,
`tmpfiles.d` rule or wrapper code deletes anything (checked `systemctl --user list-timers`,
`crontab -l`, the wrapper).
Fix: add one line to `~/agents/bin/playwright-mcp` —
`find "$HOME/agents/browser/out" -type f -mtime +7 -delete 2>/dev/null` — or a
`~/.config/systemd/user/tmpfiles`/T18 keeper rule. Owning ticket: T12 (or fold into T18).

**D4 — LOW — T12 — `killall chrome` advice in the `browser` skill also kills the owner's Chrome.**
Headed Playwright runs launch `/opt/google/chrome/chrome` (the same binary as the owner's browser —
verified in `ps` during the headed test), so the skill's "close it afterwards with `killall chrome`"
would take down the owner's session too if Chrome is open (which T14 requires). In practice the
headed browser also exits on its own when the session ends (verified), so the line is both risky and
unnecessary.
Fix: replace with "the headed browser closes when the session ends; if one is stranded, close it with
`pc win close` on the automation window, never `killall chrome` while the owner's Chrome is open."
Owning ticket: T12.

**D5 — LOW — T12 — `PW_PROFILE` is interpolated into an `rm -rf` path without validation.**
`~/agents/bin/playwright-mcp` does `profile="$HOME/agents/browser/profile-${PW_PROFILE:-default}"`
then `rm -rf "$profile/Default/Sessions"`. A value containing `/../` (e.g.
`PW_PROFILE=x/../../../.config/google-chrome`) makes that delete a `Default/Sessions` directory
outside `~/agents/browser`. Only agents set this variable, so the risk is a mistake, not an attack.
Fix: `case "$PW_PROFILE" in *[!A-Za-z0-9_-]*) echo "bad PW_PROFILE" >&2; exit 2;; esac`.
Owning ticket: T12.

**D6 — LOW — T12 docs — `profile-clean` is described as "throwaway" but it persists.**
`PW_PROFILE=clean` reuses `~/agents/browser/profile-clean` (5.5 MB on disk) across runs; it is
logged out only because nobody logged in on it. If an agent ever logs in there, "clean" silently
stops being clean.
Fix: either say "second, currently logged-out profile", or have the wrapper wipe
`profile-clean` on start when `PW_PROFILE=clean`. Owning ticket: T12.

**D7 — LOW — T14 — 15 temp files left in `/tmp`.**
`t14.png`, `t14-a…t14-n.png`, `chrome-t14.log`, `chrome-t14b.log` (~1.5 MB) from the implementation
session. Harmless (`/tmp` is cleared on boot) but noise for the next agent's screenshot listing.
Fix: implementation agents should write scratch screenshots under a per-ticket dir and remove it at
the end. Owning ticket: T14.

**D8 — INFO — T12 — the wrapper only passes `--user-data-dir` when `PW_PROFILE` is set.**
With `PW_PROFILE` unset the persistent profile comes from `~/.claude/playwright-mcp.json`, so
running `~/agents/bin/playwright-mcp` **without** `--config` (e.g. a future systemd unit that forgets
the flag) silently gets a throwaway profile and no output dir, with no warning. Not a bug today —
the registered command always passes the config — but a foot-gun worth one defensive default.
Owning ticket: T12.

## Owner-review items

1. **Chrome extension permissions (T14).** The "Claude" extension (id `fcoeoabgfenejglbffodgkkbkcdhcgfn`,
   v1.0.91, from the Web Store) is installed in your **default** Chrome profile with these permissions
   granted and active: **read and change all your data on all websites** (`<all_urls>`, host and
   scriptable), **access the page debugger backend** (`debugger` — full CDP control of any tab),
   `tabs`, `tabGroups`, `scripting`, `webNavigation`, `downloads`, `nativeMessaging`, `identity`,
   `notifications`, `storage`, `unlimitedStorage`, `offscreen`, `sidePanel`, `alarms`,
   `declarativeNetRequestWithHostAccess`. Site access is set to **On all sites**. This is the standard
   permission set for Claude in Chrome, but it is broad and it applies to the profile where you are
   signed into Google. Remove it from `chrome://extensions` if you would rather it lived in a separate
   Chrome profile.
2. **What account authorisation is actually in effect.** QA found the extension's side panel showing
   **"Iniciar sesión"** — i.e. it is **not currently signed in** to claude.ai in Chrome, and it says
   Claude in Chrome needs a paid plan. So whatever consent screen was clicked during T14 is **not
   granting any live access today**; the only thing installed and active is the extension itself plus
   the local native-messaging host (`~/.claude/chrome/chrome-native-host`, a Unix socket in `/tmp`,
   mode 0600, reachable only by your user). QA deliberately did **not** open your claude.ai session,
   did not sign in, and did not read your Chrome cookies. If you want to be sure nothing lingers,
   check **claude.ai → Settings → Connectors/Authorised apps** yourself and revoke anything you do not
   recognise; deciding whether to sign the extension in is also yours (D1).
3. **Do you want Chrome permanently open?** T14 chose *no autostart service* — Chrome must be started
   with `pc open google-chrome` and a GNOME keyring dialog must be cancelled each time. If you want
   agents to use your Chrome unattended, say so and the `chrome-session.service` from step 2 of the
   ticket can be enabled (and the keyring set to an empty password so the dialog stops).

## Not testable / out of scope

- **T14's Goal in an interactive session.** QA can only run `claude -p`; the ticket's own check is
  the `-p` form and it fails, but "works interactively" cannot be proven from here. After D1 is fixed
  the owner should try `claude --chrome` interactively once.
- **Behaviour under a systemd timer (T15).** QA approximated it with `env -i` and it passed; the real
  unit environment (no `XDG_RUNTIME_DIR`, no session bus) only exists once T15 lands. Headed runs will
  certainly need `~/agents/bin/env.sh` there.
- **Multi-env `moodle-envs` output.** Only 5.2 exists; multi-env listing was exercised with a
  throwaway directory (removed), not with a second real install.
- **Long-run profile durability.** Whether the Moodle session cookie survives days (Moodle session
  timeout, not Chromium) was not tested — only across ~9 sessions within one hour.
- **T13 against 4.x layouts** (`www` instead of `www/public`): the code path exists in `moodle-envs`
  and the skill documents it, but no 4.x env is installed to test it.
