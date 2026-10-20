# Image re-read guard: deny the 4th Read of an unchanged image, reset on compaction

Ticket: T495, T513 · Last verified: 2026-10-19 by `python3 ~/agents/hooks/image-reread.test.py` (32/32 ok) on Claude Code 2.1.303

## When to use
Changing or debugging the hook that denies a 4th `Read` of the same unchanged image in one context, or a "read 3× already"
denial that looks wrong. Not for screenshot policy in general (AGENTS.md §1, `pc` text verbs first).

## The path we took
One script, `hooks/image-reread.py`, wired on two Claude Code events by `adapters/claude/settings.fragment.json`:

| Event | What it does |
|---|---|
| `PreToolUse` (matcher `Read`) | count per `realpath|mtime_ns|size` in `$XDG_RUNTIME_DIR/image-reread/<session_id>-<agent_id>.json`; deny at count 3 |
| `PostCompact` (all triggers) | delete that context's count file: the image is no longer in context after a compaction |

Context key = `session_id` + `agent_id` (absent on the main thread), so each subagent has its own counts and its own reset.
`PostCompact` was chosen over `SessionStart` `source:"compact"` (main thread only) and `PreCompact` (fires before the
summary; the compaction can still fail). Byte gate first: anything without `"postcompact"`, or without `"read"` plus an
image extension, exits before `import json`.

## Exact commands
```bash
python3 ~/agents/hooks/image-reread.test.py          # fixture runtime dir, selftest, 7-day transcript replay
~/agents/bin/tests/run.sh --only 'hooks/image-reread*'
~/agents/adapters/claude/install                       # writes settings.json: the owner runs it (settings.json rule)
```

## Pitfalls (measured)
- Before T513 a compaction kept the counts, so a legitimate re-read after compaction was denied; now 3 reads, compact,
  3 more pass and the 4th is denied (test `compaction: …`).
- `PostCompact` is skipped by Claude Code 2.1.303 for subagents in delegated-observation mode (`agentType=="subagent"`
  and `delegatedObservation`); those keep their counts until the session ends. Ordinary subagents get it with `agent_id`.
- Main-thread compaction never resets a subagent's file, and vice versa (key includes `agent_id`).
- A fragment change only takes effect after `adapters/claude/install` merges it into `~/.claude/settings.json`;
  dry-run first with `SETTINGS_OUT=<copy> python3 adapters/claude/merge-settings.py install …` (adds only `PostCompact`).
- p50 latency 16 ms (byte gate) / 35 ms (image Read) vs the 107 ms budget at load ~26.

## Links
- Code: `~/agents/hooks/image-reread.py`, `~/agents/adapters/claude/settings.fragment.json`
- Tests: `~/agents/hooks/image-reread.test.py`
- Hook input shape: `strings` on `~/.local/share/claude/versions/<ver>` around `hook_event_name:"PostCompact"`
