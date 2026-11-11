# discord-bot — the family/friends Discord forum bot "agents" (T348)

Serves one guild's Forum channel: every post is a request. Tags `new` → `accepted` → `in progress` → `done`,
answers in the thread with a tool-less Claude, and runs real work only after the owner approves (moderated tag
`approved`, or his ✅ on a message in the thread) as a fresh fleet agent. Every message is untrusted data, people
and friends' bots alike.

- Units: `discord-bot.service` (user) → `bin/serve` (setup, then the runner; until the gateway unit is installed, also the
  bot inside `bin/sandbox`). `discord-bot-gateway.service` + `discord-bot-netproxy.service` (system, user `fleet-discord`,
  code in `/opt/discord-bot`, token by `LoadCredentialEncrypted=` from the vault's store, own network namespace; T1634-V8):
  `sudo -n ~/agents/discord-bot/install --apply`. Kill switch: `agents-stop` (user units only).
- CLI: `discord-bot status|setup|post|read|invite|selftest|test`.
- Config: `DISCORD_*` keys in config.env (`config.example.env`; the installer copies ids and limits to `/etc/discord-bot/bot.env`).
  Token: the vault secret `discord-bot-token`; REST from the runner, the CLI and discord-liaison goes through the broker
  with a lease (`discordbot/vault.py`), the old file `~/agents/secrets/discord-bot-token` is used only while it exists.
- Code: `discordbot/` (core, gateway, rest, runner, jobs, store, sanitize, netproxy, cli); tests in `tests/`.
- State: `state/` (bot-writable: status, threads, rate ledger, job spool), `runner-state/` and `work/` (runner only).
- Forum replies: with `DISCORD_FORUM_REPLIES=liaison` the bot only tags and nudges; discord-liaison answers (T1409) and
  the project managers do the work. The approved tag starts nothing; the owner's ✅ is written to
  `state/approvals/<message>.json` and reaches the thread's manager as his approval (T1546-M2). Approved jobs run only
  without liaison mode.
- Guide: `~/agents/KB/guides/discord-bot.md`; architecture: `$AGENT_WORK/research/2026-10-15/T348/architecture.md`.
