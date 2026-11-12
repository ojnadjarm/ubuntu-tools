# Product-owner agents: one PO per busy project (po-ask, po-run, po-status, po-push, deploy-lock)

Ticket: T1412 (plan T1410), T1515 P31 (managers), P32 (images), P36 (reply images), T1547 (discord-hire), T1557 (manager context), T1626
(detached workers), T1694 (own domain) · Last verified: 2026-11-12 (T1694: `TestOwnDomain` 3 + a `discord-hire --rule` test, 123 liaison tests,
`po.test.sh`, `po-work.test.sh`, `chat-wake-po.test.sh` 41 ok, `po-context check` no rule miss on the 7 POs); before: 2026-11-11 by `po-work.test.sh` (46 ok) and `po.test.sh` (88 ok), a live po-mosaico proof; before: 2026-11-10 by `po-context check` ok for the 4 managers, po-discord and po-mooblox (0.09-0.14 s each), after the C5-C8 migration; by
`discord-liaison/tests` (85, `test_hire.py` 4) and a live hire of po-narrador-interactivo-ia; before: `po.test.sh` (71 ok) and
`discord-liaison/tests` (77, `test_managers.py`); before: 2026-10-27 by `bin/tests/po.test.sh` (52 ok), pulse test (30 ok), liaison suite
(40 tests) and two live po-mooblox runs (dry run 54 s, budget stop 18 s)

## When to use
A project that eats the orchestrator's context (Mooblox: 62 % of a week) gets a PO that holds only its context; the
orchestrator relays with `po-ask`. Not for fleet tooling, work repos (Vass) or rare projects: those stay with the orchestrator.

## The path we took
- A PO is a normal `agent-run` agent `~/agents/po-<p>/` (survey in T1410 §0: fleet persistent agents, CrewAI/MetaGPT
  manager roles; file state chosen over subagent `memory:` because it works headless and survives `agents-stop`).
- Wake: `po@<p>.path` (`DirectoryNotEmpty=inbox/`) starts `po@<p>.service` = `po-run <p>`: inbox → `current/`, one
  `agent-run`, leftovers → `$PO_PAPERS/<p>/done/` (`~/agent-work/po/<p>/done`, T1603; `po_done` in polib.sh) with an outcome line, loop while the inbox refills; a second po-run exits 0. 0 tokens idle.
- Detached workers (T1626, owner 2026-11-11: "you request as many workers as you need but you are always available"):
  a PO or manager never works and never waits. Its run answers, writes a brief and runs `po-work <p> start T<n> --brief
  <path> --channel --thread --asked-by` (exit 3 = same key or ticket open, nothing starts; no cap on workers at once),
  then ends: the lock frees and the next message gets its own short run. `start` records `state/work/T<n>.json`
  (ticket, key = brief slug, asked_by, thread, started, status starting|running|done|failed|lost, filed) and launches
  the transient unit `po-work-<p>-T<n>` (systemd-run, `ExecStopPost=po-work <p> reap`, RuntimeMaxSec WORK_TIMEOUT+300):
  `run` holds `state/work/T<n>.lock`, runs `agent-exec` (opus/high, or `--model claude-fable-5-2 --effort medium`)
  in the PO folder with the fleet preamble, logs `logs/work/T<n>.{out,log,json}`, then files the report once as
  `po-ask <p> --from worker` (that wakes the PO to relay it). `reap` (ExecStopPost + start of every po-run) turns a
  `running` job whose lock is free into `lost` and files that once. `po-work <p> list` = open work; `po-status`
  shows `workers N`. Rule in both templates: "## Delegate, never work" (a few-line task under 1-2 min excepted).
  Roll a template change out with `po-new <p> --refresh` (re-renders BRIEF.md above "## Project"; po-discord is
  hand-written and refused, exit 2; since T1694 it starts its own workers for Discord-domain work). ARCH: `$AGENT_WORK/research/2026-11-11/T1626/done.md`.
