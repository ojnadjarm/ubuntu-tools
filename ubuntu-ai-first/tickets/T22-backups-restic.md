# T22 — Backups with restic (agent state, harness, Moodle code and DB dumps)

**Phase 4 · must · Model: opus · Estimated agent time: 75 min**

## Goal
A daily, verified, deduplicated backup of everything agents and the owner would miss (`~/.claude`, `~/agents`, `~/moodle-envs/*/www`, DB dumps, `/etc` git), restorable with one command, optionally mirrored off-machine.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- DB dumps from T18 in `~/agents/backups/moodle/`. `/etc` is in git (T01). Disk: 416 GB free; `www` checkouts are ~1 GB each.
- Owner answer to PLAN §7 Q3 decides the off-machine part: default = local repo only + optional rclone to Google Drive (Gmail/Drive are the owner's Google account; `rclone config` needs an interactive OAuth step the owner must do once, or use the Drive MCP only for reports — do not try to script the OAuth).
- Secrets dir `~/agents/secrets` (600).

## Steps
1. `sudo apt install -y restic`; repo `/var/backups/restic` (root-owned dir, user-writable via setfacl); password in `~/agents/secrets/restic.env` (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`); `restic init`.
2. `~/agents/bin/backup-run`: `restic backup` of the paths above with excludes (`node_modules`, `moodledata`, `.cache`, docker volumes, `~/agents/browser/profile-*/Cache`), then `restic forget --keep-daily 14 --keep-weekly 8 --prune`, then `restic check --read-data-subset=5%` weekly; log to `~/agents/log/backup.log`; `notify-owner` only on failure.
3. `backup.timer` daily 05:00 (after the keeper's 04:30 dump), `backup.service` user unit with `Nice=10`, `IOSchedulingClass=idle`.
4. `~/agents/bin/backup-restore <path> [snapshot]` helper + KB runbook `restore.md` (restore a file, restore a DB dump into a container).
5. If the owner opted in for Drive: install rclone, leave a step-by-step for the owner to run `rclone config` once via SSH, then add `rclone sync /var/backups/restic gdrive:moodle-lab-restic` to `backup-run` guarded by `rclone listremotes | grep gdrive`.

## Success check
```bash
~/agents/bin/backup-run; echo exit=$?                      # 0
source ~/agents/secrets/restic.env && restic snapshots | tail -3
restic ls latest | grep -c "agents/KB/machine.md"           # 1
~/agents/bin/backup-restore ~/agents/KB/machine.md /tmp/restore-test && diff -q /tmp/restore-test/$HOME/agents/KB/machine.md ~/agents/KB/machine.md && echo restore-ok
systemctl --user list-timers | grep backup
```

## Rollback
Disable the timer; `sudo rm -rf /var/backups/restic`; delete scripts and `restic.env`.
