# lid — panel off while the lid is closed (`pc lid`, T44)

The built-in panel is an OLED (Samsung ATNA56YX03). With no other monitor, mutter keeps it as the
only output when the lid closes, so it stays lit (power, heat, burn-in). `pc-lid.service` fixes that.

- **Rule:** lid closed and no external monitor → mutter `DisplayConfig.PowerSaveMode = 3` (CRTC off,
  panel unpowered). Lid open, or an external monitor present → `0`. With the TV connected, mutter
  drops eDP by itself and the unit never touches `PowerSaveMode`, so the TV stays on.
- **Reassert:** gnome-settings-daemon resets it to `0` on idle-inhibitor, AC or power-profile changes;
  the unit sets `3` again on the `PropertiesChanged` signal. More than 5 sets in 10 s → it stops for
  that closed period and sends one `notify-owner`.
- **Events, no polling:** UPower `LidIsClosed` (system bus, the source mutter reads) + DisplayConfig
  `PropertiesChanged`/`MonitorsChanged` (session bus). Idle: ~28 MB RSS, 0 CPU ticks and 0 context
  switches in 60 s.
- **Agents keep working while dark:** mutter still composites (dummy flips every 100 ms). Verified
  2026-09-22 with the lid open and `PowerSaveMode=3`: `dpms Off`, a `pc shot` taken while dark shows
  text typed while dark, `pc tree`, `pc win list`, `pc see`, an AT-SPI action and a Playwright
  snapshot all answer.
- **Lid open with psm 3 left over** (e.g. after a crash) → the unit sets `0`. `ExecStopPost` also
  sets `0` whenever the unit stops.

## Commands

| | |
|---|---|
| status | `pc lid` → `lid=closed psm=3 edp=Off ext=no unit=active reasserts=0` (`--json` too) |
| enable | `pc lid policy panel-off --apply` → writes `~/.config/systemd/user/pc-lid.service`, `enable --now`, prints `rollback: pc undo <id>` |
| disable | `pc undo <id> --apply`, or `pc lid policy none --apply` → stop, disable, delete the unit, `PowerSaveMode 0` |
| code | `~/agents/bin/pc-lid` (verb), `~/agents/bin/pc_lid.py` (watcher), tests `bin/tests/pc-lid.test.sh` |
| journal | `journalctl --user -u pc-lid` |
| guard | `PowerSaveMode` is on the `pclib.sh` guard list: `pc dbus set … PowerSaveMode` exits 3; `pc lid` is the only writer |

## Panel stuck dark

`busctl --user set-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig org.gnome.Mutter.DisplayConfig PowerSaveMode i 0`
(over ssh/tailnet works: it is the user session bus). Then `pc lid` and `cat /sys/class/drm/card1-eDP-1/dpms` → `On`.

## Not yet verified live

A real lid close (needs the owner), and whether the EC also cuts the panel by itself. Test: close
the lid → from the phone/ssh `pc lid` reads `lid=closed psm=3 edp=Off`, no light at the seam → open
the lid → `psm=0 edp=On`, desktop unchanged, session unlocked.
