# The flag-file container

`pcbench-sick` runs `sh -c '[ -f /flag/second ] && touch /tmp/ok; sleep 600'` with
`--health-cmd 'test -f /tmp/ok' --health-interval 2s --health-retries 1`, and `flag/` in this
directory bind-mounted at `/flag`.

1. `setup.sh` starts it with `flag/` empty → `/tmp/ok` is never created → **unhealthy** in ~2 s.
2. `setup.sh` then creates `flag/second`.
3. Only a fresh run of the entrypoint sees the flag, so **only a restart** turns it healthy.

That makes "restarted" and "healthy" the same observable fact: `docker exec … touch /tmp/ok`
or any other shortcut leaves the container's health green *without* a restart only if it also
re-runs the entrypoint, which it does not. `check.sh` additionally hashes every *other*
container's `StartedAt` so a blanket `docker restart $(docker ps -q)` fails.
