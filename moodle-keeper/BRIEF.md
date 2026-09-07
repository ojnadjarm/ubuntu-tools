# moodle-keeper — daily care of the Moodle dev environments

Run `moodle-keep` (bash, `~/agents/bin/moodle-keep`). It brings every env in `~/moodle-envs/<ver>`
up, waits for HTTP, dumps its database to `~/agents/backups/moodle/<ver>/YYYY-MM-DD.sql.gz`,
proves the dump restores into a scratch database, prunes dangling images/build cache and rotates
`~/agents/log`. These dumps are the only backup of these databases: a failed dump is serious.

## If it exits 0
Overwrite `REPORT.md` with at most 5 lines: the `== done` line, the dump size(s) and the disk line.
Stop. Do not push, do not investigate, do not touch anything else.

## If it exits non-zero
1. Read the output. Identify the failing env and stage (compose up / unreachable / pg_dump /
   restore / cron / upgrade).
2. Gather: `pc status`, `moodle-envs`, `docker logs --tail 50 <container>`, `docker compose ps`
   in the env dir, `df -h /`.
3. Fix only what these runbooks allow:
   - container down or unhealthy → `docker compose up -d` / `docker compose restart <service>`
     in `~/moodle-envs/<ver>`, then re-run `moodle-keep`.
   - HTTP not answering but containers up → wait 60 s and re-run once.
   - disk over 85 % → `docker image prune -f`, `docker builder prune -f`, `journalctl --vacuum-size=200M`.
     Never `docker system prune --volumes`, never delete images or volumes of a running env.
   - `~/agents/backups` growing → remove only dumps older than 14 days that are not dated `-01`.
   Anything else (DB corruption, upgrade failure, git conflicts, unknown errors): do not improvise.
4. Re-run `moodle-keep` after any fix and record the new exit code.
5. Write `REPORT.md` (≤5 lines): what failed, what you did, the final exit code.
6. Only if the failure is still unresolved after your fix attempts:
   `notify-owner -p high -t moodle-keeper "<one line: env, stage, what is broken>"`.

## Never
- Never commit, push, stage, reset, checkout or stash in any git repository.
- Never touch `www/public/<plugin>` directories or any plugin repo.
- Never stop or remove the Moodle 5.2 stack, the shared stack, or any volume.
- Never reboot, never kill the orchestrator tmux session (`$ORCHESTRATOR_TMUX_SESSION`), never use `pkill -f`.
- Never ask the owner for machine state you can read yourself.
