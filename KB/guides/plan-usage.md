# Plan limits: 5-hour and weekly used %, and the hourly orchestrator pulse

Ticket: T170 · Last verified: 2026-10-03 by live `plan-usage` (week 55% = owner's reading), `--check` at 50/55/80, pulse fixtures on a private tmux socket

## When to use
Before deciding how much work to start (lesson builds, swarms, big tests): read the plan meter instead of asking
the owner. Not for token counts per session (those are in `~/.claude/projects` transcripts, see `improve-meter`).

## The path we took
- Survey: statusline JSON `rate_limits` only reaches a configured statusLine command during a live render; the
  `anthropic-ratelimit-unified-*` headers need a paid model call; ccusage-style tools sum local tokens (an estimate,
  no plan %). Chosen: `GET https://api.anthropic.com/api/oauth/usage` with the Claude Code OAuth token, the same
  endpoint `/usage` reads: the plan's own percentage, no tokens spent.
- Architecture: source adapter `fetch()` (one endpoint → `{5h, week, scoped}`), cache `~/agents/state/usage.json`
  (last good reading, fallback on any failure, `stale` > 30 min), CLI `plan-usage` (line / `--json` / `--check`),
  timer `orchestrator-pulse.timer` → `orchestrator-pulse` (guarded `tmux send-keys`, same echo-then-Enter pattern
  as `notes-brain-arm`). Each piece has one job; the pulse never reads the meter itself, the orchestrator does.

## Exact commands
```bash
plan-usage                 # 5h 1% (resets 16:10) · week 55% (resets Tue 06 Oct 12:00) · source oauth-usage-api · age 0s
plan-usage --json
plan-usage --check 80      # exit 1 at/above 80% in either window, 2 = no reading
plan-usage --cached        # no network
systemctl --user list-timers orchestrator-pulse.timer
tail ~/agents/log/pulse.log
```

## Rules
- Lesson builds stop at weekly 80% (owner standing order): `plan-usage --check 80` before each new ticket.
- The weekly reset time is known (`plan-usage`); spare weekly budget before the reset is lost, so use it.

## Pitfalls (measured)
- 2026-10-03: the API's weekly reset was Tue 06 Oct 12:00 Madrid while the owner and the orchestrator believed
  Sun 04 Oct 12:00; read the reset from `plan-usage`, never from memory.
- The 5-hour window starts at the first message after the last one expired: 0-1% right after 11:10 is real,
  not a broken read (owner had read 5% in the previous window).
- `resets_at` comes as `14:09:59.8`; the CLI rounds to the minute (showed 16:09 before the fix).
- The token is read from `~/.claude/.credentials.json` and never refreshed here: refreshing would rotate the
  refresh token under the running Claude Code. A 401 (expired) falls back to the cache; any claude turn refreshes it.
- Pulse busy markers: `esc to interrupt` (turn running) and `Waiting for … background` (agents running); text on
  the `❯` line means the owner is typing. All skip, logged with the reason. The 130-char prompt wraps on an 80-col
  pane: the echo check joins the box lines before matching.

## Links
- Code: `~/agents/bin/plan-usage`, `~/agents/bin/orchestrator-pulse`, `~/.config/systemd/user/orchestrator-pulse.{service,timer}`
- Skill: `~/.claude/skills/plan-usage/SKILL.md`
- Kill switch: `agents-stop` stops `orchestrator-pulse.{service,timer}`; `agents-start` re-enables it from the roster row in `KB/orchestrator.md`
