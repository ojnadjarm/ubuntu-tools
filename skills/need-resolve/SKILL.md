---
name: need-resolve
description: Clear a stale "need you" dashboard alert. Use for "need you", "clear alert", "mark fixed", "resolve push", "stale notification". `pc need`, then `pc need resolve <id> --fixed "<what>" --apply` (ledgered, `pc undo`); any agent, no owner approval.
---

Triggers: needs you, alert, dashboard headline count, high-priority, asking pushes, append-only ledger, rollback.

# need-resolve

1. `pc need` - open pushes on the dashboard "need you" list: id, time, kind, text.
2. `pc need resolve <id> --fixed "<what fixed it, ticket>"` - dry run, prints `would: need:<id> open → resolved`.
3. Add `--apply`; the last line is `rollback: pc undo <undo-id>`. Say so in your report.
4. Read back: `pc need` no longer lists it; `curl -s localhost:19998/api/status | jq '.verdict.needs | length'`.

Rules: resolve only what you fixed; a text pattern matches every open push containing it, so prefer the id. `notify.log` is
never edited; the ledger is `~/agents/log/notify-resolved.jsonl`. A new push of the same failure gets a new id and shows again.
Guide: `~/agents/KB/guides/need-resolve.md`.
