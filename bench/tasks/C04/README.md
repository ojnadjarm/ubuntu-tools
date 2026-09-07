`pcbench-idle` is a real user unit file (`~/.config/systemd/user/pcbench-idle.service`), not
`systemd-run --user --unit …` as the ticket sketched: a transient unit is garbage-collected
when it stops, so the ledger's rollback (`pc units start pcbench-idle --user --apply`) would
fail and the undo half of the task could never pass. `teardown.sh` stops it, removes the file
and reloads, so nothing survives. S05 shares this setup and teardown verbatim.
