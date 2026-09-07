# D02 — which container is unhealthy?

pc path: `pc docker health --json`. Raw path: `docker ps` (STATUS column shows "unhealthy") or
`docker inspect --format '{{.State.Health.Status}}'`.
