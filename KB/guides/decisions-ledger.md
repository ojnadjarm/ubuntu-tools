# Decisions ledger: standing owner decisions per project, handed to subagents

Ticket: T396, T1754 · Last verified: 2026-11-17 (T1754: `bin/tests/brief-check.test.sh` green, brief-lint no longer warns); before: 2026-10-20 (T846) by paths, `brief-lint --help`, `lib/decisions.py` read and one `digest('ailearning')` (8 of 20 lines, 1133 chars); tests last run 2026-10-18 (orbit-hook 41/41, brief-check 9/9)

## When to use
- The owner states a standing decision ("desktop only", "delete those buttons", "Chapter 1 stays"): add one line to the ledger.
- Not for one-off actions ("uninstall X"); only rules that must hold for every later ticket.

## The path we took
- Evidence: T392 FRICTION.md row 3, 9 owner messages 2026-10-07..12 re-reporting decisions ("I have tell you that several times").
- Survey: decisions lived in 20+ memory files the orchestrator reads but briefs and subagents do not; the closest start was
  the T379 SubagentStart `additionalContext` (guides) and the T381 `brief-lint`; both extended, nothing new to run.
- Ledgers: fleet `~/agents/KB/DECISIONS.md`; owner repos stay clean, so `$AGENT_WORK/decisions/{ailearning,portfolio,vass}.md`.
  Line shape: `- YYYY-MM-DD · decision · "owner's words"`.
- One module `lib/decisions.py` (project regexes, ledger path, `named()`, `unreferenced()`, `digest()`); `orbit-hook` imports it
  (single source, open for a new project by one dict row).
- `brief-lint` warned on a brief naming a project but not its ledger until T1754 (owner 2026-11-17 "Yes all"): the memory cards
  (T1599) carry the dated decisions every agent loads, so the warning went.
- `orbit-hook start`: for each project the Agent description names, appends `digest()` (quotes cut, ≤ 1200 chars ≈ 300 tokens,
  `(+N more in <path>)`) after the guide hits in `additionalContext`.

## Exact commands
```bash
python3 -c "import sys; sys.path.insert(0,'$HOME/agents/lib'); import decisions; print(decisions.digest('ailearning'))"
```

## Pitfalls (measured)
- The digest only fires when the Agent `description` names the project (e.g. "T400 ailearning sheet 6 fix"); "T334 pencil tick" gets nothing.
- 20 of the T38x/T39x briefs warned on the first lint (most for fleet); the warning was advice, not a gate (gone since T1754).
- `lesson`/`sheet N`/`U0N` count as ailearning in `named()`, so the digest also fires on a make-lesson fleet ticket.
- Ordered newest re-breaks first: the 300-token digest keeps the top 8 lines of the 20-line ailearning ledger (2026-10-20).

## Links
- Code: `~/agents/lib/decisions.py`, `~/agents/bin/orbit-hook`
- Ledgers: `~/agents/KB/DECISIONS.md`, `~/agent-work/decisions/`
- Tests: `~/agents/bin/tests/orbit-hook.test.py` (decisions: 4 checks)
