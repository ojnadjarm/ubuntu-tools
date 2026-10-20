# File claims: declare, release and expire rows on the parallel-agent board

Ticket: T378, T415, T946 · Last verified: 2026-10-20 (T946) by `claims --help`, code read and a live `claims diff T946`; test 2026-10-20 bin/tests/claims.test.py (52/52)

## When to use
Any agent about to edit files while other agents run: claim first, release when done. Not for owner to-dos (`owner-todo`) or pushes (`pc need`).

## The path we took
Existing: a hand-edited `~/agents/FILE-CLAIMS.md` plus an unused `FILE-CLAIMS.md.lock`, read by the dashboard (`dashboard/dash/services/agents.py`, lines starting `- `) and required in briefs by `brief-lint`.
Chosen: one small CLI `bin/claims` over the same file and format, so the dashboard and old rows keep working; every write is a read-modify-write under `flock` on the lock and an atomic rename.
Stale = unpinned and older than 48 h (`CLAIMS_STALE_H`, floor 24 h). A bare date counts as the end of that day, so a row is never aged older than it can be. `pin` / `do not move` rows never go stale; undatable rows never expire.
`add` also snapshots each claimed path into `~/agents/state/claims-snap/<T>/` (`CLAIMS_SNAP`): `manifest.tsv` rows `<sha256|absent|dir|skipped>\t<path>` plus copies under `files/`. Dirs copy their files ≤ 1 MB each, ≤ 200 files and ≤ 5 MB per ticket (over a cap: `claims: snapshot skipped <path> (<cap>)` on stderr); paths under `secrets/` or `backups/` are never copied; an unreadable file is `skipped` with its error, never a crash. Relative paths resolve under the board's dir (~/agents), never the cwd; an absent relative path warns on stderr. A later add snapshots only paths the manifest does not hold yet, so the first baseline wins. `done` keeps the snapshot 7 days (verifiers run after done); the next `add` prunes older ones.
`add` refuses (exit 3, one `overlap: <ticket> <path>` line each on stderr) a path equal to, inside or a parent of a live (non-stale) row of another ticket; `--force` adds anyway. Paths split on commas/spaces, `{a,b}` expands, a glob counts as its directory.

## Exact commands
```bash
claims list                          # every row: ok | STALE | PIN, age in hours
claims add T<nn> "bin/x, KB/guides/x.md"   # exit 3 on overlap; --force to add anyway; --pin = never stale (owner rows)
claims done T<nn>
claims expire                        # dry run: would drop: …
claims expire --apply                # drops stale rows, prints each dropped line
claims check                         # "N claims, M stale (…), P pinned"; exit 2 when stale (pc doctor WARN)
claims check <paths>                 # free/held per path; exit 1 when any is held
claims diff T<nn>                    # builders and verifiers: unified diff of only this ticket's claimed paths, snapshot at add vs now; new files vs /dev/null; `untouched` when equal
claims diff T<nn> --stat             # one `path | +N -M` line per file, then `N file(s) changed, +A -D`; `no baseline: <path>` first for each claimed path without a snapshot
```

## Pitfalls (measured)
- Before T378 the board had 2 stale rows (T64 at 25 d, T322 at 7 d); T322 is an owner `do not move` row, so it is pinned, not stale: 1 expired, stale 2 → 0.
- Hand edits race the CLI: the lock only protects writers that take it.
- T415: the live board mixes comma lists, space lists, `{a,b}` braces and globs (`TSP-04[2-5].md`); a glob is cut to its directory, so it over-reports rather than misses.
- Dates without a time: a row dated yesterday is 0-24 h old, never more; expiry needs > 48 h past the end of the day.

- T946: 9 of 20 wave 22 verifiers could not isolate a ticket's diff (~/agents had 230 modified + 106 untracked files and agents may not commit), so `git diff` mixes tickets; `claims diff` is the per-ticket baseline. Paths claimed before T946 have no snapshot; `diff` lists each as `no baseline: <path>`, so read those with `git diff` (T944: run.sh, run-sh.test.sh).
- T946 verify: `claims add T1 bin/x` from another cwd used to snapshot `<cwd>/bin/x` and `diff` said `untouched` after a real edit; a chmod 000 file under a claimed dir crashed `add` after the board write, leaving no manifest.

## Links
- Code: ~/agents/bin/claims; doctor row in ~/agents/bin/pc-doctor (`check claims`)
- Tests: `python3 ~/agents/bin/tests/claims.test.py` (fixture board via CLAIMS_FILE; asserts the real board is untouched)
- Design: ~/agent-work/research/2026-10-18/night/T373/IMPROVE.md item 7; skill /claims
