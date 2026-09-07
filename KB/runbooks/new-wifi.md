# Runbook: connect to a new WiFi network

1. Scan: `nmcli dev wifi list --rescan yes`
2. Connect: `nmcli dev wifi connect "<SSID>" password "<PASSWORD>"`
   Hidden network: add `hidden yes`. Enterprise: use `nmcli con add type wifi ...` instead.
3. Verify: `pc status --brief` (field `wifi=`) and `ping -c1 1.1.1.1`.
4. Tailscale should reconnect by itself: `tailscale status --peers=false --json | jq -r .BackendState` = `Running`.
   If not: `sudo tailscale up`.
5. Make it stick on boot: `nmcli con mod "<SSID>" connection.autoconnect yes`.
6. The LAN IP changes with the network; the Tailscale IP (`KB/machine.md`) does not — always give the
   owner Tailscale URLs. Regenerate facts: `pc status --facts > ~/agents/KB/machine.md`.
