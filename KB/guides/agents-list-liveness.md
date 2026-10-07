# Decide whether an agent is live or finished (dashboard Agents list, one rule per source)

Ticket: T66, T89, T90 · Last verified: 2026-09-25 by `tests/test_agents_live.py` (98 dashboard tests) and live `/api/agents`: 3 working, 10 recent

## When to use
- Anything that must answer "which agents are running now?": the dashboard Court, a digest, a reaper, a status line.
- A finished agent still shows as running, or a live one shows as done.
- Reuse `dash/services/agents.py` (or copy its rule) rather than inventing a new timeout. Not for orbiters on the Eye:
  those go out by `orbit-hook` (`orbit-hook-orbiters.md`); stuck shell waits: `wait-for-and-stuck-loops.md`.

## The path we took
- Cause (T66): `/api/agents` returned all 34 sub-agents of the session; liveness had only two signals (a
  `SubagentHandback`, or `eye status <id> done|error` in `log/actions.jsonl`). Stopped, killed or interrupted agents never
  handed back and stayed "stale" under "running now" forever; workflow agents were not read at all.
- One adapter per source, one record `{id, label, type, started, last, state, doing, report}`:

| Source | Where | Ended when | Live when |
|---|---|---|---|
| One-off sub-agent | `<session>/subagents/agent-*.jsonl` | handback, `eye status done\|error`, or `<task-notification>` completed/failed/killed/stopped in the orchestrator transcript | no end event and a transcript write < 15 min (`WORKING_S`) |
| Workflow agent | `<session>/subagents/workflows/wf_*/` | its `result` (done) or `failed` (error) row in `journal.jsonl`, or the run's task notification | same |
| Orchestrator | tmux `$ORCHESTRATOR_TMUX_SESSION` + transcript | tmux session gone → `off` | transcript < 60 s → `running`, else `idle` |
| Rostered agent | `agent@<name>.service`/`.timer`, or tmux `<name>` | timer disabled, no tmux → `off` | unit active or tmux transcript < 60 s → `running`, else `idle` |
| Orbiter | `eye status` bridge | — | a hint only: keeps an un-ended agent `working` |

- End signals are parsed by one shared stdlib module, `~/agents/lib/agent_ends.py` (T90): `scan()` folds task notifications,
  `TaskStop` calls and workflow launches from the orchestrator transcript incrementally, `journal()` reads a run's result/failed/started
  rows, `resumed()` is the later-same-label-start rule (T89). `orbit-hook`'s sweep uses the same module; change a rule there once.
- An end event wins unless the agent wrote again more than `SLACK_S` 60 s after it and < 15 min ago (a resumed agent revives).
- A handback or done/error ≤ `SLACK_S` before a killed/stopped note beats it: the orchestrator stops agents 4-5 s after they hand back
  (3 of 46 in session 828baebc), and the newest-wins rule showed them `stale` (F21, 2026-10-03).
- `shown()` is the single view policy: every `working` record, then ended ones of the last 24 h, newest first, max 10.
  Court: "running now" = working only; ended ones in a collapsed "recent · 24 h" `<details>`; outer ring = persistent crew.
- Cost: the 13 MB orchestrator transcript and the 13.5 MB `log/actions.jsonl` feed are read incrementally (offset memo, only appended bytes;
  the feed keeps every `eye status` event, 302 rows, first read 23 ms); one batched
  `systemctl show` + one `tmux ls`, memoised 5 s; API memo 3 s. Read-only: nothing on disk is touched.

## Exact commands
```bash
curl -s http://127.0.0.1:19998/api/agents | python3 -m json.tool | less    # orchestrator, subagents, orbiters, roster, claims
cd ~/agents/dashboard && python3 -m pytest tests/test_agents_live.py -q    # fixture sessions: finished leaves, live stays, resume revives, workflow, workflow failed, cap, persistent
systemctl --user restart agents-dashboard && curl -sI http://127.0.0.1:19998/ | head -1
systemctl --user list-units 'agent@*'; eye status                           # cross-check against units and orbiters
```

## Pitfalls (measured)
- Before: 3 "running now" (1 working, 2 stale) + 31 finished shown. After: 4 working, matching the 4 live orbiters.
- A missing end event is normal (stop, kill, interrupt, context loss): never require a handback to call an agent done.
- Timing: a finished agent leaves the live list in ≤ 30 s (30 s tick), ≤ 8 s while Court is open with work (5 s poll).
- A workflow journal `failed` row is an end event (`error`); ignoring it showed a failed agent as `stale` (F30, 2026-09-24).
- The feed once read only the last 1 MiB of `actions.jsonl`; a busy hour (1.49 MB on 2026-09-24) pushed `eye status <id> done` out and
  the agent fell back to `stale` (F21, 2026-09-26). Never window the feed by bytes.
- `cache.cached()` runs `collect()` outside its lock on a threaded server: two polls advanced the feed offset twice and skipped
  `eye status` lines (F24, 2026-10-03). `feed()` reads and advances under `_feed_lock`; keep any new incremental reader locked too.
- Workflow agents sit one folder deeper than one-offs; the same miss broke `orbit-hook` (T68). Glob every depth under `subagents/`.
- `subagents()` reads only the newest session that spawned any; agents of an older session drop out when a new one spawns.
- Tests use fixture transcripts only (paths are module constants the tests repoint); never the real `~/.claude/projects`.

## Links
- Code: `~/agents/lib/agent_ends.py` (end signals, shared with `orbit-hook`), `~/agents/dashboard/dash/services/agents.py` (`ends`, `state_of`, `one_offs`, `workflow_agents`, `persistent`, `shown`),
  `static/next/js/screens/court.js`, `static/next/next.css`
- Tests: `~/agents/dashboard/tests/test_agents_live.py`
- Design: `~/agents/research/2026-09-23/T66/design.md`, shots `T66/shots/` · brief `~/agents/briefs/T66-agents-list-cleanup.md`
