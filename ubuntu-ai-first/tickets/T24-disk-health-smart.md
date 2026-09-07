# T24 — Disk and battery health monitoring (SMART)

**Phase 4 · nice · Model: opus · Estimated agent time: 30 min**

## Goal
Early warning for NVMe wear/failure and battery degradation, visible in `pc status` and in the daily digest.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- `smartctl` not installed. NVMe `SSDPEKNU512GZ` (Intel 670p). Battery health 72 % (T21 sets an 80 % charge cap). `pc status --json` (T05) and sentinel digest (T17) are the consumers.

## Steps
1. `sudo apt install -y smartmontools`; `smartctl -H /dev/nvme0` and `smartctl -A /dev/nvme0` (percentage used, available spare, media errors). Enable `smartd` with a minimal `/etc/smartd.conf` line (`DEVICESCAN -H -l error -l selftest -m root -M exec /usr/local/sbin/smart-alert`) where `smart-alert` calls `notify-owner -p urgent` (root can read the ntfy env via a root-only copy in `/etc/agents/ntfy.env`).
2. Add to `pc status`: `disk.smart` (PASSED/FAILED, percent used, spare) and `battery.health` (energy-full/design, cycle count if exposed). Thresholds for `--check`: SMART not PASSED, percent used > 90, spare < 20.
3. Digest (T17) includes both once a day.

## Success check
```bash
sudo smartctl -H /dev/nvme0 | grep -i result        # PASSED
systemctl is-active smartd                          # active
pc status --json | python3 -c "import json,sys;d=json.load(sys.stdin)['sections'];print(d['disk']['smart']['value'],d['power']['battery_health']['value'])"
```

## Rollback
`sudo apt remove smartmontools`; remove the fields from `pc-status`.
