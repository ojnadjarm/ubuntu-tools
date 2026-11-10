# Discord liaison: the agent that answers the #foro forum and @agents in #general, and turns requests into PRs

Ticket: T1409, T1411, T1413, T1414, T1415, T1416, T1421, T1482, T1515 P31, P32, P36, P40, T1536 · Last verified: 2026-11-10 (T1546-M2: 6 approval fixture tests, the owner's ✅ reaches the manager once; T1546 L1-L5: 94 fixture tests, po-asked.json saved per hand-off, a failed image download is skipped; T1536: 81 fixture tests, hand-off posts nothing; P40: relay on outbox write; P36: 77 fixture tests, a manager's reply images reach its thread, 8 bad paths refused; P32: 76 fixture tests, an image reaches only its manager; P31: 75 fixture tests,
`test_managers.py` 5: code routing to one manager per project); 2026-11-04 (T1482 postmortem of 119 jobs, lessons in `JOB.md`, guarded by `tests/test_lessons.py`); 2026-10-31 (caps re-read from agent.env, F71); 2026-10-27 by 63 liaison fixture tests (T1421: 6 batch/supersede/stale tests) + a live nudge → wake run; before: 57 (T1416: 8 routing tests, job vs escalate); before: 49 (T1415: job media + reply); before: 47 liaison fixture tests (T1414: 7 job tests, a transient-unit probe, a live tick) and eval 57 fixtures on opus (T1413: old brief 45/57 twice, new brief + context 55/57 twice); before: 25 liaison fixture tests + 25 orchestrator-pulse checks + 31 discord-bot tests, live ticks on #foro and #general

## When to use
Run, check, change or debug discord-liaison: the persistent agent that owns the conversation in the forum #foro
(Spanish replies, collab PRs, project registry) and answers @agents mentions in #general. Not for the bot's gateway, tags or approval jobs: guide `discord-bot`.

## The path we took
- Survey: discord-bot T348 (REST adapter, `sanitize.clean`, `RateLimiter`, fake Discord REST: reused); official
  `discord@claude-plugins-official` channel plugin (full tools on every message, resident session: rejected);
  sentinel-check pattern (cheap timer, `agent-run` only on need: copied).
- `discord-liaison-check.timer` (3 min) → `discord-liaison tick`: one REST poll of the forum's active threads; no new
  message = exit, 0 tokens. Same tick reads #general (`DISCORD_GENERAL_ID`, found once by name among the guild's
  text channels and stored in config.env) and keeps only messages that mention the bot user or its managed role
  (`mentions`, `mention_roles`; role = the guild role whose `tags.bot_id` is the bot); other #general traffic costs
  nothing. New ones → inbox + thread→project map, then `agent-run discord-liaison` under the daily
  run cap. The LLM run follows `discord-liaison/BRIEF.md` (inbox, post, map, pr, done).
- Modules (`discord-liaison/liaison/`): `watch.Watcher` (read-only poll), `registry.Registry` (`match`, `route`),
  `state.State` (cursor, inbox, threads, shown), `caps.Caps` (per-UTC-day caps, logged), `cli.App` (verbs).
  Architecture: `$AGENT_WORK/research/2026-10-27/T1409/architecture.md`.
- Registry `discord-liaison/projects.json`: one entry per project (repo, clone, match tags/title, rules, skills, `po`).
  `Registry.route()` is the one routing seam: `po` set → that project's threads go to its PO agent (T1410), else the
  liaison does the work. A repo not in the registry: reply "pendiente", `notify-owner`, nothing starts.
- Managers (T1515 P31): `po` = the project's own manager `po-<id>`; with top-level `"router": "po-discord"` the routing is
  code: `tick` → `Registry.dispatch` → `po-ask` before the run gate, the message leaves the liaison inbox, so a routed
  message wakes no triage. No project / a 2nd project named → the router. The triage keeps #general, projects without
  `po` and failed handoffs. Context map and SOLID: `$AGENT_WORK/research/2026-11-09/T1515/P31-architecture.md`;
  guide `product-owner-agents`. Rollback: drop `router` and set `po` back (one commit).
- The owner's ✅ (T1546-M2, owner 2026-11-10): the bot writes `discord-bot/state/approvals/<message>.json` and nudges;
  `run_tick` → `po.approvals` re-checks it (user = `DISCORD_OWNER_ID`, his ✅ in `reactors` on Discord, thread mapped to a
  project with a manager) and files one `po-ask --owner` item "the owner approved this message (✅): message <id>:
  "<first 200 chars>"" for that manager. `state/approved.json` keeps it to once per message; anyone else's ✅, a
  project without a manager or #general: nothing. A REST error or failed po-ask keeps the record for the next tick.
