# Discord liaison: the agent that answers the #foro forum and @agents in #general, and turns requests into PRs

Ticket: T1409, T1411 · Last verified: 2026-10-27 by 25 liaison fixture tests + 25 orchestrator-pulse checks + 31 discord-bot tests, live ticks on #foro and #general

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
- #general (owner, T1411): answer general questions on any topic, in Spanish, and do small creative requests there
  (concept art via `art` + `post --image`, short texts); send people to #foro only for coordination with other agents
  or follow-up on a project; never `map`/`pr` from #general (`BRIEF.md`).
- Images in (owner, T1411): the watcher keeps attachment metadata for png/jpg/jpeg/webp/gif on the Discord CDN
  (`LIAISON_CDN_PREFIXES`), ≤ 8 MB, ≤ 4 per message. Before a run, `tick` downloads them with a token-less session
  (no redirects, magic bytes checked) into `state/work/<msg>-<n>.<ext>`; `inbox` lists them as `images="…"`, the model
  reads them with Read; `tick` deletes `state/work/` when the run ends.
- The owner (T1411): `inbox` marks `owner="true"` when the author id equals `DISCORD_OWNER_ID` (the guild owner,
  stored by `discord-bot setup`); his requests are the owner's decisions.
- Escalations (owner, T1411): never "no puedo" / "lo decide el owner". Beyond its tools or rules the liaison reacts 👀,
  acks in Spanish and runs `escalate`, which writes `state/escalations/<utc>-<msg>.md` (channel, message, author,
  request, what it tried) and starts `orchestrator-pulse`; every `tick` starts it again while an open file is missing
  from the pulse snapshot (`~/agents/log/pulse-queue.json` key `escalations`). The pulse stays idle-only and logged; its
  turn begins `Discord escalation: <file>`. The orchestrator answers, then moves the file to `escalations/done/`; an
  open or done escalation of the same message is refused (KB/orchestrator.md "Pulse").
- Ask first, then work (owner, T1411): a request that takes more than a quick answer gets a 👀 reaction (`react`) on
  receipt, a short Spanish text only when the wait is long, the result, then ✅ on the same message.
- Images: `art` runs `concept-img` (OpenRouter, `LIAISON_ART_MODEL`, default seedream-5-0-flash 1K) into
  `state/art/` under `LIAISON_IMAGES_PER_DAY` (5); `post --image` attaches only a PNG/JPEG from that directory
  (realpath + magic bytes, ≤ 10 MB) as one multipart upload (`Rest.send_file`), so no other file can leave.
- Split with discord-bot: `DISCORD_FORUM_REPLIES=liaison` in config.env. The bot still tags posts and runs the owner's
  approved jobs; it no longer sends its English ACK or tool-less answers. Its sandbox is unchanged.

## Exact commands
```bash
discord-liaison status              # inbox, mapped threads, runs/PRs used today, projects and their route
discord-liaison tick --dry-run      # read #foro, write REPORT.md, post nothing, keep state
discord-liaison inbox | done        # what the LLM run sees; done clears only what inbox showed
discord-liaison post <thread> [--image <png>] <texto…>   # forum threads or #general, sanitized; LIAISON_DRY_RUN=1 prints
discord-liaison react <thread> <message-id> 👀|✅       # ack on receipt, done when the result is posted
discord-liaison art "<prompt>"     # concept-img into state/art/, prints the path; daily image cap
discord-liaison escalate <message-id> "<asked; tried>"   # -> state/escalations/, pulses the orchestrator
discord-liaison map <thread> <project> | pr <project>   # pr = registry + route + daily PR cap gate
discord-liaison test                # fixture tests (also bin/tests/discord-liaison.test.sh)
journalctl --user -u discord-liaison-check -n 20; tail ~/agents/discord-liaison/logs/caps.log
```
Caps: `LIAISON_RUNS_PER_DAY` (30), `LIAISON_PRS_PER_DAY` (3), `LIAISON_IMAGES_PER_DAY` (5) in `discord-liaison/agent.env`.

## Pitfalls (measured)
- The first tick with an empty cursor only seeds it: old history never wakes the LLM (#foro had 2 threads of old
  messages on 2026-10-27). A new thread created later is read whole.
- `inbox` then `done` is two-phase on purpose: messages that arrive during a run stay for the next tick.
- The unit runs `agent-run` inline, so a 3-min timer never overlaps a run; TimeoutStartSec 2100 > agent TIMEOUT 1800.
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

## Links
- Code: `~/agents/discord-liaison/` (`liaison/`, `projects.json`, `BRIEF.md`, `agent.env`), CLI `~/agents/bin/discord-liaison`,
  units `~/agents/units/discord-liaison-check.{service,timer}`
- Tests: `~/agents/discord-liaison/tests/` via `discord-liaison test`
- Design: `$AGENT_WORK/research/2026-10-27/T1409/architecture.md`; bot: guide `discord-bot`
