# Agent memory: load the core and a domain card, note a lesson, check the store, run the keeper (agent-memory)

Ticket: T1599 (M00-M10), T1772 · Last verified: 2026-11-18 by `memory-quiz.test.sh`, `memory-check.test.sh`, `memory-keeper.test.sh` (all green) and `memory apply` of the slim cards (1f9df6e, green, 1 brittle row)

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
each mapped folder (git-excluded, never in a protected folder); the orchestrator's `MEMORY.md` becomes a generated page
(the index only: subagents read it; the owner seat's card comes by the SessionStart hook `memory-carrier session-start`, T1752);
`MEMORY_DOMAINS` in each rostered `agent.env`; the Claude adapter appends `memory load` to every headless run.
The keeper (`~/agents/memory-keeper`, timer 04:10, `PRECHECK` skips an empty night) files notes into pages in a staging
copy, gates with `memory check`, commits; Sunday adds the weekly pass and the full quiz.
Quiz gate (T1772): a row green in the baseline and red by vote blocks only when a must word (any `|` word) is gone from
the text the quiz loads for it (`memory load` + pages); with every must word loaded it is `quiz · brittle` on stderr, never blocking.

## Exact commands
```bash
memory load                          # routed by cwd, $CHAT_SEAT, $MEMORY_DOMAINS
memory load mooblox                  # core + one domain card (brief line: `Memory: memory load <d>`); core skipped where ~/CLAUDE.md gave it
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
- Quiz drift (T1766): the 11-12 card reword dropped the must words of c18 "fear", c19 "changed", c21 "measured" and
  c22's framing but left their questions, and they surfaced only when CORE changed again (keeper red 3/3 on 11-18);
  reword a row's question in the same edit, and before applying grep each staged must word in the pages. A changed
  page re-asks all its rows (~180 for core): about 1 baseline-green row still flips per apply (c01, c28, c20).
- A must cell is `a;b` (every word) or `a|b` (any word), T1768; before it every "|" word was required (74 staged cells).
- Re-asks in the same chunk as the first ask are not independent votes: c14 went red in 2 applies and passed alone
  (T1768); each red row is now re-asked alone, one question per call (T1769): 2 calls per red, 6 for 3 reds.
  The 2-of-3 vote re-asks in the same chunked context, so its asks are not independent: on 11-18 c14 "only he" (rule
  unchanged) was red in 2 of 2 applies yet green asked alone; c20 "page" (11-18 12:05) and 60087263e2 "claims" too.
- A red apply merged the store's new ledger lines into the staging; re-applying that staging went red on `core/ledger.md`
  "changed in both" (T1771: 2 of 3 applies). `_append_merge` now adds only the staging's tail lines the store lacks (T1772).

## Links
- Code: `bin/memory`, `lib/memory_store.py`, `lib/memory_route.py`, `lib/memory_check.py`, `lib/memory_quiz.py`,
  `lib/memory_sources.py`, `lib/memory_txn.py`, `adapters/claude/memory-carrier`, `memory-keeper/`
- Tests: `bin/tests/memory*.test.sh`, `bin/tests/fleet-backup.test.sh` (store in tier 1)
- Design / results: `~/agent-work/research/2026-11-10/T1599/` (PLAN.md, done/M00-M10.md)
- Skill: `/memory`
