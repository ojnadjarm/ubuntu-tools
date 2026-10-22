# Reclaim disk in ~/agent-work: duplicate copies, done tickets' venvs/node_modules, big old traces

Ticket: T1111 · Last verified: 2026-10-21 by bin/tests/pc-disk.test.sh (39/39, 9 mutants red) and a live apply (20,409 → 19,248 MB)

## When to use
~/agent-work (or another fleet scratch root) is large and `pc doctor` names it. Not for /tmp (`pc tmp`), not for
owner data (~/agent-work/owner, ~/agents/backups, ~/Documents, `$PC_DISK_PROTECT`: refused as absolute paths from
any root; a root inside them exits 2), not for game builds (games/*/build is rewritten nightly, refused; other
build/ dirs are listed as "not scanned").

## The path we took
Survey: fdupes/rdfind/jdupes link by content but know nothing of tickets, claims or the ledger; none installed.
Chosen: one Python verb `pc disk` (scan once → plan → apply), blake2b (1 MB head, then full) per same-size group,
one `changes.jsonl` entry per action in pc_apply's shape so `pc undo <id>` works unchanged.
Actions: link (copy → hardlink of the oldest copy, both idle > 24 h), delete (venv with pyvenv.cfg, node_modules,
.godot of a ticket with a history.md done line and no claim, tree idle > 7 d), compress (`zstd -1 --rm`, json/jsonl/log/txt ≥ 200 MB idle > 14 d).

## Exact commands
```bash
pc disk dupes ~/agent-work                  # MB COPIES SAVED_MB FILES, then "N groups, M extra copies, X MB"
pc disk reclaim ~/agent-work                # ACTION PATH MB REASON + skip rows, "would: …"
nice -n 19 ionice -c3 pc disk reclaim ~/agent-work --apply   # last line "rollback: pc undo <id> per action (N ids)"
pc undo <id> --apply                        # link: cp --preserve=all split; compress: zstd -d; delete: prints the recreate command
```
`PC_DISK_MIN_MB` (default 5) lowers the dupe size floor; 0.25 MB found 383 MB linkable vs 107 MB at 5 MB (416 ledger rows).

## Pitfalls (measured)
- Venvs made by uv share hardlinks: T329 and T342 .venv were 211 + 200 MB alone but 211 + 8 MB together; delete
  reclaimed 404 MB of du, not the 600 MB the per-tree sizes add up to. Tree MB now counts each inode once and only
  when every link is inside the tree.
- A failed zstd (CalledProcessError) is caught like OSError: the action shows FAILED, the run goes on, every ledger row gets its verified row.
- Idle = newest file mtime, never a dir mtime: a 10-18 declutter move touched every ticket dir, files were 10-12.
- A dir named `venv` is not always a venv: Blender's bundled python has lib/python3.11/venv (stdlib); only dirs with pyvenv.cfg go.
- 2026-10-21: 486 MB of the dupes (T1032/T1034 3D, written 7–19 h earlier) were < 24 h idle and stayed; re-run after 24 h.
- Re-runs itself: pc-disk-reclaim.timer (user, daily 03:40 +≤ 10 min, Nice 19, idle IO, skips the CI window) runs `pc disk reclaim ~/agent-work --apply`; ledger ids in `pc units log pc-disk-reclaim.service` (T1126).
- Venv deletion writes `<tree>.freeze.txt` (name==version from dist-info) so the recreate hint has a requirements file.

## Links
- Code: ~/agents/bin/pc-disk
- Tests: nice -n 19 bash ~/agents/bin/tests/pc-disk.test.sh
- Design / results: ~/agent-work/research/2026-10-21/T1100/BACKLOG.md §11