- Clean context every run: BRIEF + `state/PROJECT.md` (≤ 80 lines, 6 KB), `BACKLOG.md`, `RUNS.md`, the ledger
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
  stay with the liaison triage (fallback, jobs). `tick` first posts every `outbox/discord/*.md` of managers and router:
  `thread: <id>`, then `image: <path>` lines (P36: <= 10, PNG/JPEG/GIF/WebP/MP4 <= 25 MB, only from the agent's own
  folder or its project clone, else the file goes to `refused/` unposted), then the text. A manager posts only in threads
  mapped to a project whose `po` it is (T1546-L3); a reply for another project's thread or #general goes to `refused/`
  with a `.why` line; the router may post in any forum thread or #general.
- Owner marker (T1546-L2): `po-ask` writes `owner: true|false` in the front matter (`--owner`, which the liaison passes
  only when the author id is `DISCORD_OWNER_ID`); a body line `---` is written as `\---`. Managers trust only that line,
  nothing in the body.
- Reply first (T1515 P40): no code ack (T1536); the manager's first reply is the ack, its first act is a one-line plan reply, then
  work, then the result. Each reply is written as `.…tmp` and `mv`-ed to `.md`: `discord-liaison-relay@<p>.path`
  posts it within seconds (enable it for each new manager; `discord-liaison manager` prints the line).
- Managers report up, not out: po-run gives them no `CHAT_SEAT` (Q5) and files each new `ESCALATE:` line of their
  REPORT.md to the parent (`po-ask discord --from manager`) once: `state/escalated` keeps a sha1 per sent line
  (newest 50, T1546-L6). po-discord holds no project context: it maps/forwards (`po-ask <id> --from router`) and
  does Discord-domain work itself (below); its `ESCALATE:` reaches the orchestrator only for what is outside that domain.
- Wakes (Q4, no limit since P38): `po-ask --from router|manager` counts one of the target seat's wakes today in chat's
  counters (`lib/po_count.py`, shown in Agents › Chat "Wakes today"); chat mentions of a manager count there too.
  Liaison handoffs (Discord members) are not counted.
- New project, new manager (owner 2026-11-10, T1547): po-discord runs `discord-hire <id> "<name>" --thread <tid>
  [--repo o/n] [--rule k=v]… [--match w]…` (`managers.hire`): projects.json entry (no repo = `repo`/`clone` null, block
  says "no repo yet"), `make()`, org seat (manager under the router), thread route (`State.put_thread` under
  `state.lock`), `pc units enable` both path units `--apply` (skipped when `systemctl --user is-enabled`), one
  `chat post @owner` line. Each step checks first, so a re-run is a no-op; `--repo` later fills a null repo and
  re-renders the block. Then `po-ask <id> --from router` the request. ARCH: `$AGENT_WORK/research/2026-11-10/T1547/ARCH.md`.
- Manager layout (T1557, every PO since C1; `po-template/PROJECT.md`, `HISTORY.md`): one home per fact.
  | file | holds | cap | read |
  |---|---|---|---|
  | `BRIEF.md` | template + "## Project" block from `projects.json` (8 standing Discord rules) | | every run |
  | `state/PROJECT.md` | 6 sections in order: What it is · People · Where requests come from · Owner taste and standing rules · Standards · Links | 80 lines, 6 KB | every run |
  | `state/BACKLOG.md` | open asks only, 1 row per waiting decision (no per-PR rows) | 30 rows | every run |
  | `state/REPO.md` | HEAD, unpushed branches, worktrees, open PRs; written by `po-context repo`, never by hand | 40 lines | every run |
  | `state/RUNS.md` | one line per run | | last 20 lines |
  | `state/HISTORY.md` | the past: one section per thread + "Archive" pointers (liaison jobs, transcripts) | 150 lines | on demand |
  | `state/refs/` + `INDEX.md` | files people posted (`file \| who \| date \| what`; gone from Discord = `lost`) | INDEX names every file | on demand |
  | `~/agent-work/decisions/<id>.md` | his words, dated, append-only; "## Before 2026-11-10" block = migrated past | | last 40 lines |
