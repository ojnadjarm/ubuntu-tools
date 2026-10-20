---
name: owner-todo
description: The owner's "waiting on you" list. Use for "owner step", "needs the owner", "waiting on you", "blocked on owner", "he must run". `owner-todo add` a step only he can take (sudo/ufw, an account setting, a decision) with the exact how-to; list; `owner-todo done`.
---

Triggers: owner-only, to do for Oscar, owner command, Discord setting, go TSP-…, restore from Trash, dashboard headline, Machine > To do, Copy + Done.

# owner-todo

1. Check the step is really still open (read the state; never add what you can do yourself).
2. `owner-todo add "<one line, what and why>" --how "<exact command or clicks, one per line>" --src T<nn>` - prints the id.
3. Say the id in your report instead of burying the step in it.
4. Read back: `owner-todo list`; dashboard `curl -s localhost:19998/api/owner-todo | jq length`.
5. When you verify he did it: `owner-todo done <id> --note "<what shows it>"`; undo `owner-todo reopen <id>`.
6. Go/drop decisions: phrase `--how` as `Tell the orchestrator: go …` or `reply '…'`; `owner-todo decide` batches them into one
   reply (`5 go, 6 drop, 9 go 9`); the reply grammar is in the guide.

Rules: `--how` uses `~` and placeholders, never passwords or tokens. The ledger `~/agents/state/owner-todo.jsonl` is append-only;
never edit it by hand. Pushes that expire (`pc need`) are not to-dos. Guide: `~/agents/KB/guides/owner-todo.md`.
