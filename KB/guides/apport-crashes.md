# Clear a stuck apport crash so apport-autoreport.service stops failing

Ticket: T490, T571 · Last verified: 2026-10-20 by T846 audit (`pc crashes --help`, unit read-back inactive/success, `PathChanged=/var/crash`, paths); 2026-10-19 by `bin/tests/pc-crashes.test.sh` (21 ok), two real archives (unit failed → inactive/success) and a fixture `check_ignored()` (T571)

## When to use
`pc failures` / `pc status` shows `apport-autoreport.service` failed, or `/var/crash` holds a `.crash` with `.upload` but no `.uploaded`. Not for debugging the crash itself (read the `.crash` with `gdb` first, before archiving; `apport-retrace` is not installed, apt package `apport-retrace`).

## The path we took
Existing: `apport-cli`/`whoopsie-upload-all` (upload only), `pc units reset-failed` (unit only). Chosen: one verb `pc crashes` on `pclib.sh` that lists the reports and archives one set as a ledgered move plus `reset-failed`, so `pc undo` puts it back. Why: the failing unit re-fires on every `/var/crash` change (`apport-autoreport.path` = `PathChanged=/var/crash`), so only removing the queued set ends the loop.

## Exact commands
```bash
pc crashes                       # name, exe, signal, age, upload state, cmdline head
pc crashes --json
pc crashes archive <name>        # would: crash:<name> present → archived
pc crashes archive <name> --apply   # moves to ~/agents/backups/crash/<stamp>-<name>/, resets the unit
systemctl show apport-autoreport.service -p ActiveState,Result   # read-back
```

## Pitfalls (measured)
- Root cause on this box: whoopsie's upload fails with `SSL connect error` (2026-10-19), so no `.uploaded` is ever written and `whoopsie-upload-all --timeout 20` exits 2 for every queued crash.
- Archiving one set changes `/var/crash`, which re-runs the unit at once; it then re-collects any other `.crash` (40 MB localsearch: 39 s, 449 MB peak), deletes its `.uploaded` and fails again on it. Archive every `queued` report, then read the unit back.
- The `.uploaded` file is `whoopsie`-owned in a sticky dir: the move falls back to `sudo -n mv`.
- A program that crashes on a known upstream bug: ignore it instead of archiving each dump. `python3 -I -c "import apport.report as a; r=a.Report(); r['ExecutablePath']='<exe>'; r.mark_ignore()"` writes `~/.apport-ignore.xml` with the binary's mtime (a package upgrade re-enables it); `check_ignored()` on the same Report proves it, and `APPORT_IGNORE_FILE=<fixture>` keeps a dry check off the real file. `pc crashes` lists it as `ignored-by-apport` with its kernel trap count (T571).

## Links
- Code: `~/agents/bin/pc-crashes`
- Tests: `bash ~/agents/bin/tests/pc-crashes.test.sh` (temp crash dir, stub systemctl/sudo, temp ledger)
- Design: `~/agent-work/research/2026-10-19/T490/architecture.md`
