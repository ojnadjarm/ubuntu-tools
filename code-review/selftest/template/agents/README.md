# Fleet (selftest fixture)

- 2026-08: `~/agents/tmp` was removed. Scratch files now live in each agent's `state/`, which the maintenance run sweeps; nothing writes `*.tmp` under `~/agents/tmp` any more.
