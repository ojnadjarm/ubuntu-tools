# Runbook: a docker stack or the daemon is down

1. Daemon: `systemctl is-active docker`; if not active `sudo systemctl start docker`.
   Permission denied on the socket: `sudo setfacl -m u:$USER:rw /var/run/docker.sock`.
2. What is down: `pc status | sed -n '/^DOCKER/,/^DESKTOP/p'` (shows running/total per project).
3. Bring stacks up (shared first, it owns the proxy):
   `docker compose -f ~/moodle-envs/shared/docker-compose.yml up -d`
   `docker compose -f ~/moodle-envs/<ver>/docker-compose.yml up -d`
4. A container restarting in a loop: `docker logs --tail 50 <name>`. Postgres usually means a stale
   lock or a full disk (see disk-full.md).
5. Verify: `pc status --check` exit 0 and `curl -sI http://localhost:8052 | head -1`.
