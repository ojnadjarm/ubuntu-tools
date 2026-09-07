# T20 — Kernel/OS limits: inotify, swappiness, file limits, journald and docker log caps

**Phase 4 · should · Model: opus · Estimated agent time: 45 min**

## Goal
Developer workloads (big Moodle repos, grunt watchers, Playwright, many containers) never hit kernel limits, and logs can never fill the disk.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Current: `fs.inotify.max_user_watches=65536`, `max_user_instances=128`, `vm.swappiness=60`, `ulimit -n 524288`, 8 GB swap file, THP `madvise`, `systemd-oomd` active, `/etc/sysctl.d` empty, journald defaults (volatile size unbounded), no `/etc/docker/daemon.json`.
- 37 GB RAM, 416 GB free. Only drop-in files; no edits to distributed files.

## Steps
1. `/etc/sysctl.d/90-agents.conf`: `fs.inotify.max_user_watches=1048576`, `fs.inotify.max_user_instances=1024`, `vm.swappiness=10`, `vm.max_map_count=262144`, `net.core.somaxconn=4096`, `kernel.sysrq=1`; `sudo sysctl --system`.
2. `/etc/security/limits.d/90-agents.conf`: nofile soft/hard 1048576 for the user; `/etc/systemd/system.conf.d/limits.conf` `DefaultLimitNOFILE=1048576`.
3. `/etc/systemd/journald.conf.d/90-agents.conf`: `Storage=persistent`, `SystemMaxUse=1G`, `MaxRetentionSec=1month`; `sudo systemctl restart systemd-journald`.
4. `/etc/docker/daemon.json`: `log-driver json-file`, `log-opts {max-size 20m, max-file 3}`, `live-restore true`; `sudo systemctl reload docker` (live-restore keeps containers up; confirm with `docker ps` that nothing restarted).
5. etckeeper commit; note the values in `~/agents/KB/machine.md`.

## Success check
```bash
sysctl fs.inotify.max_user_watches vm.swappiness       # 1048576, 10
journalctl --disk-usage; grep -h SystemMaxUse /etc/systemd/journald.conf.d/*.conf
docker info --format '{{.LoggingDriver}} live-restore={{.LiveRestoreEnabled}}'   # json-file live-restore=true
docker ps --format '{{.Names}} {{.Status}}' | grep -c "Up"   # 5 (nothing restarted)
sudo etckeeper vcs log --oneline | head -1              # T20 commit
```

## Rollback
Delete the four drop-in files and `daemon.json`, `sysctl --system`, restart journald, reload docker; or `sudo etckeeper vcs revert`.