- Reply first (T1515 P40): no code ack (T1536): `po.handoff` posts nothing in the thread; the manager's first reply is
  the ack. The manager's first act is a one-line plan reply, then work, then the result. `discord-liaison-relay@<p>.path`
  (PathModified on `po-<p>/outbox/discord`, dot files ignored) runs `discord-liaison relay` on each outbox `mv`; the
  relay holds `state/relay.lock` and loops until the outbox is empty; the 3-min tick still relays as a fallback.
- Refusals (T1546 L1-L4): a reply that fails (Discord error, a thread its manager does not own, no `thread:`/text) moves to
  `outbox/discord/refused/` with `<name>.why` and a `refused reply:` line in the agent's REPORT.md; `po-status` prints refused N.
  An image over `LIAISON_UPLOAD_MAX` (10 MB) refuses the reply; a transient thread-lookup error (not 403/404) leaves it for the next relay.
- #general (owner, T1411): answer general questions on any topic, in Spanish, and do small creative requests there
  (concept art via `art` + `post --image`, short texts); send people to #foro only for coordination with other agents
  or follow-up on a project; never `map`/`pr` from #general (`BRIEF.md`).
- Images in (owner, T1411): the watcher keeps attachment metadata for png/jpg/jpeg/webp/gif on the Discord CDN
  (`LIAISON_CDN_PREFIXES`), ≤ 8 MB, ≤ 4 per message. Before a run, `tick` downloads them with a token-less session
  (no redirects, magic bytes checked) into `state/work/<msg>-<n>.<ext>`; `inbox` lists them as `images="…"`, the model
  reads them with Read; `tick` deletes `state/work/` when the run ends.
- The owner (T1411): `inbox` marks `owner="true"` when the author id equals `DISCORD_OWNER_ID` (the guild owner,
  stored by `discord-bot setup`); his requests are the owner's decisions.
- Worker first (owner, T1416: "it should only reach you if something is blocking him"): work or a missing tool is a
  `job`; `escalate <message> <blocker>` takes only `permission`, `owner`, `secret` or `attempts` (`liaison/routing.py`),
  any other reason is refused toward `job`. A failed worker run is retried once in the same runner, a lost runner or
  failed launch is requeued once (`attempt` in job.json); the second failure posts the note and escalates `attempts`.
- Escalations (owner, T1411): never "no puedo" / "lo decide el owner". When blocked the liaison reacts 👀,
  acks in Spanish and runs `escalate`, which writes `state/escalations/<utc>-<msg>.md` (channel, message, author,
  blocker, request, what it tried) and starts `orchestrator-pulse`; every `tick` starts it again while an open file is missing
  from the pulse snapshot (`~/agents/log/pulse-queue.json` key `escalations`). The pulse stays idle-only and logged; its
  turn begins `Discord escalation: <file>`. The orchestrator answers, then moves the file to `escalations/done/`; an
  open or done escalation of the same message is refused (KB/orchestrator.md "Pulse").
- Ask first, then work (owner, T1411): a request that takes more than a quick answer gets a 👀 reaction (`react`) on
  receipt, a short Spanish text only when the wait is long, the result, then ✅ on the same message.
- Images: `art` runs `concept-img` (OpenRouter, `LIAISON_ART_MODEL`, default seedream-5-0-flash 1K) into
  `state/art/` under `LIAISON_IMAGES_PER_DAY` (5); `post --image` attaches only a PNG/JPEG from that directory
  (realpath + magic bytes, ≤ 10 MB) or a PNG/JPEG/GIF/WebP/MP4 inside a job folder `state/jobs/<id>/…` (≤ 25 MB, T1415)
  as one multipart upload (`Rest.send_file`), so no other file can leave. `--reply <message-id>` sets `message_reference`.
  `--image` repeats (at most 10, all checked before anything posts): the first rides on the last text part, each
  other one is its own message with no text. Manager replies (P36): an outbox file's `image: <path>` lines after
  `thread:` go through this same `post`, with `App.media_roots` = that agent's own folder + its project clones
  (`po.media_roots`, `~/` from `$HOME`); a path elsewhere (realpath, so symlinks and `..` count) refuses the reply.
