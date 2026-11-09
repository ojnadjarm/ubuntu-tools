# Product-owner agents: one PO per busy project (po-ask, po-run, po-status, po-push, deploy-lock)

Ticket: T1412 (plan T1410), T1515 P31 (managers), P32 (images) · Last verified: 2026-11-10 by `po.test.sh` (69 ok) and
`discord-liaison/tests` (76, `test_managers.py`); before: 2026-10-27 by `bin/tests/po.test.sh` (52 ok), pulse test (30 ok), liaison suite
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
- Discord (T1515 P31): one **manager** per Discord project, `po-<project-id>` (seat role `manager` under `discord` in
  `org.json`), made by `discord-liaison manager <id>` = `po-new <id> "<name>" --parent discord` (`po-template/MANAGER.tmpl.md`,
  `PARENT=` in agent.env) + a "## Project" block rendered from that one `projects.json` entry + ledger
  `~/agent-work/decisions/<id>.md`. The entry's `po` names its manager; top-level `"router": "po-discord"` turns on code
  routing: `tick` runs `Registry.dispatch` before any LLM run and `po-ask`s each message to its manager; a thread with no
  project or a message naming a 2nd project goes to the router; #general, a project without `po` and a failed `po-ask`
  stay with the liaison triage (fallback, jobs). `tick` first posts every `outbox/discord/*.md` of managers and router.
- Managers report up, not out: po-run gives them no `CHAT_SEAT` (Q5) and files each new `ESCALATE:` line of their
  REPORT.md to the parent (`po-ask discord --from manager`, counted in `state/escalated`). po-discord holds no project
  context: it maps/forwards (`po-ask <id> --from router`) and writes its own `ESCALATE:` for the orchestrator.
- Cap (Q4): `po-ask --from router|manager` takes one of the target seat's 12 wakes a day from chat's counters
  (`lib/po_cap.py`, exit 4 at the cap); chat mentions of a manager hit the same counter via `chat_route`. Liaison handoffs
  (Discord members) are not capped.
- Context map (who reads what): `~/agent-work/research/2026-11-09/T1515/P31-architecture.md`. A manager reads its BRIEF,
  inbox, state and ledger only; `test_managers.py` proves a request for project A never reaches manager B.
- `deploy-lock <env> --version '<cmd>' -- <cmd>`: one deployer per live env, second one waits and gets `DEPLOY_LIVE_BEFORE`.

## Exact commands
```bash
po-new <p> "<Name>"                     # from ~/agents/po-template; then fill the "## Project" block of BRIEF.md
discord-liaison manager <project-id>    # a Discord project's manager (po-new --parent discord + its block + ledger)
pc units enable po@<p>.path --user --now --apply
po-ask <p> --from owner --copy "<his words>"      # or --intent; prints the inbox file
po-ask <p> --image <png|jpg|gif|webp> … "<text>"  # copies each into po-<p>/state/images/, `images:` line (P32)
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
- Before P31 every Discord request cost a triage LLM run first: the handoff ran only when the triage called `inbox`/`map`.
- `po-new --parent` still prints "fill the '## Project' block": `discord-liaison manager` has filled it already.
- `discord-liaison/tests/test_po.py` or `test_managers.py` alone fails to import `discordbot`; run the folder
  (`test_liaison` puts the bot on sys.path).
- At the P31 switch po-discord held 3 project requests (1 running, 2 queued): its next loop reads the router brief and
  forwards them with `po-ask <id> --from router`, so the first wakes of each manager count against its 12.
- The pulse lets only a *new* Discord escalation through between 80 and 95 % of the plan, as an escalation-only turn.

## Links
- Code: `~/agents/bin/po-{ask,run,new,status,push,picks}`, `bin/polib.sh`, `lib/po_cap.py`, `discord-liaison/liaison/managers.py`, `bin/deploy-lock`, `units/po@.{path,service}`,
  `units/po-picks.service`, `po-template/` (`MANAGER.tmpl.md`), `discord-liaison/liaison/po.py`
- Tests: `bin/tests/po.test.sh`, `discord-liaison/tests/test_po.py` (`bin/tests/discord-liaison.test.sh`), `bin/tests/orchestrator-pulse.test.sh`
- Design: `~/agent-work/research/2026-10-27/T1410/PLAN.md`; pilot `~/agents/po-mooblox/`
