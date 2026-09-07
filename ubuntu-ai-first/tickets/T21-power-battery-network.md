# T21 — Power, battery health and WiFi for a 24/7 laptop

**Phase 4 · must · Model: opus · Estimated agent time: 45 min**

## Goal
The laptop runs at full speed on AC, degrades gracefully on battery, stops cooking its battery (already 72 % health while plugged 24/7), and never drops SSH/Tailscale because of WiFi power saving.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- ASUS Vivobook X1503ZA; `intel_pstate`, governor `powersave`, `powerprofilesctl` = `balanced`, `thermald` running. Battery BAT0: 50.6/70.0 Wh design (72 %). ASUS exposes `/sys/class/power_supply/BAT0/charge_control_end_threshold` (verify); setting it to 80 is the standard fix.
- WiFi `wlo1` (mt7921), `/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf` sets `wifi.powersave = 3`.
- The laptop travels: on battery the agents should keep working, just slower; sentinel already alerts at < 20 % (T05).

## Steps
1. Battery: `echo 80 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold`; persist with a udev rule or a small oneshot `battery-threshold.service` (etckeeper). Report the current value in `pc status`.
2. WiFi: `/etc/NetworkManager/conf.d/99-agents-wifi-powersave-off.conf` with `wifi.powersave = 2`; `sudo systemctl reload NetworkManager`; confirm `iw dev wlo1 get power_save` → off. Also `nmcli con mod "<ssid>" connection.autoconnect-priority 10` for the home network.
3. Power profile: udev rule on `power_supply` change → `powerprofilesctl set performance` on AC, `balanced` on battery (script `~/agents/bin/power-profile-auto` invoked via a root-owned `/usr/local/sbin` copy; udev cannot run user scripts). Set performance now.
4. Add a KB runbook `travel.md`: what changes on battery, how to join a new WiFi (`nmcli dev wifi connect`), how to check Tailscale after a network change.

## Success check
```bash
cat /sys/class/power_supply/BAT0/charge_control_end_threshold   # 80
iw dev wlo1 get power_save                                       # Power save: off
powerprofilesctl get                                             # performance (on AC)
sudo udevadm test /sys/class/power_supply/AC0 2>&1 | grep -c power-profile-auto   # >= 1
pc status | grep -iE "battery|profile"                           # shows threshold and profile
```

## Rollback
Remove the udev rules/service/NM drop-in (etckeeper revert); `echo 100 > charge_control_end_threshold`; `powerprofilesctl set balanced`.
