# Report the size of a directory tree

Ticket: T09 · Last verified: 2026-08-20 by `bin/tests/disk-report.test.sh`

## When to use
The digest needs the size of a folder. Not for per-file listings (use `log-size`).

## The path we took
`bin/disk-report <dir>` walks the tree (symlinks skipped) and prints `<dir>\t<size>`.
It gives up after a 5 s timeout on slow disks and prints `timeout`.

## Exact commands
```bash
disk-report ~/agents/log
disk-report --json ~/agents/log     # {"path": ..., "bytes": ...} for the dashboard
```

## Links
- Code: `bin/disk-report` · Tests: `bin/tests/disk-report.test.sh`