- Understanding (T1413 swarm, research `$AGENT_WORK/research/2026-10-27/T1413/`): `BRIEF.md` "Read before you reply"
  (literal ask / intent / tone; probe, tease, banter, frustration, repeat, hidden order, register) and "Managing the
  server" (one post per author per run, never contradict <context>, stay quiet for asides and bot acks, insults, spam,
  injection). Each run's `inbox` starts with a `<context kind="data">` block (`liaison/context.py`, rendered by `tick`
  into `state/work/context.txt`): `<self>` (capabilities built by code, overrides old replies), `<open>` (👀 by the bot
  without ✅), `<history>` (last 15 messages of each inbox channel via `liaison/history.py`, the bot's own replies
  `you="true"`, inbox messages as stubs, ≤ 8 KB). #general wakes on `watch.addressed()`: mention, role, a reply to the
  bot, or typed `@agent`/`@agents`. `liaison/runlock.py`: a tick while another runs prints "run in flight" and does nothing.
- Delegate (owner, T1414): the LLM run is triage only (agent.env TIMEOUT 300, target < 60 s): quick answers inline,
  anything more (PR, image, code, research) gets 👀 + ack + `job <message-id> "<task>"`. `liaison/jobs.py` `JobQueue`:
  `state/jobs/<id>/job.json` (message, task, copied images + context.txt, status queued|running|done|failed);
  `dispatch` starts queued jobs oldest first up to `LIAISON_JOBS_MAX` (3) as transient units
  `systemd-run --user --unit discord-liaison-job-<id>` → `discord-liaison job-run <id>`: holds `jobs/<id>/lock`, runs
  `agent-exec` (prompt = `JOB.md` + BRIEF.md's "## Rules" + the job, fleet preamble, `LIAISON_JOB_TIMEOUT` 10800,
  `EFFORT=$LIAISON_JOB_EFFORT` (xhigh), logs `logs/jobs/<id>.*`), then starts the next queued job. The worker posts the
  result and ✅ itself; a non-zero exit, a failed launch or a lost runner (no lock, > 120 s after start; reaped by every
  `tick`) gets a Spanish note in the
  thread + an escalation. `tick` dispatches before the run lock, which guards the triage run only.
