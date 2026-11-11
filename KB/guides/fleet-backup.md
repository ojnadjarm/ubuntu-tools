# Back up the laptop to the USB stick, restore it, turn it off (fleet-backup)

Ticket: T1580, T1597, T1603, T1623 · Last verified: 2026-11-11 by bin/tests/fleet-backup.test.sh (36/36) and a stick-only restore

## When to use
Restore a file or the whole fleet state from the USB stick, check the nightly backup, change what it keeps.
Not for git code (pushed repos are their own backup) or protected projects (never backed up).

## The path we took
restic 0.18 (apt): encrypted, deduplicated, zstd; packs are small, so vfat's 4 G file limit, missing symlinks and
chmod never matter. borg and rsync+age were the alternatives (no gain on vfat; rsync+age has no dedup).
`bin/fleet-backup run` (timer `fleet-backup.timer`, 02:30 +20 min, fleet-heavy slice, idle CPU/IO):
locate the stick by `FLEET_BACKUP_LABEL` (config.env) -> repo `<stick>/fleet-backup/restic` -> tier 1 (finance,
invoices, ~/.config/pc-harness, ~/.claude minus projects/ plus every memory/, agent-work history.md, briefs,
decisions, owner, agents/state, `$CLAIMS_SNAP`, newest Moodle dump per env from `$FLEET_BACKUPS_DIR/moodle`
and, as a one-time fallback, the old `~/agents/backups/moodle`; drop that fallback line in `newest_dumps` once the
old folder is gone (T1597)) -> tier 2 (rest of agent-work minus tmp/scratch, and
transcripts), newest first while the raw size stays under 60 % of `FLEET_BACKUP_BUDGET_MB` minus tier 1 ->
`restic backup --tag nightly` -> `forget --keep-daily 7 --keep-weekly 4 --prune` -> `state/fleet-backup/last-ok`
(read by `pc status`: `backup_age`, red after 7 days). Skipped tier-2 paths: `state/fleet-backup/last-skipped.txt`.
Protected projects (`protected entries path|text|container`) are filtered by name before any stat (strace: 0 touches).

## What is on the stick, and who can read it (owner 2026-11-11, T1623)
- On it: finance, invoices, the memory store (private pages too), papers, state, Moodle dumps, transcripts, and
  `fleet-backup/restic-key.txt` (the password) + `README.txt` (the restore command). **Whoever holds the stick reads
  all of it, finance and invoices included**: the owner chose an always-openable stick over encryption he could lose.
- Never on it: keys, tokens, passwords. One list, `never()` in `bin/fleet-backup` (restic patterns: `~/agents/secrets`,
  `private-values`, `~/.claude/.credentials.json`, `daemon/control.key`, `*.env` except `*agent.env`/`*.example.env`,
  `*.pass`, `*.key`, `*.pem`, `*.token`, ssh keys, browser `Cookies`/`Login Data`/`Web Data`), plus this machine's
  files in `state/fleet-backup/never.local` (untracked: 2 transcripts that hold a real password). The run excludes
  them, `--check` fails on any hit in any snapshot, `purge` removes them from old snapshots.
- `config.env` holds passwords, so it is excluded; `state/fleet-backup/config-redacted.txt` (keys kept, credential
  values `<redacted>`) is backed up instead. Dev and test passwords (local Moodle admin/DB, Vass test student) appear
  in many briefs, scripts and transcripts: they stay (listed in the T1623 hand-off), no real account behind them.

## Exact commands
```bash
fleet-backup --check                     # restic, password 600, stick mounted, repo readable
fleet-backup list                        # snapshots
fleet-backup purge                       # plan: never-back-up paths per snapshot (dry run)
fleet-backup purge --apply               # rewrite --forget, read back (count, paths, 0 hits, check), then prune
fleet-backup restore latest ~/finance/x.csv /tmp/r   # lands at /tmp/r$HOME/finance/x.csv
tail ~/agents/state/fleet-backup/run.log # ok / skip / FAIL lines

# New machine: install restic, mount the stick, restore everything with the key on the stick.
sudo apt install restic
cd "/media/<user>/<stick-label>/fleet-backup"
restic -r restic --password-file restic-key.txt snapshots
restic -r restic --password-file restic-key.txt restore latest --target ~/restore   # then copy by hand
# Keys and tokens are not in it: make new ones (Discord bot, ntfy, OpenRouter, Spotify, Salesforce, Claude login).

# Turn it off / on
pc units disable fleet-backup.timer --user --apply       # rollback: the pc undo id it prints
pc units enable fleet-backup.timer --user --now --apply
```
The password lives in `~/agents/secrets/fleet-backup.pass` (600, never printed) and on the stick as
`fleet-backup/restic-key.txt` (T1623); `run` re-creates the stick copy and README when missing.

