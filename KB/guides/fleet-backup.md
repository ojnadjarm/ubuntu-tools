# Back up the laptop to the USB stick, restore it, turn it off (fleet-backup)

Ticket: T1580, T1597 · Last verified: 2026-11-10 by bin/tests/fleet-backup.test.sh (23/23) and one real run + restore

## When to use
Restore a file or the whole fleet state from the USB stick, check the nightly backup, change what it keeps.
Not for git code (pushed repos are their own backup) or protected projects (never backed up).

## The path we took
restic 0.18 (apt): encrypted, deduplicated, zstd; packs are small, so vfat's 4 G file limit, missing symlinks and
chmod never matter. borg and rsync+age were the alternatives (no gain on vfat; rsync+age has no dedup).
`bin/fleet-backup run` (timer `fleet-backup.timer`, 02:30 +20 min, fleet-heavy slice, idle CPU/IO):
locate the stick by `FLEET_BACKUP_LABEL` (config.env) -> repo `<stick>/fleet-backup/restic` -> tier 1 (finance,
invoices, secrets, ~/.config/pc-harness, ~/.claude minus projects/ plus every memory/, agent-work history.md, briefs,
decisions, owner, agents/state, `$CLAIMS_SNAP`, newest Moodle dump per env from `$FLEET_BACKUPS_DIR/moodle`
and, as a one-time fallback, the old `~/agents/backups/moodle`; drop that fallback line in `newest_dumps` once the
old folder is gone (T1597)) -> tier 2 (rest of agent-work minus tmp/scratch, and
transcripts), newest first while the raw size stays under 60 % of `FLEET_BACKUP_BUDGET_MB` minus tier 1 ->
`restic backup --tag nightly` -> `forget --keep-daily 7 --keep-weekly 4 --prune` -> `state/fleet-backup/last-ok`
(read by `pc status`: `backup_age`, red after 7 days). Skipped tier-2 paths: `state/fleet-backup/last-skipped.txt`.
Protected projects (`protected entries path|text|container`) are filtered by name before any stat (strace: 0 touches).

## Exact commands
```bash
fleet-backup --check                     # restic, password 600, stick mounted, repo readable
fleet-backup list                        # snapshots
fleet-backup restore latest ~/finance/x.csv /tmp/r   # lands at /tmp/r$HOME/finance/x.csv
tail ~/agents/state/fleet-backup/run.log # ok / skip / FAIL lines

# New machine: install restic, mount the stick, put the password file back, restore everything.
sudo apt install restic
export RESTIC_REPOSITORY="/media/<user>/<stick-label>/fleet-backup/restic" RESTIC_PASSWORD_FILE=~/fleet-backup.pass
restic snapshots && restic restore latest --target /    # or --target ~/restore and copy by hand

# Turn it off / on
pc units disable fleet-backup.timer --user --apply       # rollback: the pc undo id it prints
pc units enable fleet-backup.timer --user --now --apply
```
The password lives only in `~/agents/secrets/fleet-backup.pass` (600, never printed) plus the owner's own off-laptop
copy (owner-todo, T1580). Lose both and the stick is unreadable.

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
- The single-file restore lands under the full path: `restore latest <abs path> /tmp/r` gives `/tmp/r<abs path>`.

## Links
- Code: ~/agents/bin/fleet-backup, ~/agents/units/fleet-backup.{service,timer}, `backup_age` in ~/agents/bin/pc-status
- Tests: `~/agents/bin/tests/fleet-backup.test.sh` (fake HOME, loopback vfat sticks via udisksctl; ~15 s)
- Design: ~/agent-work/research/2026-11-10/T1580/ARCH.md
