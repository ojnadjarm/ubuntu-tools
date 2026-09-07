# Runbook: the laptop travels (battery, new WiFi, power profile)

## What changes on battery
- A udev rule (`/etc/udev/rules.d/99-agents-power-profile.rules`) runs
  `/usr/local/sbin/power-profile-auto` on every AC plug/unplug: `performance` on AC,
  `balanced` on battery. Check with `powerprofilesctl get`; force with
  `sudo systemctl start power-profile-auto.service`.
- Agents keep working on battery, just slower. The sentinel alerts below 20 % (T05).
- Charging stops at 80 % (`/sys/class/power_supply/BAT0/charge_control_end_threshold`,
  persisted by `/etc/udev/rules.d/99-agents-battery-threshold.rules`). For a long trip on
  battery, allow a full charge for one cycle:
  `echo 100 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold`
  (the rule restores 80 on the next boot).
- Never suspend/lid-close changes are in place (T02); the machine stays reachable while closed.

## Joining a new WiFi
See `new-wifi.md`. Short form: `nmcli dev wifi list --rescan yes` then
`nmcli dev wifi connect "<SSID>" password "<PASSWORD>"`.

## After any network change
1. `pc status --brief` — `wifi=`, `ts=up`, `FAIL=none`.
2. `tailscale status` must list the owner's own device as a peer; `tailscale ping <peer>` should pong.
3. The Tailscale IP (`KB/machine.md`) never changes — always give the owner Tailscale URLs.
4. WiFi power save must stay off: `iw dev wlo1 get power_save` → `Power save: off`.
   NetworkManager applies it from `/etc/NetworkManager/conf.d/zz-agents-wifi-powersave-off.conf`
   at connection activation; to fix it live without dropping the link:
   `sudo iw dev wlo1 set power_save off`.

## Rollback (T21)
Delete the two udev rules and the NM drop-in, `sudo udevadm control --reload-rules`,
`echo 100 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold`,
`sudo systemctl disable --now power-profile-auto.service`, `powerprofilesctl set balanced`.