## Pitfalls (measured)
- Stick absent = `skip: stick absent` in run.log, exit 0: the unit never fails for it; `backup_age` grows instead.
- A session started before `FLEET_BACKUP_LABEL` was added still had `HARNESS_ENV_LOADED=1`: the first real run
  skipped as "absent" (label ''). fleet-backup now always sources env.sh.
- `forget` must group by tag: the default host+paths grouping makes every night its own group (tier 2 paths change),
  so nothing would ever be pruned.
- Fixture loop devices: `$(stick …)` ran in a subshell and leaked the loop device; udisks `loop-delete` is refused
  without a TTY (polkit), the test falls back to `sudo -n losetup -d`.
- First real run (2026-11-10, idle priority under strace, load 5-12): 22 min 40 s; tier 1 810 MB, tier 2 10249 MB raw
  chosen, 19429 MB in 361 entries skipped, repo 5585 MB on the stick (zstd + dedup ~2x); vfat write ~6 MB/s.
- `~/agent-work/claims-snap/` holds copies of protected repos' files (`files/<home>/moodle-envs/<project>/…`): the
  first run backed them up (strace caught it). Mirrors of every protected path are now excluded anywhere
  (`--exclude=**/<path under home>`), and sizes come from a scandir walker, because du and find stat what they skip.
- `protected entries path` runs `readlink -m`, which stats the protected paths (strace: 2 statx on run 2); fleet-backup
  expands the config words lexically instead.
- `! a | grep -q x` under `set -o pipefail` passes when it should fail (grep -q closes the pipe, `a` gets SIGPIPE):
  the strace assertion counts with `grep -c` instead; a negative control (old code) now fails it.
- restic picks the parent snapshot by host+paths: tier 2 paths shift, so run 2 had no parent and re-read 11 G
  (21 min). `--group-by host,tags` makes the last nightly the parent.
- T1597: work material moved out of `~/agents` (`FLEET_BACKUPS_DIR`, `CLAIMS_SNAP`, `TOOLSMITH_PAPERS`, `DASH_PLANS_DIR`
  in env.sh / lib/agent_work.py). Both dirs are skipped as tier-2 candidates (backups would eat the budget; claims
  snapshots are tier 1). A fixture test that inherits the session's `AGENT_WORK` writes into the real dirs: tests
  set a fake `AGENT_WORK` too (moodle-keep and work-repo-guard tests leaked 2 dumps + 1 file before that).
- T1603: more material left `~/agents` (`LIAISON_PAPERS`, `BENCH_PAPERS`, `PO_PAPERS`, `ASR_CORPUS` under `owner/` = tier 1,
  `IMPROVE_PAPERS`, `CODE_REVIEW_PAPERS`, `GAMEDEV_PERF_DIR`). `$LIAISON_PAPERS/jobs` is one tier-2 entry per job (one
  job folder is 9.7 G of rebuildable `target/`: it skips alone instead of taking the whole 14 G folder with it);
  gamedev-perf left tier 1 (`agents/state`) for tier 2.
- T1623: `restic ls` and `rewrite` print a `snapshot … of [<paths>]` header holding the backup's source paths, which
  still name an excluded source (e.g. `.credentials.json`): count hits on lines that start with `/`, or by `rewrite
  --dry-run -v` `excluding` lines (that is what `--check` does: restic's own matcher, so it agrees with the run).
- T1623: `restic find` counts every node (children of an excluded dir too, and it has no `!` re-include); `rewrite`
  counts top-level excluded entries. The first real dry run: 39 entries / 131 find hits over 3 snapshots.
- T1623: a scan for real secret values found the Salesforce password in 2 transcripts (now in `never.local`) and the
  Claude OAuth token only in `.credentials.json`; card-number scan (Luhn + IIN): 0 real cards, 680 numeric look-alikes.
- The single-file restore lands under the full path: `restore latest <abs path> /tmp/r` gives `/tmp/r<abs path>`.

## Links
- Code: ~/agents/bin/fleet-backup, ~/agents/units/fleet-backup.{service,timer}, `backup_age` in ~/agents/bin/pc-status
- Tests: `~/agents/bin/tests/fleet-backup.test.sh` (fake HOME, loopback vfat sticks via udisksctl; ~15 s)
- Design: ~/agent-work/research/2026-11-10/T1580/ARCH.md
