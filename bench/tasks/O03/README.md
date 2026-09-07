# O03 — what's on :8052?

pc path: `pc net who 8052` (prints pid, comm, unit-or-container in one call). Raw path:
`ss -ltnp | grep 8052` + `docker ps --format` to map the port to a container — two commands,
no shortcut. Depends on the owner's moodle52 stack being up; setup.sh skips (exit 1) rather
than injecting anything if it is down.
