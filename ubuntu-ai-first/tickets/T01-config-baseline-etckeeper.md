# T01 — Config baseline with etckeeper

**Phase 0 · must · Model: opus · Estimated agent time: 45 min**

## Goal
Every configuration change on this machine is reversible: `/etc` is under git (etckeeper) and a baseline copy of the agent-relevant user config exists.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"` (available after T01).
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Nothing under `/etc` is versioned today. Ubuntu 26.04, apt-based. Snap packages present but irrelevant here.
- User config that agents will change later: `~/.claude/settings.json`, `~/.claude/hooks`, `~/.claude/skills`, `~/agents/bin`, gsettings (GNOME).
- The owner manages git for their repos; etckeeper is the one exception (system-level, root-owned repo).

## Steps
1. `sudo apt install -y etckeeper`; check `/etc/etckeeper/etckeeper.conf` uses git; `sudo etckeeper init` if not already; `sudo etckeeper commit "baseline 2026-09-05"`.
2. Confirm the apt hook is active (`/etc/apt/apt.conf.d/05etckeeper`) so package installs auto-commit.
3. Create `~/agents/backups/` and a script `~/agents/bin/baseline.sh` that writes a timestamped tarball of `~/.claude/{settings.json,hooks,skills,CLAUDE.md,*.md}`, `~/agents/bin`, `~/CLAUDE.md` and `dconf dump / > dconf.ini` into `~/agents/backups/<date>.tar.gz`, keeping the last 20.
4. Run it once. Document both tools in `~/agents/README-pc-control.md` under a new "Rollback" heading (3 lines).

## Success check
```bash
sudo etckeeper vcs status | head -3            # clean tree, on a branch
sudo etckeeper vcs log --oneline | head -3      # baseline commit visible
ls ~/agents/backups/*.tar.gz | tail -1          # one baseline tarball
tar tzf $(ls ~/agents/backups/*.tar.gz | tail -1) | grep -c settings.json   # 1
```

## Rollback
`sudo apt remove etckeeper` and `sudo rm -rf /etc/.git`; delete `~/agents/backups` and `baseline.sh`.
