# T23 — Updates and the reboot policy (weekly maintenance agent)

**Phase 4 · should · Model: opus · Estimated agent time: 60 min**

## Goal
Security updates apply automatically without surprise reboots; a weekly maintenance agent applies the rest, and reboots only inside the agreed window after verifying everything will come back (T03) and telling the owner.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- `unattended-upgrades` enabled with defaults (security pocket, no auto-reboot). Kernel 7.0.0-31; GRUB `GRUB_TIMEOUT=0` hidden. Snap auto-refresh on (Firefox, snap-store).
- Owner answer to PLAN §7 Q4 sets the window; default 04:00–05:00 Europe/Madrid, push before, only when `pc status --check` is OK and no `agent@*` unit is active. The first reboot is also the real test of T03; do it in this ticket only if the owner approved the window.
- Needs `agent-run` (T15), `notify-owner`, `boot-check.sh` (T03).

## Steps
1. `/etc/apt/apt.conf.d/52-agents-unattended`: keep security-only, `Automatic-Reboot "false"`, `Remove-Unused-Dependencies "true"`, mail off. `sudo unattended-upgrades --dry-run --debug | tail -5` must pass. Snap: `sudo snap set system refresh.timer=04:00-05:00`.
2. `~/agents/bin/maintenance-run` (bash): `apt update && apt full-upgrade -y` (docker packages held back unless `--with-docker`), `apt autoremove -y`, `/var/run/reboot-required` check, `needrestart -b` for services, docker image prune, write a summary. Exit 3 when a reboot is required.
3. `~/agents/maintenance/BRIEF.md` + `agent-enable maintenance "Sun *-*-* 04:00"`: run `maintenance-run`; if exit 3 and the window rule holds (`date`, `pc status --check`, no agents active), push "rebooting moodle-lab in 5 min (kernel update)", `sudo shutdown -r +5`; else report "reboot pending, window missed" and push once. After reboot the sentinel (T17) verifies and the digest reports.
4. GRUB safety: set `GRUB_RECORDFAIL_TIMEOUT=5` and `GRUB_TIMEOUT=2` (hidden style kept) so a failed boot never waits forever at the menu; `update-grub`; etckeeper.
5. KB runbook `reboot.md` updated with the sequence: check → push → shutdown -r → sentinel confirms.

## Success check
```bash
grep -h "Automatic-Reboot" /etc/apt/apt.conf.d/52-agents-unattended    # "false"
sudo unattended-upgrades --dry-run 2>&1 | tail -2
~/agents/bin/maintenance-run --dry-run; echo exit=$?
agents-status | grep maintenance                                         # Sun 04:00
grep -E "GRUB_TIMEOUT|RECORDFAIL" /etc/default/grub
```
If the owner approved: schedule `sudo shutdown -r +2` at night, then next morning `~/agents/bin/boot-check.sh` and `agents-status` show everything back (paste in the report). Otherwise mark "reboot test pending owner".

## Rollback
Remove the apt drop-in, disable the maintenance timer, restore `/etc/default/grub` from etckeeper and `update-grub`.
