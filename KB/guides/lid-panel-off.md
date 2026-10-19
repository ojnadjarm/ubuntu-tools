# Turn the OLED panel off while the lid is closed: `pc lid` and the pc-lid.service policy unit

Ticket: T44 · Last verified: 2026-10-15 by comparing with `KB/runbooks/lid-panel-off.md` and `KB/pc-cli.md`

## When to use
The built-in panel stays lit with the lid closed, or you need the lid, PowerSaveMode, eDP dpms or reassert state.
Not for an external monitor or the TV: mutter drops eDP by itself then.

## The path we took
- `bin/pc-lid` (verb) + `bin/pc_lid.py` (event watcher run by `pc-lid.service`): lid closed and no external monitor → mutter `DisplayConfig.PowerSaveMode = 3`, else `0`.
- Full rule, reassert limit and agent behaviour while dark: `KB/runbooks/lid-panel-off.md`.

## Exact commands
```bash
pc lid                                  # lid=… psm=… edp=… ext=… unit=… reasserts=…
pc lid policy panel-off --apply         # install + enable the unit; prints rollback: pc undo <id>
pc lid policy none --apply              # stop, disable, delete the unit, PowerSaveMode 0
journalctl --user -u pc-lid
```

## Pitfalls (measured)
- gnome-settings-daemon resets PowerSaveMode to 0 on idle-inhibitor, AC or power-profile changes; the unit reasserts, and more than 5 sets in 10 s stops it for that closed period with one notify-owner.

## Links
- Code: `bin/pc-lid`, `bin/pc_lid.py`
- Tests: `bin/tests/pc-lid.test.sh`
- Runbook: `KB/runbooks/lid-panel-off.md`
