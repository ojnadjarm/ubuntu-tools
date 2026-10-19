# File claims: declare, release and expire rows on the parallel-agent board

Ticket: T378, T415 · Last verified: 2026-10-19 by bin/tests/claims.test.py (21/21) and `pc doctor --quick` claims row

## When to use
Any agent about to edit files while other agents run: claim first, release when done. Not for owner to-dos (`owner-todo`) or pushes (`pc need`).

## The path we took
Existing: a hand-edited `~/agents/FILE-CLAIMS.md` plus an unused `FILE-CLAIMS.md.lock`, read by the dashboard (`dashboard/dash/services/agents.py`, lines starting `- `) and required in briefs by `brief-lint`.
Chosen: one small CLI `bin/claims` over the same file and format, so the dashboard and old rows keep working; every write is a read-modify-write under `flock` on the lock and an atomic rename.
Stale = unpinned and older than 48 h (`CLAIMS_STALE_H`, floor 24 h). A bare date counts as the end of that day, so a row is never aged older than it can be. `pin` / `do not move` rows never go stale; undatable rows never expire.
`add` refuses (exit 3, one `overlap: <ticket> <path>` line each on stderr) a path equal to, inside or a parent of a live (non-stale) row of another ticket; `--force` adds anyway. Paths split on commas/spaces, `{a,b}` expands, a glob counts as its directory.

## Exact commands
```bash
claims list                          # every row: ok | STALE | PIN, age in hours
claims add T<nn> "bin/x, KB/guides/x.md"   # exit 3 on overlap; --force to add anyway
claims done T<nn>
claims expire                        # dry run: would drop: …
claims expire --apply                # drops stale rows, prints each dropped line
claims check                         # "N claims, M stale (…), P pinned"; exit 2 when stale (pc doctor WARN)
```

## Pitfalls (measured)
- Before T378 the board had 2 stale rows (T64 at 25 d, T322 at 7 d); T322 is an owner `do not move` row, so it is pinned, not stale: 1 expired, stale 2 → 0.
- Hand edits race the CLI: the lock only protects writers that take it.
- T415: the live board mixes comma lists, space lists, `{a,b}` braces and globs (`TSP-04[2-5].md`); a glob is cut to its directory, so it over-reports rather than misses.
- Dates without a time: a row dated yesterday is 0-24 h old, never more; expiry needs > 48 h past the end of the day.

## Links
- Code: ~/agents/bin/claims; doctor row in ~/agents/bin/pc-doctor (`check claims`)
- Tests: `python3 ~/agents/bin/tests/claims.test.py` (fixture board via CLAIMS_FILE; asserts the real board is untouched)
- Design: ~/agent-work/research/2026-10-18/night/T373/IMPROVE.md item 7; skill /claims
