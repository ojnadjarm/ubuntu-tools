# "What's pending?" — one owner status screen (running, done, waiting on you, queued)

Ticket: T395 · Last verified: 2026-10-20 (T846) by `agents-status --owner --help`, `lib/owner_status.py` read and paths; 2026-10-18 by bin/tests/agents-status-owner.test.py (10/10) and live dashboard shots at 5 widths

## When to use
The owner asks what is running, pending, left or waiting on him. Answer from `agents-status --owner`, not by hand.
Not for the persistent-agent timer table (plain `agents-status`) or machine state (`pc status`).

## The path we took
- Survey: `agents-status` (timer table), `owner-todo`, `/api/status` verdict, orbit-hook claims existed; none joined the four.
- `lib/owner_status.py` collects; `agents-status --owner` renders ≤ 15 lines; the dashboard imports the same module.
- Running = `$XDG_RUNTIME_DIR/dark-eye/orbit-claims.json` (label from the subagent's `meta.json`) + active `agent@*.service`.
- Done = dated `- YYYY-MM-DD` lines of `$AGENT_WORK/history.md` after the last-ask stamp `~/agents/state/owner-status.json`.
- Waiting = open `owner-todo` items (top 3). Queued = `briefs/T*.md` edited < 48 h with no history line and not running.
- Dashboard Overview: `owner` block in `/api/status` (swr cached), one counts line above the verdict ("done today").

## Exact commands
```bash
agents-status --owner                    # the screen; moves the last-ask stamp
agents-status --owner --since 2026-10-18 # done since a date; stamp untouched
agents-status --owner --json             # all four sections; stamp untouched
python3 ~/agents/bin/tests/agents-status-owner.test.py
```

## Pitfalls (measured)
- history.md has undated sub-bullets: 396 `- ` lines vs 119 dated; only dated lines count or "done today" read 277 instead of 37.
- Only the plain text run marks the stamp; tests set `OWNER_STATUS_STAMP`, `AGENT_WORK`, `XDG_RUNTIME_DIR`, `OWNER_TODO_LEDGER`.
- Orbit claims only see Claude subagents; headless runs come from `agent@*.service`.

## Links
- Code: `~/agents/lib/owner_status.py`, `~/agents/bin/agents-status`, `~/agents/dashboard/dash/services/system.py` (`owner_counts`), `static/next/js/screens/overview.js`
- Tests: `~/agents/bin/tests/agents-status-owner.test.py`
- Shots: `~/agent-work/evidence/T395/overview-{400,768,1366,1920,2560}.png`
