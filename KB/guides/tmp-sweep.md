# Free RAM held in /tmp: sweep leaked test dirs, finished tickets' scratch, old build caches

Ticket: T636 · Last verified: 2026-10-20 by T846 audit (`pc tmp --help`, /tmp tmpfs, maintenance timer Sun 04:00, ledger path); 2026-10-19 by bin/tests/pc-tmp.test.sh (10/10) and a live dry run

## When to use
/tmp is tmpfs (RAM; `free -m` "shared"). Use `pc tmp` when shared memory is high or tests get OOM-killed.
Not for ~/drop, ~/agent-work or anything outside /tmp (refused: exit 2).

## The path we took
Survey: systemd-tmpfiles and tmpreaper sweep by age only; neither knows tickets, claims or open fds. Chosen: one
pc verb (pclib) with three classifiers (test-dir, scratch, build), one /proc fd+cwd scan, one ledger entry per apply.
A scratch dir goes only when its ticket has a `- <date> T<n>` line in history.md, no claims row, and is idle > 6 h.

## Exact commands
```bash
pc tmp              # KIND PATH MB AGE REASON, then "would: delete N paths, X MB"
pc tmp --apply      # deletes, appends ~/agents/log/changes.jsonl, last line "rollback: none, scratch only"
```
maintenance-run calls `pc tmp --apply` each run (weekly, Sun 04:00).

## Pitfalls (measured)
- Idle = newest mtime in the whole tree, not the dir's own mtime (a dir's mtime ignores nested writes).
- Session project dirs start with `-` (`-home-...`): always absolute paths or `--`, else ls/rm parse them as flags.
- 2026-10-19: 1309 MB of done, unclaimed scratch was all < 6 h idle, so the live dry run listed 0 MB; it frees once idle.
- Multi-phase tickets get a history line per phase while still running: the claims row and the 6 h idle gate guard them.

## Links
- Code: ~/agents/bin/pc-tmp, ~/agents/bin/maintenance-run
- Tests: bash ~/agents/bin/tests/pc-tmp.test.sh
