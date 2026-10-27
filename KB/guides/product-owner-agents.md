# Product-owner agents: one PO per busy project (po-ask, po-run, po-status, po-push, deploy-lock)

Ticket: T1412 (plan T1410) · Last verified: 2026-10-27 by `bin/tests/po.test.sh` (52 ok), pulse test (30 ok), liaison suite
(40 tests) and two live po-mooblox runs (dry run 54 s, budget stop 18 s)

## When to use
A project that eats the orchestrator's context (Mooblox: 62 % of a week) gets a PO that holds only its context; the
orchestrator relays with `po-ask`. Not for fleet tooling, work repos (Vass) or rare projects: those stay with the orchestrator.

## The path we took
- A PO is a normal `agent-run` agent `~/agents/po-<p>/` (survey in T1410 §0: fleet persistent agents, CrewAI/MetaGPT
  manager roles; file state chosen over subagent `memory:` because it works headless and survives `agents-stop`).
- Wake: `po@<p>.path` (`DirectoryNotEmpty=inbox/`) starts `po@<p>.service` = `po-run <p>`: inbox → `current/`, one
  `agent-run`, leftovers → `done/` with an outcome line, loop while the inbox refills; a second po-run exits 0. 0 tokens idle.
- Clean context every run: BRIEF + `state/PROJECT.md` (≤ 200 lines), `BACKLOG.md`, `RUNS.md`, the ledger
  `~/agent-work/decisions/<p>.md`. Requests keep his words verbatim (`quote: copy|intent`).
- Budget: po-run passes `PO_BUDGET=stop` when `plan-usage --check 95` exits 1; the PO then spawns nothing and writes
  `ESCALATE: budget`. `po-status` shows `ESCALATE:` lines to the orchestrator.
- Owner pushes: `po-push` (≤ 3/day, `[<p>]` prefix) via `notify-owner -a`; pick buttons are ntfy `http` actions that POST
  `<p>:<pick-id>:<key>` to the reply topic (`NTFY_REPLY_TOPIC`, else `<topic>-picks`). `po-picks.service` streams that
  topic and files a tap that matches an unanswered `state/picks/<id>.json` as `po-ask <p> --from pick`; anything else dropped.
- Discord: a project with `"po": "po-<p>"` in `discord-liaison/projects.json` — `discord-liaison inbox`/`map` hand its
  messages to the PO once (`state/po-asked.json`), `tick` first posts `po-<p>/outbox/discord/*.md` (`thread: <id>` line).
- `deploy-lock <env> --version '<cmd>' -- <cmd>`: one deployer per live env, second one waits and gets `DEPLOY_LIVE_BEFORE`.

## Exact commands
```bash
po-new <p> "<Name>"                     # from ~/agents/po-template; then fill the "## Project" block of BRIEF.md
pc units enable po@<p>.path --user --now --apply
po-ask <p> --from owner --copy "<his words>"      # or --intent; prints the inbox file
po-status                               # last run, inbox, running, open items, pushes today, ESCALATE lines
po-push <p> --pick 'A=Dimensioned;B=Plain' "pick a look <link>"
deploy-lock 5.2 --version '<read live version>' -- <deploy cmd>
bash ~/agents/bin/tests/po.test.sh      # fixture: bwrap no-net, fake ntfy, fake agent-run
```

## Pitfalls (measured)
- `po-ask` writes into `.inbox-tmp/` and renames: the path unit fires within 1 s of a file landing (live: the same second), so a
  half-written file would be read. Never write requests into `inbox/` by hand; tests that need no unit write to `current/`.
- `agent-run` exits 0 with "already running" when its own lock is held; po-run then files the batch as "left in current/".
  Do not run `agent-run po-<p>` by hand while the unit is active.
- Live run cost: the dry run read 286k cache tokens and wrote 4.8k (54 s, ~$0.47); the budget stop 18 s. A PO run is
  not free: the T1410 §5 per-request estimate (~150k) was low for the first read of a fresh state.
- `*/state/` is gitignored, so `po-template` keeps its state stubs at its root and `po-new` copies them into `state/`.
- New CLIs need `~/agents/install.sh --links` (or the `~/.local/bin` symlink) before a session can call them.
- The pulse lets only a *new* Discord escalation through between 80 and 95 % of the plan, as an escalation-only turn.

## Links
- Code: `~/agents/bin/po-{ask,run,new,status,push,picks}`, `bin/polib.sh`, `bin/deploy-lock`, `units/po@.{path,service}`,
  `units/po-picks.service`, `po-template/`, `discord-liaison/liaison/po.py`
- Tests: `bin/tests/po.test.sh`, `discord-liaison/tests/test_po.py` (`bin/tests/discord-liaison.test.sh`), `bin/tests/orchestrator-pulse.test.sh`
- Design: `~/agent-work/research/2026-10-27/T1410/PLAN.md`; pilot `~/agents/po-mooblox/`