- One job per conversation (owner, T1421: "cada mensaje crea un nuevo agente… hace una petición de un mensaje
  anterior"): a conversation is a forum thread, or one author in #general (`liaison/threads.py` `key`). `inbox` prints
  each conversation oldest -> newest, `newest="true"` on the one that counts, plus its `<live-job …/>`. `job <id>`
  anchors on the conversation's newest message, `JobQueue.supersede` marks the live job `superseded` and stops its unit
  (`systemctl --user stop`, `LIAISON_JOB_STOP` in tests), the new job carries every message (`messages`) and images.
  `done` records `through` on a kept live job and takes 👀 off messages no job or escalation covers. A worker's `post`
  (`LIAISON_JOB` set by `job-run`) re-reads the thread: a newer requester/owner message after `through` waits up to
  `LIAISON_STALE_WAIT` (90 s) for the triage, then refuses (exit 4, job ends `stale`); `job-run` ✅ all covered messages.
- Wake on arrival (T1421): the bot (liaison mode) writes `discord-bot/state/liaison.nudge` on every guild message (its
  only writable dir); `discord-liaison-wake.path` (PathModified) starts `discord-liaison-wake.service` = `wake`:
  `check` (inbox + 👀 on every new human message at once) per nudge, one `tick --wait` once the file is
  `LIAISON_DEBOUNCE` (20) s old, again if nudged during the tick (`liaison/wake.py`). The 3-min timer stays as fallback.
  Design: `$AGENT_WORK/research/2026-10-27/T1421/architecture.md`.
- Eval (`discord-liaison/eval/`): `run_eval.py <brief> --model opus --context liaison|none --out r.jsonl` (tool-less
  `claude -p`, one JSON decision per fixture, ~$0.04 and ~5 s per opus call, `--show` prints prompts) and
  `score.py r.jsonl` (deterministic regex/field checks, per-class %). Change the brief → run both, twice each.
- Split with discord-bot: `DISCORD_FORUM_REPLIES=liaison` in config.env. The bot only tags posts and nudges; it no longer
  sends its English ACK or tool-less answers, and since T1546-M2 runs no approved jobs (his ✅ goes to the manager). Its sandbox is unchanged.

## Exact commands
```bash
discord-liaison status              # inbox, mapped threads, runs/PRs used today, projects and their route
discord-liaison tick --dry-run      # read #foro, write REPORT.md, post nothing, keep state
discord-liaison wake                # what the path unit runs on a bot nudge (check + 👀, 20 s debounce, tick)
discord-liaison inbox | done        # what the LLM run sees; done clears only what inbox showed
discord-liaison post <thread> [--image <file>] [--reply <msg>] <texto…>   # forum threads or #general, sanitized; LIAISON_DRY_RUN=1 prints
discord-liaison react <thread> <message-id> 👀|✅       # ack on receipt, done when the result is posted
discord-liaison art "<prompt>"     # concept-img into state/art/, prints the path; daily image cap
discord-liaison escalate <message-id> <permission|owner|secret|attempts> "<asked; tried>"   # -> state/escalations/, pulses the orchestrator
discord-liaison map <thread> <project> | pr <project>   # pr = registry + route + daily PR cap gate
discord-liaison job <message-id> "<task>"   # triage: hand a work request to a background worker (queued over the cap)
discord-liaison job-run <id>                # the worker's runner (started by the transient unit; not by hand)
journalctl --user -u 'discord-liaison-job-*' -n 20; ls ~/agents/discord-liaison/state/jobs/
discord-liaison manager <project-id> # po-<id> manager for a registered project (T1515 P31)
discord-liaison test                # fixture tests (also bin/tests/discord-liaison.test.sh)
journalctl --user -u discord-liaison-check -n 20; tail ~/agents/discord-liaison/logs/caps.log
```
Caps: `LIAISON_RUNS_PER_DAY` (100000, owner: no caps), `LIAISON_PRS_PER_DAY` (100000, owner 2026-10-28; only guards a
runaway loop), `LIAISON_IMAGES_PER_DAY` (5), `LIAISON_JOBS_MAX` (3), `LIAISON_JOB_TIMEOUT` (10800),
`LIAISON_JOB_EFFORT` (xhigh, owner fleet rule 2026-10-30; 11-01: max wastes tokens) in `discord-liaison/agent.env`.

## Pitfalls (measured)
- The first tick with an empty cursor only seeds it: old history never wakes the LLM (#foro had 2 threads of old
  messages on 2026-10-27). A new thread created later is read whole.
- `inbox` then `done` is two-phase on purpose: messages that arrive during a run stay for the next tick.
- The unit runs `agent-run` inline, so a 3-min timer never overlaps a run; TimeoutStartSec 2100 > triage TIMEOUT 300.
- Jobs cannot use `agent-run`: its lock is one per agent dir, so a second job would exit "already running". The runner
  calls `agent-exec` directly. A plain `&` child dies with the oneshot check service; the transient unit does not.
- `state/work/` is deleted when the triage run ends: `job` copies the message's images and context.txt into the job dir.
- Jobs take caps concurrently: `Caps.take` re-reads caps.json under an flock; `art` names files `<stamp>-<pid>.png`.
- The first tick that knows #general seeds its cursor at the latest message: no mention older than the deploy is
  answered (2026-10-27: the 08:25 joke mention was answered by hand before the deploy).
- Discord renders a mention as `<@bot-id>` or `<@&role-id>`; `@agents` typed by a member is usually the bot's
  managed role, not the user, so both count. The watcher rewrites both to `@agents` before the LLM sees them.
- Read rejects animated GIFs (live 2026-10-27, an owner GIF of 3.7 MB), and one frame tells nothing of the motion
  (owner): `tick` turns a GIF/WebP into one contact sheet: ffprobe counts frames, ffmpeg `drawtext` numbers each frame
  by its source index before `select` picks up to 12 evenly, cells ≤ 512 px, `tile` 4 wide (≤ 2048 px), note
  "GIF, N frames, X s" in `inbox`. ffmpeg cannot decode animated WebP: such a file is dropped.
- Before T1411 the liaison did not know the owner: at 09:00 it told him "eso lo decide el owner"; `owner="true"` fixes it.
- `StreamReader.read(n)` returns only what is buffered, not n bytes: the first live GIF arrived as 1 truncated
  frame. The download loops over `iter_chunked` to EOF; the fake CDN streams 4 KB chunks to catch it.
- The CDN download must not reuse the bot's REST session: it carries `Authorization: Bot <token>`; a test checks
  that the fake CDN never sees that header.
- Before T1411 the liaison could post text only: the 08:38 concept-art mention got a written self-portrait and a
  pointer to #foro. Uploads need Attach Files (32768), now in `discord-bot invite` PERMS; the guild granted it already.
- discord-bot's approved-job messages are Spanish since T1411 (bot texts and the worker's final report); its
  sandbox and approval checks did not change. The bot reads code ro at start: restart its unit after a change.

