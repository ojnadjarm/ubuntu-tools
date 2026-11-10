# Agent memory: load the core and a domain card, note a lesson, check the store, run the keeper (agent-memory)

Ticket: T1599 (M00-M10) · Last verified: 2026-11-10 by `memory check` (exit 0), `memory-index-cap.test.sh`, `fleet-backup.test.sh` (25/25), `memory-keeper.test.sh`, `memory check --live` on the real store (5/5, 5/5 with mooblox; M10b)

## When to use
- You need what the owner taught the fleet: `memory load [domain]` (core card, then the domain cards, ids stripped).
- He corrected you, stated a preference, a decision was taken, or a measured pitfall cost over 10 minutes: `memory note`.
- Not for owner decisions history (the ledgers: `$MEMORY_HOME/core/ledger.md`, `domains/<d>/ledger.md`) or how-to knowledge (a guide).

## The path we took
One store, `$MEMORY_HOME` (default `~/memory`, its own local git repo; a private remote from M11 on), one writer per page.
| Part | What |
|---|---|
| `core/CORE.md` + `core/<topic>.md` | the owner's standing rules (card 4,096 B; topic files hold the why and his words) |
| `domains/<d>/DOMAIN.md` | one card per project or seat (6,144 B; orchestrator 8,192); `OWNER` names its only writer (`keeper` or a manager) |
| `domains.map` | folder or `seat:<id>` → domain (`protected` = keeper reads only, never writes) |
| `inbox/`, `domains/<d>/inbox/` | notes from any agent (`memory note`, ≤ 1,024 B, source stamped by the tool: owner, agent, untrusted) |
| `checks/` | ids (no lesson lost), quiz questions, quiz baseline |

Carriers (written by `memory install`, idempotent): `@~/memory/core/CORE.md` in `~/CLAUDE.md`; `CLAUDE.local.md` stubs in
each mapped folder (git-excluded, never in a protected folder); the orchestrator's `MEMORY.md` becomes a generated page;
`MEMORY_DOMAINS` in each rostered `agent.env`; the Claude adapter appends `memory load` to every headless run.
The keeper (`~/agents/memory-keeper`, timer 04:10, `PRECHECK` skips an empty night) files notes into pages in a staging
copy, gates with `memory check`, commits; Sunday adds the weekly pass and the full quiz.

## Exact commands
```bash
memory load                          # routed by cwd, $CHAT_SEAT, $MEMORY_DOMAINS
memory load mooblox                  # core + one domain card (brief line: `Memory: memory load <d>`)
memory note "Example lesson: the widget build needs the cache flag" --domain example
memory check                         # the gate: budgets, ids, format, secrets, machine values, untrusted, provenance
memory check --quiz --changed        # closed-book quiz on changed pages (haiku, majority of 3 on reds)
memory check --live --domains mooblox  # stub approvals + 5 questions through one real headless agent
memory install --plan                # what install would write; then `memory install`
memory sources --changed             # keeper: project files changed since the last run (read-only)
bash ~/agents/bin/tests/memory-keeper.test.sh   # fixture store only
```

## Pitfalls (measured)
- `memory` was not on PATH for 5 workers (M01-M09): a new CLI in `~/agents/bin` needs `~/agents/install.sh --links`.
- `claude -p` silently drops an unapproved external import (`@~/memory/...` from a repo's CLAUDE.md or CLAUDE.local.md):
  0/2 before the repo's one-time approval, 2/2 after (M00). The adapter's `memory load` and the brief line are the sure paths.
- Claude Code's Edit tool refuses to write through a symlink: a manager edits `$MEMORY_HOME/domains/<p>/DOMAIN.md`, not
  its old `PROJECT.md` link (M06). Shell `>>` to a linked ledger still works.
- One haiku answer per question gave 2-3 % red on right answers per full run (M07b); a red is re-asked twice, red only
  at 2 of 3 (M07c: 174/175 green).
- A test that writes a wrapper through a symlink overwrote `bin/memory` for 2 minutes and every `memory` call recursed
  (M09); the keeper test now guards the tool files' sha.
- The generated `MEMORY.md` holds no index until the keeper's first apply writes `INDEX.md` (M10: 38 lines, 4,224 B).
- `memory install` skips a served build (a folder holding the `sites publish` stamp `build.json`): `skipped (served
  build)`, no stub, no approval asked (M10 wrote 2 useless stubs there; M10b).
- `memory check --live` draws only questions whose must words are in the agent's `memory load` text: a card line with
  `→ topic` can carry an id whose question is answered only in the topic file (M10: 4/5, 2/5; M10b: 53 of 65 core
  questions drawable, 63 of 73 with mooblox); reds get the quiz's majority of 3.

## Links
- Code: `bin/memory`, `lib/memory_store.py`, `lib/memory_route.py`, `lib/memory_check.py`, `lib/memory_quiz.py`,
  `lib/memory_sources.py`, `lib/memory_txn.py`, `adapters/claude/memory-carrier`, `memory-keeper/`
- Tests: `bin/tests/memory*.test.sh`, `bin/tests/fleet-backup.test.sh` (store in tier 1)
- Design / results: `~/agent-work/research/2026-11-10/T1599/` (PLAN.md, done/M00-M10.md)
- Skill: `/memory`
