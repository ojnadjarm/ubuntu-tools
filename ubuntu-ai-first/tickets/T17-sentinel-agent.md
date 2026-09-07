# T17 — Sentinel: health checks every 15 min, LLM repair only on failure

**Phase 3 · must · Model: opus · Estimated agent time: 75 min**

## Goal
The machine notices and fixes its own problems (stack down, Tailscale off, ydotoold dead, disk filling, screen locked, session gone) without the owner, and sends one push only when it could not fix something or once a day as a digest.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- `pc status --check` (T05) is the detector; `agent-run`/timers (T15); `notify-owner` (T04); runbooks in `~/agents/KB/runbooks/`; boot-check (T03).
- Pattern (PLAN §2.5): bash first, Claude only when bash fails. Cost matters: a 15-min timer must not start Claude on a healthy machine.
- Repairs Claude may do unattended: `docker compose up -d`, `sudo tailscale up`, `systemctl restart ydotoold`, `systemctl --user restart claude-orchestrator` (only if tmux `claude` is gone), `docker system prune -f` (dangling only), journald vacuum, killing runaway agent processes. Never: reboot, apt changes, sshd/ufw changes, deleting user data.

## Steps
1. `~/agents/bin/sentinel-check`: runs `pc status --check --json`; on OK writes a heartbeat `~/agents/sentinel/state/last-ok` and exits 0. On FAIL: tries the matching runbook's bash fix for known simple cases (stack down → compose up; tailscale → up), re-checks; if still failing writes `state/incident.json` and runs `agent-run sentinel` (Claude) with the incident attached.
2. `~/agents/sentinel/BRIEF.md`: read the incident + `pc status`, follow runbooks, allowed/forbidden actions list above, verify with `pc status --check`, write `REPORT.md`, push `notify-owner` only if unresolved (priority high) with a 1-line cause and the log path. Model: opus, timeout 20 min, budget cap if API-billed.
3. Timers: `sentinel-check.timer` every 15 min (plain bash unit, not `agent@`), plus `agent@sentinel-digest` daily 08:00 running a short brief: summarise the last 24 h (incidents, agent runs from `agents-status`, disk/battery trend) into one push ≤ 300 chars and a fuller `REPORT.md`; if nothing happened, the push says so in one line.
4. Fault-injection test: `docker stop moodle-shared-mailhog-1`, run `sentinel-check`, expect the bash fix to restore it without Claude; then break something a runbook does not cover (e.g. rename `~/agents/bin/screenshot.sh` temporarily) and expect a Claude run + a push; restore.

## Success check
```bash
docker stop moodle-shared-mailhog-1 && ~/agents/bin/sentinel-check; docker ps | grep -c mailhog   # 1, no Claude run (check logs/index.tsv)
mv ~/agents/bin/portal_shot.py /tmp/ && ~/agents/bin/sentinel-check; sleep 120; tail -1 ~/agents/sentinel/logs/index.tsv; mv /tmp/portal_shot.py ~/agents/bin/   # a Claude run happened; push received or fix applied
systemctl --user list-timers | grep -E "sentinel-check|agent@sentinel-digest"   # both scheduled
```

## Rollback
Disable both timers; delete `~/agents/sentinel` and `sentinel-check`.