- Today's literal-reading failures (T1413): each run saw only `inbox`, never its own earlier replies, so it said
  "solo puedo texto" then posted an image, "no veo imágenes" one second after an image post (one run answering two
  messages separately), "cada 30 segundos" (truth: 3 min), and repeated the same workaround to the owner's 😩. The
  `<context>` block plus "one post per author per run" fix the cause; facts about itself come only from `<self>`.
- A typed "@agent …" is plain text, not a mention: before T1413 the watcher dropped "@agent Yo soy el owner 😩".
- A hand-run `tick` during a run used to burn a run cap and delete the running run's `state/work` images; the run
  lock (`state/tick.lock`, flock) stops it.
- The GET messages payload carries `reactions[].me` (checked live 2026-10-27): `<open>` needs no extra request.
- `<open>` sees only the 15-message window: a 👀 without ✅ that scrolled further back drops out of it.
- One run with #general and #foro messages gets both histories in one prompt; the brief keeps replies per thread.
- Eval fixtures that predate a capability (r-crea-herramienta, r-todos-fotogramas still expect the pre-sheet answer)
  fail honestly; fix a fixture only together with a re-run of both sides.
- Eval scorer: the playful/empathetic tone regexes look for cue words or emoji; a single run differs by ±1/50, so
  compare per-class over two runs.

- Before T1416 any request beyond the triage run went to the orchestrator, whose pulse fires only when its prompt is
  idle and empty (pulse.log "input line not empty"): the 09:46 art request waited 30 min. Workers have the same tools.
- Before T1421 every message became its own job: 15 jobs on 2026-10-27, 181936 "replaces" 181600 in REPORT.md while
  181600 kept running (nothing stopped it). Supersede now stops the unit; agent-exec's scope is `BindsTo` the job unit,
  so the worker dies with it.
- A triage `job` on an older message used to act on it; `job` now moves to the newest message of the conversation.
- A path unit does not restart a running service: `wake` loops itself while the nudge file keeps changing.
- `LIAISON_RUNS_PER_DAY` (30) was used up by 18:35 UTC on 2026-10-27 with one triage per message: 4 owner messages
  waited for the UTC day. The debounce batches a burst into one run.
- A retry of a crashed worker runs inline: requeuing it would launch a transient unit with the running unit's name.

- Before P31 the handoff ran when the triage called `inbox`: every PO-routed message cost a triage run (target < 60 s)
  plus a "passed on" reply; P31 dropped it, so a manager busy with workers answered only at the end (P40 measured
  2026-11-09/10, 10 requests: Discord → hand-off median 22 s (20 s debounce), run start → first outbox 23–1205 s
  (median 102 s), outbox → Discord 5–164 s (median 52 s, the 3-min tick), queue behind a busy run up to 1018 s).
- Handed messages keep their 👀 (no `done` runs for them). Images (P32): `po.deliver` downloads the message's images into
  `state/work`, passes them as `po-ask --image` (copied into `po-<id>/state/images/`, `images:` in the front matter) and
  deletes its own copies; the router forwards them with `--image` to one manager only. Before P32 handoff passed text only.
- Postmortem T1482 (119 jobs, 2026-10-27..11-04, doc pruned with the T1482 drop folder by T1505): 82 done, 36 superseded, 1 lost;
  median 16 min, p90 47 min; 5 escalations, none after 10-28. Superseded jobs had run 320 min (12 over 5 min, one 115 min)
  and the next job did not know them: `JOB.md` now sends it to the predecessor's folder and branch. Process lessons
  (every ask numbered, one subject first, sound by default, facts from the group's sources) live in `JOB.md` "Lessons";
  craft lessons stayed in their guides (`hd2d-sprite-character`, `web-audio-sound-kit`). A new lesson: a `JOB.md` line
  plus an anchor in `tests/test_lessons.py`.

## Links
- Code: `~/agents/discord-liaison/` (`liaison/`, `projects.json`, `BRIEF.md`, `JOB.md`, `agent.env`), CLI `~/agents/bin/discord-liaison`,
  units `~/agents/units/discord-liaison-check.{service,timer}`, `discord-liaison-wake.{path,service}` (T1421)
- Tests: `~/agents/discord-liaison/tests/` via `discord-liaison test` (`test_context.py`, `test_manage.py` T1413, `test_jobs.py` T1414, `test_routing.py` T1416, `test_threads.py` T1421); eval `discord-liaison/eval/` (57 fixtures, 7 held out)
- Design: `$AGENT_WORK/research/2026-10-27/T1409/architecture.md`; bot: guide `discord-bot`
