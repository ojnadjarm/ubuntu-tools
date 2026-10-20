---
name: claims
description: File claims board ~/agents/FILE-CLAIMS.md via the `claims` CLI. Use for "file claims", "claim files", "claims board", "FILE-CLAIMS", "release my claim", "stale claim", "who is editing". Declare, release, list, expire; unpinned rows are stale after 48 h.
---

Triggers: parallel agents collide, parallel-agent board, flock, FILE-CLAIMS.md.lock.

# claims

1. Before editing: `claims list` - a path held by a live row (not STALE) is someone else's; pick other work or ask the orchestrator.
2. Claim: `claims add T<nn> "<path>, <path>"` (`--pin` only for owner rows that must never expire). Exit 3 + `overlap: <ticket> <path>` = another live claim covers it: wait for release; `--force` only if the owner says so.
3. When done: `claims done T<nn>`; read back with `claims list`.
4. Dead rows: `claims expire` (dry run) then `claims expire --apply`; it prints every dropped line, re-add one with `claims add`.
5. `claims check` is the `pc doctor` WARN row (exit 2 when a row is stale).

Rules: never edit the board by hand while agents run (the CLI holds the lock). Rows with `pin` or `do not move` never expire;
nothing under 24 h is ever dropped (CLAIMS_STALE_H cannot go lower). Guide: `~/agents/KB/guides/file-claims.md`.
