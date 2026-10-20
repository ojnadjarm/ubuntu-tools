# Owner to-do: one "waiting on you" list (owner-only steps)

Ticket: T372, T421 (decide) · Last verified: 2026-10-20 by T846 read-only audit (`--help`, paths, code); before: 2026-10-19 by `bin/tests/owner-todo.test.py`, `dashboard/tests/test_owner_todo.py` and headless shots at 400/768/1366/1920/2560

## When to use
A step only the owner can take (sudo/ufw command, a Discord or account setting, a `go TSP-…`, a decision, a restore from Trash):
add it here instead of burying it in a report. Not for transient alerts (those are pushes, `pc need`) or project tickets (TICKETS.md).

## The path we took
Survey: `pc need` lists 24 h pushes (expire, no steps); vass TICKETS.md is per project markdown; nothing kept owner steps with a how-to.
Chosen: an append-only ledger + one lib + a thin CLI, shown on the existing dashboard (headline count + Machine › To do sub-tab).

| Module | Role |
|---|---|
| `~/agents/state/owner-todo.jsonl` | ledger, one event per line: `add {id,text,how,src}`, `done {id,note}`, `reopen {id}`; each with `ts`, `by` |
| `~/agents/lib/owner_todo.py` | the only reader/writer: `items(home)` folds events (latest op wins), `add`/`done`/`reopen` append under `flock`; ids 1, 2, 3… |
| `~/agents/bin/owner-todo` | CLI over the lib: `add`, `list`, `done`, `reopen`, `decide` (read-only view, no lib change) |
| `dash/services/todo.py` | `GET /api/owner-todo`, `POST /api/owner-todo/done {id}` (calls the lib, CSRF via `Handler.cross_site`) |
| `system.verdict(..., todo)` | open items join `needs` as kind `todo` (key `todo`, not `id`, so `pc need` never lists or resolves them) |
| `static/js/screens/todo.js` | Machine › To do: one card per item, the steps in a copyable block, Copy + Done (`ask()` confirm) |

Single responsibility: the lib owns the format; CLI and dashboard only call it. Open/closed: a new field is one key in `add`.
Nothing rewrites history; `reopen` is the undo of `done`.

## Exact commands
```bash
owner-todo add "Grant the Discord bot View Audit Log" --how "Server Settings > Roles > agents > enable View Audit Log" --src T361
owner-todo list                 # open items: id, text, steps
owner-todo list --all --json    # everything, done included
owner-todo done 3 --note "ran it"   # agents only when they verified it is done; the owner taps Done on the dashboard
owner-todo reopen 3             # undo a done
owner-todo decide               # the go/drop items, one line each, then a sample batch reply
curl -s localhost:19998/api/owner-todo | jq '.[] | .id'
```

## Batch decisions (`decide`, T421)
`owner-todo decide` lists the open items whose text or how holds `go`, `drop`, `reply` or `tell the orchestrator:` (path parts like
`~/drop/` do not count), one line each, then `reply: 5 go, 6 drop, 7 go <words>`. Send it as the owner's one daily minute.

The orchestrator parses his answer as comma-separated `<id> go [words]` or `<id> drop` (also `no`/`skip` = drop, `yes`/`ok` = go):
- `5 go, 6 drop, 9 go 9` = item 5 go; item 6 drop; item 9 go with words `9` (T373 section 9). Words carry the item's own option
  (`15 go group 3`, `17 go keep`); without words, go = the item's first proposed option.
- go: brief the work the item's how names; close it with `owner-todo done <id> --note "go: <ticket>"` once briefed.
- drop: `owner-todo done <id> --note "dropped by owner"` at once.
- An id that is not open, or a piece that does not parse: do nothing for that piece and ask back in one line.

## Pitfalls (measured)
- `decide` picks items by words, not a field (the lib is shared): write decision items with `Tell the orchestrator: go …` or `reply '…'`
  in `--how`, and keep `go`/`drop` out of plain-step items. T421 seed: 10 of 17 matched, exactly the backlog's list.
- Verify the step is still open before adding (T372 seed: 6 of 13 candidates were already done: T349 D/E, T313 #1/#5/#8/#10; 7 seeded).
- `--how` holds the exact command or clicks; machine values only as `~`, `<lan-ip>`, never a password or token.
- `OWNER_TODO_LEDGER` overrides the path; tests always set it so they never touch the real ledger. `/api/status` reads the ledger,
  so dashboard `tests/conftest.py` points it at a missing fixture (without it `test_needs` failed 1/154 on the 7 real items).
- A change to `system.py`/`todo.py` needs `pc units restart agents-dashboard.service --user --apply`; a ledger edit needs nothing.

## Links
- Code: `~/agents/lib/owner_todo.py`, `~/agents/bin/owner-todo`, `~/agents/dashboard/dash/services/todo.py`, `dashboard/static/js/screens/todo.js`
- Tests: `python3 ~/agents/bin/tests/owner-todo.test.py`; `cd ~/agents/dashboard && python3 -m pytest tests/test_owner_todo.py`
- Skill `/owner-todo`
