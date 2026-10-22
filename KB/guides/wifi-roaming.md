# Wi-Fi roaming: see the 5 GHz / 2.4 GHz ping-pong, pin a band or BSSID safely

Ticket: T1083, T1091, T1098 · Last verified: 2026-10-21 by bin/tests/pc-net.test.sh (stub nmcli) + live dry runs

## When to use
The laptop hops between the router's 5 GHz and 2.4 GHz BSSIDs (API streams stall, SSH/Tailscale blips).
Read first with `pc net wifi roams`; pin only if T1091's regdom fix did not stop it (≥ 3 ping-pong pairs per 3 d).

## The path we took
- Diagnosis: `pc net wifi roams` parses the wpa_supplicant journal (T1083); regdom pinned by T1091 (`/etc/modprobe.d/90-agents-regdom.conf`, effective after reboot).
- Pin: `pc net wifi pin` sets `802-11-wireless.band` / `.bssid` on the active connection with `nmcli con modify` + `nmcli con up` (user has polkit `settings.modify.system` yes; no sudo).
- Dead-man: before the change, `systemd-run --user --on-active=90s` arms `pc-net-wifi-pin-revert-<band|bssid>.timer`, which runs `pc net wifi pin <kind> auto --con <uuid> --apply` (ledgered). The UUID is baked into the timer and the `pc undo` rollback, so both work while the pin keeps the wifi disconnected (no connected-state lookup). `pin --confirm` cancels it only after the in-use AP matches the pin (active BSSID / frequency in band), a gateway ping and tailscale `BackendState=Running`.
- Not chosen: NetworkManager checkpoints (`CheckpointCreate` with rollback timeout) are the native dead-man, but `checkpoint-rollback` is polkit `auth` for the user, so it would need sudo.

## Exact commands
```bash
pc net wifi roams --since 3d               # ping-pong count first
pc net wifi pin band a                     # dry run: would: / nothing: / refused:
pc net wifi pin band a --apply             # pin 5 GHz; 90 s dead-man armed
pc net wifi pin --confirm                  # within 90 s, from a session that survived the reconnect
pc net wifi pin bssid <bssid> --apply      # one AP; refused unless visible with signal >= 60
pc net wifi pin band auto --apply          # unpin (or: pc undo <id>)
```

## Pitfalls (measured)
- Signal scale is nmcli's 0–100 from the cached scan (`--rescan no`, EF09): on 10-21 the 2.4 GHz BSSID read 100 and the 5 GHz one 79, so a 5 GHz pin passes the ≥ 60 gate but is the weaker link.
- `nmcli con up` drops the link for a few seconds; over SSH confirm from a new session, not the one that ran the pin.
- The router also shows a hidden BSSID on the same channel (empty SSID, mesh backhaul): the BSSID gate only accepts BSSIDs that carry the connection's SSID.
- If `systemd-run` cannot arm the timer, nothing is changed (fixture case).

## Links
- Code: ~/agents/bin/pc-net (`wifi roams`, `wifi pin`)
- Tests: `nice -n 19 bash ~/agents/bin/tests/pc-net.test.sh` (section 5c: stub nmcli, systemd-run, systemctl)
- Design / results: ~/agent-work/research/2026-10-21/T1079/BACKLOG.md (T1083, T1091, T1098)
