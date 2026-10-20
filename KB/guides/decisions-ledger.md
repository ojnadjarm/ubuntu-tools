# Decisions ledger: standing owner decisions per project, linted into briefs, handed to subagents

Ticket: T396 · Last verified: 2026-10-20 (T846) by paths, `brief-lint --help`, `lib/decisions.py` read and one `digest('ailearning')` (8 of 20 lines, 1133 chars); tests last run 2026-10-18 (orbit-hook 41/41, brief-check 9/9)

## When to use
- The owner states a standing decision ("desktop only", "delete those buttons", "Chapter 1 stays"): add one line to the ledger.
- Writing a brief for ailearning, portfolio, vass or fleet work: name the ledger file in the brief.
- Not for one-off actions ("uninstall X"); only rules that must hold for every later ticket.

## The path we took
- Evidence: T392 FRICTION.md row 3, 9 owner messages 2026-10-07..12 re-reporting decisions ("I have tell you that several times").
- Survey: decisions lived in 20+ memory files the orchestrator reads but briefs and subagents do not; the closest start was
  the T379 SubagentStart `additionalContext` (guides) and the T381 `brief-lint`; both extended, nothing new to run.
- Ledgers: fleet `~/agents/KB/DECISIONS.md`; owner repos stay clean, so `$AGENT_WORK/decisions/{ailearning,portfolio,vass}.md`.
  Line shape: `- YYYY-MM-DD · decision · "owner's words"`.
- One module `lib/decisions.py` (project regexes, ledger path, `named()`, `unreferenced()`, `digest()`); `brief-lint` and
  `orbit-hook` both import it (single source, open for a new project by one dict row).
- `brief-lint` prints `WARN <brief>: names <project> but not its decisions ledger <path>`; exit code unchanged.
- `orbit-hook start`: for each project the Agent description names, appends `digest()` (quotes cut, ≤ 1200 chars ≈ 300 tokens,
  `(+N more in <path>)`) after the guide hits in `additionalContext`.

## Exact commands
```bash
brief-lint ~/agent-work/briefs/T4*.md | grep WARN          # briefs missing their ledger
python3 -c "import sys; sys.path.insert(0,'$HOME/agents/lib'); import decisions; print(decisions.digest('ailearning'))"
```

## Pitfalls (measured)
- The digest only fires when the Agent `description` names the project (e.g. "T400 ailearning sheet 6 fix"); "T334 pencil tick" gets nothing.
- 20 of the T38x/T39x briefs warned on the first lint (most for fleet): the warning is advice, not a gate.
- `lesson`/`sheet N`/`U0N` count as ailearning, so a make-lesson fleet brief warns too; naming the ledger silences it.
- Ordered newest re-breaks first: the 300-token digest keeps the top 8 lines of the 20-line ailearning ledger (2026-10-20).

## Links
- Code: `~/agents/lib/decisions.py`, `~/agents/bin/brief-lint`, `~/agents/bin/orbit-hook`
- Ledgers: `~/agents/KB/DECISIONS.md`, `~/agent-work/decisions/`
- Tests: `~/agents/bin/tests/brief-check.test.sh` (fixtures T910/T911), `~/agents/bin/tests/orbit-hook.test.py` (decisions: 4 checks)
