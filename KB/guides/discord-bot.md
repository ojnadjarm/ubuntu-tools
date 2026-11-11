# Discord forum bot: requests from family and friends (and their agents) in a Forum channel

Ticket: T348, T361, T448, T1546-M2, T1634-V8 · Last verified: 2026-11-11 (T1634-V8: 9 vault REST fixture tests, vault-unit.test.sh: a throwaway unit with the gateway's hardening reads a fake sealed credential, 5 routes read 0 bytes from the agents' user, a same-user control fails); 2026-11-10 by 36 fixture tests (T1546-M2: liaison mode + owner ✅ leaves `pending/` empty, writes one approval record); 2026-10-20 by T846 read-only audit (`--help`, paths, code); before: 2026-10-19 by 28 fixture tests (29 `test_` functions now), sandbox selftest, a live gateway connect through the sandbox

## When to use
Run, check, change or debug the `agents` Discord bot, post into its forum, or build another sandboxed chat bot.
Conversation in #foro (Spanish replies, collab PRs): guide `discord-liaison`; with `DISCORD_FORUM_REPLIES=liaison` the bot only tags and nudges (T1409): the approved tag starts nothing, the owner's ✅
writes `state/approvals/<message>.json` for discord-liaison to pass to the thread's manager (T1546-M2); no bot worker runs.
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
- Liaison mode (T1546-M2, owner 2026-11-10: "his ✅ reaches the manager"): `on_thread_update` only nudges;
  `on_message_reaction_add` with the owner's ✅ writes the approval record (gateway `user_id`, atomic) and nudges.
  Before M2 his ✅ started a fleet agent with none of the project's rules beside the project's manager.
- Limits per member per UTC day: `DISCORD_REQUESTS_PER_DAY` (10) answers, `DISCORD_JOBS_PER_DAY` (3) jobs, the
  latter counted again by the runner. Every reply passes `sanitize.clean` (paths, IPs, hosts, emails, tokens,
  config values) twice.

- Vault (T1634-V8): the token is the vault secret `discord-bot-token` (class free). The gateway runs as the system unit
  `discord-bot-gateway.service` under its own user `fleet-discord` (V1: a same-user unit leaks its credential by the
  host path), code and venv copied root-owned to `/opt/discord-bot`, `LoadCredentialEncrypted=fleet.discord-bot-token`,
  `PrivateNetwork=yes` with the in-process relay to `discord-bot-netproxy.service` (same user, `/run/discord-bot/proxy.sock`,
  443 to Discord hosts only), state bound from `discord-bot/state` (ACL: fleet-discord and the owner, default ACL on new
  files). Every other caller (runner, `discord-bot` CLI, discord-liaison, its relay and job workers) calls REST through
  the broker: `make_rest` → `LeaseSource` (the launcher's `FLEET_LEASE_DISCORD_BOT_TOKEN`, else its own grant from the
  admin socket, renewed 5 min before it ends) → `http://127.0.0.1:<FLEET_VAULT_PORT>/<lease>/discord-bot-token/api/v10/…`,
  the broker adds `Authorization: Bot …` (registry `scheme = "Bot"`, methods GET/POST/PUT/DELETE, path `/api/v10/`).
  The triage run gets its lease by `Secrets: discord-bot-token` in its BRIEF.md; a liaison job worker gets one minted by
  `job-run` for the job's time limit, revoked at the end. A replaced token reaches the gateway at its next start: the old
  one fails with 4004, the unit exits and restarts after 60 s with the new sealed value.

## Exact commands
```bash
discord-bot status            # unit, uptime, API readiness (guilds, intent), guild, forum, tags
discord-bot setup             # store guild/forum/owner ids in config.env; exit 3 + the exact missing item
discord-bot invite            # OAuth invite URL with the needed permissions
discord-bot read [thread-id]  # forum posts, or the last 20 messages of one
discord-bot post <thread-id> <text…> | discord-bot post --new <title> <text…>
discord-bot test              # fixture tests (fake Discord REST, recorded gateway payloads)
discord-bot selftest          # gateway unit proof: other uid, own network namespace, its credential reads 0 bytes here by 5 routes
sudo -n ~/agents/discord-bot/install [--apply|--remove]   # gateway + netproxy system units, /opt copy, bot.env, state ACL
pc units restart discord-bot-gateway --system --apply     # start or reload the gateway after an install
journalctl --user -u discord-bot -n 50; journalctl -u discord-bot-gateway -n 50
```

## Pitfalls (measured)
- systemd-run checks ExecStart on the host before the unit's mounts: a path only visible through BindPaths= fails
  "Failed to find executable"; wrap it in `/bin/sh -c` (T1634-V8). BindPaths= from /home works under ProtectHome=yes.
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
