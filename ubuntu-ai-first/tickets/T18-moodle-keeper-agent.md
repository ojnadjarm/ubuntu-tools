# T18 — Moodle keeper: daily care of the dev environments

**Phase 3 · must · Model: opus · Estimated agent time: 75 min**

## Goal
Every day the Moodle environments are up, their databases are dumped, disk is kept clean, and (weekly, only when the checkout is clean) stable branches are pulled and upgraded, with a short report and no owner involvement.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Envs: `~/moodle-envs/<ver>` (`docker-compose.yml`, `www` clone of `MOODLE_<MMM>_STABLE`, plugins under `www/public` on 5.1+), shared stack in `~/moodle-envs/shared`. DB: postgres 16 container `moodle<MM>-db-1` (creds in `config.php`). `moodle-envs` lister (T13). Harness rules `~/.claude/moodle-guidelines.md`. Docker images 8.9 GB, 4.6 GB reclaimable today.
- Risk: plugin work in progress inside `www/public/<plugin>` — pulling core is safe only if `git status --porcelain` (core repo) is clean and plugins are separate repos; never touch plugin dirs.
- Backups land in `~/agents/backups/moodle/<ver>/YYYY-MM-DD.sql.gz`; restic (T22) will pick that folder up.

## Steps
1. `~/agents/bin/moodle-keep` (bash, no Claude): for each env: `docker compose up -d`, wait for HTTP 200/303 on the wwwroot, `pg_dump` via `docker exec` to the backups folder (keep 14), run `admin/cli/cron.php` once if the env is used for testing cron features (flag in `agent.env`), then `docker image prune -f` and `docker builder prune -f`; print a summary and exit non-zero on any env that is not reachable.
2. Weekly part (`moodle-keep --weekly`, Sundays 05:00): for each env with a clean core checkout: `git pull --ff-only`, `php admin/cli/upgrade.php --non-interactive` in the container, `purge_caches.php`; skip and report otherwise.
3. `~/agents/moodle-keeper/BRIEF.md` + `agent-enable moodle-keeper "*-*-* 04:30"`: the Claude run only executes `moodle-keep`, and if it fails, investigates (logs, `pc status`, docker logs), fixes what runbooks allow, writes `REPORT.md`, pushes only on unresolved failure. Keep the brief ≤ 40 lines.
4. Add the keeper to the roster in `~/CLAUDE.md` (T19 formalises the table).

## Success check
```bash
~/agents/bin/moodle-keep; echo exit=$?                     # 0, dump created
ls -la ~/agents/backups/moodle/5.2/ | tail -2
zcat ~/agents/backups/moodle/5.2/*.sql.gz | head -20 | grep -c "PostgreSQL database dump"   # 1
agent-now moodle-keeper && sleep 120 && cat ~/agents/moodle-keeper/REPORT.md
agents-status | grep moodle-keeper                           # enabled, 04:30
```

## Rollback
`agent-disable moodle-keeper`; delete the agent folder and `moodle-keep`.
