`pc power` caches `powerprofilesctl get` for 60 s, so a `pc undo` replay inside that window
reads a stale "before" and no-ops. `check.sh` exports `FRESH=1` around the undo so the whole
chain re-reads. Worth fixing in `pc-power` (out of PB05's scope); until then any undo of a
power mutation needs `FRESH=1`.
