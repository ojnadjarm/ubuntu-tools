# Clear a stale "need you" item on the dashboard (resolve a push)

Ticket: T264 · Last verified: 2026-10-20 (T846: `pc need --help`, `pc units` syntax, `push_key`/`resolved`/`verdict` read, test patching read); 2026-10-06 by `pc need resolve` on the two ailearning CI pushes (dashboard count 2 → 0) and the tests below

## When to use
A high-priority or asking push in `~/agents/log/notify.log` still counts on the dashboard "need you" headline after the cause was
fixed. Not for `pc status` FAILs or failed agent runs: those clear when the state itself is fixed.

## The path we took
No ack verb existed; `verdict()` counted every high/asking push of the last 24 h. Architecture: `notify.log` stays untouched; a
separate append-only ledger `~/agents/log/notify-resolved.jsonl` holds `{ts,key,state,fixed,by}` lines (`by` = `$AGENT_NAME`, else the session id), the latest line per key wins
(`resolved` or `open`). The key is the first 10 hex of sha1(`t` + TAB + `text`) of the push, so the same text pushed again later
is a new key and shows again. `dash/services/system.py` owns the key (`push_key`) and the reader (`resolved()`); `verdict()` skips
resolved pushes and tags each push need with its `id`. `pc need` (bash, pclib) is the only writer: it reads the open list from
the same Python (one source of truth), and each resolve goes through `pc_apply`, so it is ledgered in `changes.jsonl` with a
`pc undo <id>` that appends an `open` line (single responsibility: system.py reads, pc-need writes; nothing rewrites history).

## Exact commands
```bash
pc need                                   # open pushes on the "need you" list: id, time, kind, text
pc need resolve <id|text> --fixed "T261 fixed it"            # dry run: would: need:<id> open → resolved
pc need resolve <id|text> --fixed "T261 fixed it" --apply    # one "rollback: pc undo <id>" line per resolved push
pc undo <undo-id> --apply                 # reopen that push; undo each to reopen all
curl -s localhost:19998/api/status | jq '.verdict.needs | length'
```

## Pitfalls (measured)
- Any agent resolves an alert the moment it fixes the cause, no owner approval; `--fixed` is required.
- A failed agent run counts once: while its open `agent <name> failed (exit N)` push (at or after the run's end) is listed,
  `verdict()` skips the id-less agent row; resolving that push brings the agent row back until the next good run (2026-10-15, F19).
- A text pattern resolves every open push it matches (both CI pushes matched "ailearning daily ci"); use the id for one.
- A resolve needs no restart (`verdict()` re-reads the ledger per request); a change to `system.py` itself needs `pc units restart agents-dashboard.service --user --apply`.
- Tests never touch the real files: the pytest patches `system.HOME`, the shell test sets `HOME` and `PC_LEDGER` to a temp dir.

## Links
- Code: `~/agents/bin/pc-need`, `~/agents/dashboard/dash/services/system.py` (`push_key`, `resolved`, `verdict`)
- Tests: `cd ~/agents/dashboard && python3 -m pytest tests/test_need_resolve.py`; `bash ~/agents/bin/tests/pc-need.test.sh`
- Ledger: `~/agents/log/notify-resolved.jsonl`; skill `/need-resolve`
