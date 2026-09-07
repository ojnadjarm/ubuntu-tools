# T03 — Boot resilience: everything comes back after a reboot

**Phase 0 · must · Model: opus · Estimated agent time: 60 min**

## Goal
After an unattended reboot: Docker stacks are up, the orchestrator Claude session runs in tmux with Remote Control, user timers can fire, and `docker` works without a socket ACL.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"` (available after T01).
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Compose files: `~/moodle-envs/shared/docker-compose.yml` and `~/moodle-envs/5.2/docker-compose.yml` have no `restart:` policy. The generator that writes them lives in `~/.claude/skills/moodle-install/install.sh` (harness; live copy in `~/.claude`, repo copy `~/moodle-harness` updated with `~/moodle-harness/sync.sh`).
- `loginctl show-user oscar-nadjar -p Linger` → no. GDM autologin is on. docker/tailscaled/ssh/ydotoold are enabled system services.
- The orchestrator runs as `tmux` session `claude` started with `claude --remote-control` in `~`. Claude binary: `~/.local/bin/claude` (native, no nvm needed).
- User is in the docker group but shells need a re-login; a reboot fixes it.

## Steps
1. Add `restart: unless-stopped` to every service in both compose files; apply with `docker compose up -d` for each (no data loss: same volumes/bind mounts). Patch `install.sh` so new envs get the same policy; run `~/moodle-harness/sync.sh` and tell the owner to commit.
2. `sudo loginctl enable-linger oscar-nadjar`.
3. Create `~/.config/systemd/user/claude-orchestrator.service`: `Type=forking`, `ExecStart=/usr/bin/tmux new-session -d -s claude -c %h '~/.local/bin/claude --remote-control moodle-lab'`, `ExecStop=tmux kill-session -t claude`, `Restart=on-failure`, `Environment` from `~/agents/bin/env.sh` plus `PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin`. `WantedBy=default.target`. Only enable it; do NOT start it now if a `claude` tmux session already exists (it would clash). Document that the running session must be stopped once and the service started, ideally by the owner at the next reboot.
4. Create `~/agents/bin/boot-check.sh`: prints one line per item (docker stacks, tmux claude, linger, tailscale, ssh, ydotoold) with OK/FAIL and exits non-zero on any FAIL. It will be reused by T05/T17.
5. Add a short "After reboot" section to `~/agents/README-pc-control.md`.

## Success check
```bash
grep -c "restart: unless-stopped" ~/moodle-envs/shared/docker-compose.yml ~/moodle-envs/5.2/docker-compose.yml   # 3 and 2
docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' moodle52-app-1   # unless-stopped
loginctl show-user oscar-nadjar -p Linger        # Linger=yes
systemctl --user is-enabled claude-orchestrator  # enabled
~/agents/bin/boot-check.sh; echo exit=$?         # all OK, exit=0
```
Full proof requires a reboot; do not reboot in this ticket. Report "reboot test pending" for T23 or the owner.

## Rollback
Remove the `restart:` lines and re-`up`; `loginctl disable-linger`; `systemctl --user disable claude-orchestrator` and delete the unit; revert `install.sh` from `~/moodle-harness`.
