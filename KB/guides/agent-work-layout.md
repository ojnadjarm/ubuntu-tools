# Agent work layout: where briefs, research, evidence and archives live (AGENT_WORK)

Ticket: T320 · Last verified: 2026-10-11 by the T320 batch B/C moves, `env.sh` and `agent_work.py` read-backs, `no-machine-values.test.sh`

## When to use
Writing a brief, research notes, spike or mockup output, ticket evidence, or archiving finished working papers.
Not for runtime state (`~/agents/log`, `~/agents/<name>/{logs,state,REPORT.md}`, `~/agents/browser`), which stays in `~/agents`.

## The path we took
One config key, `AGENT_WORK` (default `~/agent-work`, mode 700), outside every repo, so no repo carries agent working papers.

| Path | Holds |
|---|---|
| `briefs/` | orchestrator briefs `T###-slug.md` and per-ticket output dirs |
| `research/<date>/<ticket>/` | research, spikes, judge output, the kept taste-bar mockups (T65 atelier, T71 cutaway-plate, T91) |
| `evidence/<name>/` | finished ticket evidence: pre/post shots, videos, repro files (moved out of `~/drop`) |
| `archive/<origin path>/` | finished working papers under their original relative path (`archive/agents/portfolio/…`) |
| `owner/` | owner-provided material: **move only, never delete** (fleet rule 5.4) |
| `T320/` | the move plan, `MANIFEST.md`, `backup*/`, `trash/`, `rollback.sh` |

Resolvers, same order everywhere (env → `config.env` line → `~/agent-work`):
- bash: `bin/env.sh` exports `AGENT_WORK`; scripts that may run without it use `"${AGENT_WORK:-$HOME/agent-work}"`.
- Python: `lib/agent_work.py` `agent_work()`; skills outside the repo use `os.environ.get("AGENT_WORK", HOME/"agent-work")`.
- Markdown and JS strings: the literal `~/agent-work/…`.

## Exact commands
```bash
bash -c '. ~/agents/bin/env.sh; echo $AGENT_WORK'                         # the folder
python3 -c 'import sys,os; sys.path.insert(0, os.path.expanduser("~/agents/lib")); import agent_work; print(agent_work.agent_work())'
mkdir -p "$AGENT_WORK/research/$(date +%F)/TNNN"                           # a new ticket's research dir
~/agent-work/T320/rollback.sh B2                                            # undo one T320 step from its manifest
```

## Pitfalls (measured)
- Moves are `mv` on one filesystem: 35 GB moved instantly. Relative symlinks inside a moved tree break: 4 did in T320 (3 `node_modules` kit links, 1 `serve/orig`); find them with `find "$AGENT_WORK" -xtype l` after a move.
- A path relative to `$HOME` breaks in fixture mode when `HOME` is a sandbox: `bin/code-review` builds it from `REAL_HOME`.
- Every move or delete gets a manifest row before it runs; deletes are staged in `T320/trash/` and purged only on the owner's OK.

## Links
- Code: `~/agents/bin/env.sh`, `~/agents/lib/agent_work.py`, key in `~/agents/config.example.env`
- Tests: `bash ~/agents/bin/tests/no-machine-values.test.sh`, `bash ~/agents/bin/tests/code-review.test.sh`
- Design / results: `~/agent-work/T320/PLAN.md` §1, `~/agent-work/T320/MANIFEST.md`
