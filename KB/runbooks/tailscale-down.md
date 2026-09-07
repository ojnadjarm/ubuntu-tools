# Runbook: Tailscale is down (pc status shows ts= not up)

1. State: `tailscale status --peers=false --json | jq -r .BackendState` (`Running` / `Stopped` / `NeedsLogin`).
2. `Stopped`: `sudo tailscale up` — should return immediately.
3. Daemon dead: `sudo systemctl restart tailscaled && sleep 3 && tailscale status`.
4. `NeedsLogin` (key expired): `sudo tailscale up` prints an auth URL. The agent cannot click it —
   `notify-owner -p urgent -t "tailscale" "auth needed: <url>"` and stop.
5. Never run `tailscale down` / `logout`: it is the owner's remote path in. LAN SSH
   (`$HARNESS_LAN_IP`) is the only fallback, and only from the same WiFi.
6. Verify: `pc status --check` exit 0 and `tailscale ip -4` returns the node IP in `KB/machine.md`.
