# Discord forum bot: requests from family and friends (and their agents) in a Forum channel

Ticket: T348, T361, T448 · Last verified: 2026-10-20 by T846 read-only audit (`--help`, paths, code); before: 2026-10-19 by 28 fixture tests (29 `test_` functions now), sandbox selftest, a live gateway connect through the sandbox

## When to use
Run, check, change or debug the `agents` Discord bot, post into its forum, or build another sandboxed chat bot.
Not for a Discord bridge into an interactive Claude session: that is the official `discord@claude-plugins-official`
channel plugin (`--channels`), which gives the chat that session's tools.

## The path we took
- Survey: the official channel plugin (Bun MCP, DM pairing, full-session tools: rejected for untrusted forum posts),
  discord.py 2.7.1 (chosen, gateway only), fleet `code-review-netproxy` + `code-review-sandbox` (copied pattern).
- Three processes in one unit: netproxy (CONNECT, 443 to discord.com/.gg/discordapp.* only) → bot in bwrap (empty
  home, code ro, `state/` rw, token ro, own net namespace) → runner outside (validates job files, re-checks approval
  on Discord itself, runs `claude -p --tools ""` with a fixed system prompt for answers and `agent-exec` + fleet
  preamble for approved work in `work/<job>/`, which the bot cannot see).
- Approval = moderated `approved` tag set by the owner himself (the guild audit log, THREAD_UPDATE 111, names who
  added it; a moderator's tag starts nothing), or the guild owner's ✅, or an allowlisted author
  (`DISCORD_ALLOWLIST`, empty). Bot and runner both check; fail closed. Owner id comes from the guild at start (`discord-bot setup`).
- Limits per member per UTC day: `DISCORD_REQUESTS_PER_DAY` (10) answers, `DISCORD_JOBS_PER_DAY` (3) jobs, the
  latter counted again by the runner. Every reply passes `sanitize.clean` (paths, IPs, hosts, emails, tokens,
  config values) twice.

## Exact commands
```bash
discord-bot status            # unit, uptime, API readiness (guilds, intent), guild, forum, tags
discord-bot setup             # store guild/forum/owner ids in config.env; exit 3 + the exact missing item
discord-bot invite            # OAuth invite URL with the needed permissions
discord-bot read [thread-id]  # forum posts, or the last 20 messages of one
discord-bot post <thread-id> <text…> | discord-bot post --new <title> <text…>
discord-bot test              # fixture tests (fake Discord REST, recorded gateway payloads)
discord-bot selftest          # sandbox proof: other secrets unreadable, no writes outside state/, net only Discord
journalctl --user -u discord-bot -n 50
```

## Pitfalls (measured)
- `claude -p` with a `--system-prompt-file` still gets an automatic note with the account e-mail: the sanitizer
  strips every e-mail address. `--bare` would hide it but needs an API key (OAuth is never read).
- The fleet adapter treats `AGENT_TOOLS=""` as unset (`${AGENT_TOOLS:-…}` → Bash,Read,Edit,Write), so tool-less
  answers call `claude --tools ""` directly instead of `agent-exec`.
- Writes to `/etc` or `$HOME` inside bwrap succeed on the sandbox's tmpfs; the selftest checks from outside that no
  real file appeared (9 targets).
- With 0 guilds or the Message Content intent off, `setup` exits 3 and the unit retries every 60 s; a text channel
  named like a forum is not a forum: only type 15 counts.
- Gateway THREAD_UPDATE carries no actor: a moderated tag only proves "some Manage Threads holder". Who applied it is
  only in the audit log, which needs View Audit Log (128, in `invite` PERMS); without it the tag path fails closed
  (403 50013, status `problem`) and only ✅ approves (T361).
- The app was `bot_public: true`: anyone with the id could invite it. The bot leaves any guild other than
  `DISCORD_GUILD_ID`; turning off Public Bot in the Developer Portal closes it at the source.

- discord.py's own reconnect backs off up to 1024 s (seen 799 s) with a 45-line traceback per drop and does not retry
  a failed login (DNS at boot exited the unit). `gateway.stay_connected` runs `connect(reconnect=False)` on a fresh
  client per session: one WARNING line, 1, 2, 4 … 60 s; only LoginFailure and close 4004/4010-4014 exit (T448).
  A drop re-IDENTIFIES (no RESUME), so events during the gap are not replayed.

## Links
- Code: `~/agents/discord-bot/` (`discordbot/`, `bin/serve`, `bin/sandbox`), CLI `~/agents/bin/discord-bot`, unit `~/agents/units/discord-bot.service`
- Tests: `~/agents/discord-bot/tests/` via `discord-bot test` (also `bin/tests/discord-bot.test.sh` in `run.sh`); `discord-bot selftest`
- Design: `$AGENT_WORK/research/2026-10-15/T348/architecture.md`
