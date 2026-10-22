# Restart services running on replaced libraries after an upgrade (needrestart, pc stale)

Ticket: T1066 · Last verified: 2026-10-21 by `pc stale --apply` (5 restarted, 5 ledger rows verified, NEEDRESTART-SVC 7 → 1) and bin/tests/pc-stale.test.sh (14 ok)

## When to use
After unattended-upgrades or a maintenance full-upgrade, when `needrestart` lists services on stale libraries. Not for the kernel or the user manager: those clear only at the Sunday reboot (agent@maintenance).

## The path we took
No verb read needrestart, so `pc stale` is new; it restarts through `pc units restart --system --apply` (T1059: sudo -n, ledgered, guarded) instead of its own systemctl.
- read: `sudo -n nice -n 19 needrestart -b -r l` (batch, list only, never restarts by itself), NEEDRESTART-SVC lines
- classify: held = network (NetworkManager, wpa_supplicant, networkd, resolved), access (ssh*, tailscaled, polkit, logind, dbus, user@*), session (gdm, gnome-*), fleet (docker*, containerd, dark-eye*, sentinel*, agent@*, orchestrator), not ours (PC_NOT_OURS, Vass), bluetooth with a connected device; everything else restart
- apply: one `pc units restart` per safe unit, then re-read needrestart; exit 1 when a restarted unit is still stale

## Exact commands
```bash
pc stale                 # restart/held lines + would:
pc stale --apply         # ledgered restarts, then "after: N stale"
nice -n 19 bash ~/agents/bin/tests/pc-stale.test.sh
```

## Pitfalls (measured)
- Before T1059, `pc units restart` on a system unit hung 25 s on polkit and failed; `pc stale --apply` needs the sudo -n path (5 restarts took 4.9 s on 2026-10-21).
- Always pass `-r l` (list only) so needrestart never restarts on its own; a scan took 1.45 s (2026-10-21), the 50 s sudo timeout is headroom for a loaded box.
- Restarting bluetooth drops the owner's buds: held whenever `bluetoothctl devices Connected` lists a device (0 connected on 2026-10-21).
- NetworkManager stays held: a restart drops wifi and the tailnet for every remote session; the Sunday 04:00 reboot clears it.
- `unattended-upgrades.service` is only the shutdown waiter; restarting it does not stop a running upgrade, but check `pgrep -a apt` first.

## Links
- Code: ~/agents/bin/pc-stale (restarts via ~/agents/bin/pc-units)
- Tests: ~/agents/bin/tests/pc-stale.test.sh (PC_FIXTURE stubs; no sudo, no real unit)
- Design / results: ~/agent-work/research/2026-10-21/T1058/BACKLOG.md §8