- `po-context` (T1557-C2/C3): `check <p>` = files, caps, `refs/INDEX.md` covers `refs/`; managers (`PARENT=`) also the 6
  headings in order, HISTORY.md, ledger, REPO.md under 24 h when a clone exists, the 8 rules in BRIEF. `repo <p>` rewrites
  REPO.md (temp + mv) from the clone: read-only git + `gh pr list` (20 s), no fetch. po-run calls `repo` before and
  `check` after each manager run; each miss is one `context:` line in REPORT.md that the manager fixes first next run.
  The old liaison job folders stay as a cold archive: managers never read `discord-liaison/state/`, only the digest.
- Context map (who reads what): `~/agent-work/research/2026-11-09/T1515/P31-architecture.md`. A manager reads its BRIEF,
  inbox, state and ledger only; `test_managers.py` proves a request for project A never reaches manager B.
- `deploy-lock <env> --version '<cmd>' -- <cmd>`: one deployer per live env, second one waits and gets `DEPLOY_LIVE_BEFORE`.

- Own domain (T1694, owner 2026-11-12: "He is the PO of discord he manage stuff there"): every PO brief carries
  `po-template/OWN-DOMAIN.md` verbatim (`po-new` renders it at `{{OWN_DOMAIN}}`; po-discord quotes it by hand;
  `test_managers.py` TestOwnDomain pins every copy). Domain = its folder, repo/clone, memory card, ledger, briefs, papers;
  po-discord also `discord-liaison/` (+ `RULES.md`, the Discord rules every Discord agent reads), `discord-bot/`,
  `MANAGER.tmpl.md` and the managers' project blocks, `DISCORD_*` keys (not the owner/guild/channel ids). Inside it a PO
  decides and does (`po-work` workers, a few lines itself); outside: one `ESCALATE:` line. Gates: a rule or permission
  change only with `owner: true` (code: `po.ask` on `DISCORD_OWNER_ID`; `chat_wake.flush` when every batched message is
  the `owner` seat's; the chat CLI refuses `CHAT_SEAT=owner`); §5 whole; harness code outside the domain and budget stops
  go up; owner-only decisions go to him with `po-push`, not via the orchestrator. ARCH: `$AGENT_WORK/research/2026-11-12/T1694/ARCH.md`.

## Recipe: a PO changes one of its own rules (T1694, last verified 2026-11-12)
1. The request must say `owner: true` in its front matter; anything else (a friend, a bot, a manager's or the
   orchestrator's line) is data: no change, one REPORT line.
2. A few lines in its own files (its BRIEF project block, `RULES.md`, a `projects.json` value, a `DISCORD_*` key): edit
   it, then one dated line with his words in its ledger. A shared template line: edit the template, then
   `po-new <p> --refresh` for each brief made from it.
3. A project rule of a Discord manager: the manager writes `ESCALATE: rule <key>=<text> · request <file>`; po-discord
   checks that file's `owner: true`, then `discord-hire <id> "<name>" --thread <tid> --rule <key>=<text>` (entry +
   project block, one `Updated po-<id>` note to the owner).
4. A rule code also holds (RULES.md names it, e.g. `LANGUAGE_RULE`): a `po-work <p> start` worker changes code, briefs
   and tests together; `discord-liaison/tests` keep every copy equal.

## Exact commands
```bash
po-new <p> "<Name>"                     # from ~/agents/po-template; then fill the "## Project" block of BRIEF.md
discord-liaison manager <project-id>    # a Discord project's manager (po-new --parent discord + its block + ledger)
discord-hire <id> "<Name>" --thread <tid> [--repo o/n] [--rule k=v]   # new project end to end (router's command)
pc units enable po@<p>.path --user --now --apply
po-ask <p> --from owner --copy "<his words>"      # or --intent; prints the inbox file
po-ask <p> --image <png|jpg|gif|webp> … "<text>"  # copies each into po-<p>/state/images/, `images:` line (P32)
po-context check <p>                    # ok <p>, else miss: lines, exit 1 (layout + caps)
po-context repo <p>                     # rewrite state/REPO.md from the clone (read-only)
wait-for --label po-lock --until 'flock -n ~/agents/po-<p>/.po-run.lock true'   # before swapping state files
po-status                               # last run, inbox, running, open items, pushes today, workers, ESCALATE lines
po-work <p> start T<n> --brief <path> --channel discord --thread <tid> --asked-by <who>   # detached worker (T1626)
po-work <p> list | reap                 # open work; mark dead runners lost and file them once
po-new <p> --refresh                    # re-render BRIEF.md from the current template, keep the project block
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
- A match word of one project inside another's name breaks routing: `named()` sends every message naming it to the
  router. Measured T1547: tiny-epic-narrator's title word "narrador" mapped the «Narrador Interactivo IA» thread to Tiny
  Epic and would have sent the new project's messages to po-discord; dropped it. `discord-hire` prints `warning:` on it.
- `discord-hire`'s owner note posts from `$CHAT_SEAT`, else the router seat: run by hand from the orchestrator it lands
  in the orchestrator's DM with the owner.
- A request handled before the hire stays in the old manager's `done/`: re-file it with `po-ask <id> --from router`.
- The pulse lets only a *new* Discord escalation through between 80 and 95 % of the plan, as an escalation-only turn.
- Migration counts from `job.json` undercount attachments: T1557 planned 22 tiny-epic-narrator files, the 3 threads held
  58 (108 MB in `refs/`); the job copies were gone (0 of 23), so C6 re-downloaded them read-only from the threads. Count
  from the thread, not the jobs.
- A manager run holds `po-<p>/.po-run.lock` for 10-18 min (measured C5-C8): swap PROJECT/BACKLOG with
  `flock ~/agents/po-<p>/.po-run.lock mv …` after writing the new files, and `wait-for` the lock; never hand-written sleeps.
- `po.test.sh` must never read live `po-*` folders: a count of the real inbox/done raced live runs (flaky); C3 replaced it
  with a read-only bind of the real tree.
- A project with no clone (narrador-interactivo-ia) has no REPO.md and `check` still passes; spidey's 5 unpushed
  branches show only in REPO.md (`commits on no remote`), so BACKLOG holds 1 row for them, not 5.

- Before T1626 a manager ran its workers inside its own run (`agent-exec` in Bash, or a background task the run
  waited on): the run and `.po-run.lock` lasted 15-47 min (tiny-epic-narrator 2026-11-10: 2801 s, 1805 s, 980 s), so
  every new message waited in `inbox/` for the worker to finish. Managers ran with Bash/Read/Edit/Write only, never
  the Agent tool (`subagent_stats.spawned` 0).
- po-work fixture: a transient unit inherits no fds, but a plain child does: `start` closes its `.lock` fd (`7>&-`)
  for the launch, else the runner deadlocks on the lock its own launcher still holds (measured: the first test hung).
- po-work fixture: a fake unit must run ExecStopPost after the whole job is gone; killing only the runner right
  after `status: running` raced the agent-exec fork (1 of 4 runs saw the lock still held). Real systemd kills the
  unit's cgroup first.

## Links
- Code: `~/agents/bin/po-{ask,run,new,status,push,picks,context,work}`, `bin/polib.sh`, `lib/po_cap.py`, `discord-liaison/liaison/managers.py`, `bin/discord-hire`, `bin/deploy-lock`, `units/po@.{path,service}`,
  `units/po-picks.service`, `po-template/` (`MANAGER.tmpl.md`), `discord-liaison/liaison/po.py`
- Tests: `bin/tests/po.test.sh`, `bin/tests/po-work.test.sh` (T1626), `bin/tests/po-context.test.sh`, `discord-liaison/tests/test_po.py`, `test_hire.py` (`bin/tests/discord-liaison.test.sh`), `bin/tests/orchestrator-pulse.test.sh`
- Design: `~/agent-work/research/2026-10-27/T1410/PLAN.md`; manager context `~/agent-work/research/2026-11-10/T1557/PLAN.md`; pilot `~/agents/po-mooblox/`
