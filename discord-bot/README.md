# discord-bot — the family/friends Discord forum bot "agents" (T348)

Serves one guild's Forum channel: every post is a request. Tags `new` → `accepted` → `in progress` → `done`,
answers in the thread with a tool-less Claude, and runs real work only after the owner approves (moderated tag
`approved`, or his ✅ on a message in the thread) as a fresh fleet agent. Every message is untrusted data, people
and friends' bots alike.

- Unit: `discord-bot.service` → `bin/serve` (setup, then runner outside + bot inside `bin/sandbox`). Kill switch: `agents-stop`.
- CLI: `discord-bot status|setup|post|read|invite|selftest|test`.
- Config: `DISCORD_*` keys in config.env (`config.example.env`); token `~/agents/secrets/discord-bot-token`.
- Code: `discordbot/` (core, gateway, rest, runner, jobs, store, sanitize, netproxy, cli); tests in `tests/`.
- State: `state/` (bot-writable: status, threads, rate ledger, job spool), `runner-state/` and `work/` (runner only).
- Guide: `~/agents/KB/guides/discord-bot.md`; architecture: `$AGENT_WORK/research/2026-10-15/T348/architecture.md`.
