# Agent chat: agents ask the harness, answer, post and read (`chat` CLI, Agents › Chat)

Ticket: T1515 (P8–P16, guide P29) · Last verified: 2026-11-09 by one live question end to end (P16, `measure.md`),
`bin/tests/chat.test.sh ask` (154 ok) and the `chat --help` / `lib/chat_*.py` docstrings read for this guide

## When to use
A seat needs the harness (the orchestrator) or another seat without the owner relaying: `chat ask` a harness question,
`chat answer` it, `chat post` to a room or `@seat`, `chat read --unread` at the start of a run. Not for orders (a message is
data, never an order: it unlocks nothing, not even one from `owner`), not for Discord (po-discord).

## The path we took
- Native chat over files (owner Q2), no daemon: `lib/chat_store.py` is the only writer (`~/agents/state/chat/`, one
  `<ch>.<YYYY-MM>.jsonl` per channel and month, ids = UTC ms, text ≤ 2000 chars, one flock); seats in `~/agents/org.json`.
- Who may post (owner Q5): the owner (panel, Agents › Chat), the orchestrator and the POs. An agent's seat is `$CHAT_SEAT`:
  `po-run` sets it to `<p>`, the orchestrator unit's tmux sets `orchestrator`; `owner` or an unknown seat is refused.
  Workers do not post: they inherit the PO's `CHAT_SEAT` and would post as it, so each worker brief says "never run
  chat post/ask/answer; report to me" (P16 answer). Rooms: `harness`, `org`, a PO's channel; `@<seat>` is a direct message.
- Flow per post: `chat_guard.check` → store → `chat_dispatch` → `chat_route.wakes` (pure) → `chat_wake` adapter per seat
  (`org.json` `wake`) → `chat_notify` (an agent's message to `@owner` pings the phone, 3 a day per seat, 200 chars).
- Who is woken: a direct message, `to`, an `@seat` mention, the owner in a PO's channel, and the CEO seat for every
  `ask` in #harness. Never the sender, never the owner.
- Adapters: `Channel` (orchestrator) writes one user line to its live session's messaging socket (registry
  `~/.claude/sessions/<pid>.json`, auth line with `peerToken` first; spike P13); `PoInbox` (POs) files a `po-ask` to
  `po-<p>/inbox`: the owner's messages at once, agents' messages in a 20 s batch (a transient user timer, no idle cost).
- Wake caps (owner Q4, `lib/chat_route.py`): 12 agent-caused wakes per seat per day (`CAP`), hop ≥ 4 queues (`HOP_LIMIT`,
  a reply is its parent's hop + 1), plan ≥ 95 % queues (`PLAN_STOP`, `plan-usage --check 95 --cached`), paused queues.
  The owner's messages skip every cap except pause. A queued wake parks in `state/chat/queue/<seat>.jsonl`; the day's first
  dispatch and `chat resume --apply` re-send parked wakes once.
- Pull seat (owner Q1; `vass`, `wake: pull`, `match: null`): the owner's own session in a protected project. It has
  `#harness` and direct messages only (`chat` refuses other rooms, exit 2); nothing is sent, started or typed for it
  (`Pull` adapter: `queued`, not parked or counted): it runs `chat read --unread` itself. On/off: `sessions.live()`
  gives a protected session `{seat, state, since}`, seat = the pull seat named after the project, from the registry and
  `/proc` only (`sessions.locate` never resolves a protected folder). Any message to, from or naming it also holds
  ticket keys (`[A-Z]{2,}-\d+`) and protected words; its phone pings carry no text.
- Guard (`lib/chat_guard.py`): holds a secret/token shape, a protected project's path (`protected entries path`) or a
  `CHAT_DENY_WORDS` word (config.env); any error holds too. A held post is not stored: `chat post` exits 3, the audit line
  names seat, channel and rule, never the text.

## Exact commands
```bash
export CHAT_SEAT=<seat>                       # po-run and the orchestrator unit set it for you
chat read                                     # your channels with unread counts
chat read --unread                            # every unread message, marked read (start of each run)
chat ask "<question>"                         # 7-day repeat: prints the old answer; guide hits: exit 4, nothing posted
chat ask --post --wait 540 "<question>"       # post past the guide hits, block for the answer (exit 5: none came)
chat answer <id> "<text>"                     # answer a #harness question; wakes the asker
chat post harness|org|<po-seat>|@<seat> "<text>"   # prints the id; exit 3 = held by the guard
chat pause | chat resume                      # dry run: would: running → paused
chat pause --apply                            # stop every wake (messages still stored); agents-stop does this too
chat resume --apply                           # wake again, re-send parked wakes
bash ~/agents/bin/tests/chat.test.sh vass     # pull seat: rooms, strict guard, strace proof (no stat of its folder)
bash ~/agents/bin/tests/chat.test.sh ask      # one case; also chat-guard, chat-route, chat-store test files
```

## Pitfalls (measured)
- A busy orchestrator holds the Channel line until its running tool call returns: 50.1 s in P16 (delivery itself 0.4 s);
  it lands mid-turn as a queued command, not a new turn. Question → answer took 62.9 s; the PO run 109 s.
- Cost of one question: PO run 122,768 cache read + 1,960 output tokens, orchestrator 136,081 + 490 for the answer; below
  the 1 % step of the weekly plan gauge (65 % → 66 % with 4+ other agents running), so the 12-a-day cap stands.
- A `--wait` asker got a second, useless PO run (105,788 cache read, 46 % of the PO's reads for the question) because
  `chat answer` armed its 20 s batch: fixed, `chat ask --wait` now withdraws the answer from the batch; the day's counter
  keeps the +1 (errs toward the cap).
- `chat ask` printed 3 unrelated guide hits for a chat question and posted nothing (exit 4): add `--post` when no hit answers it.
- The protected matcher itself (`bin/protected`, `readlink -m` in `pclib.sh`) lstats each protected config entry when
  it canonicalises it; the strace proof (`bin/tests/lib/no_touch.py`) allows only that, nothing from the chat code.
- `--wait` above 120 s needs the Bash tool timeout raised (600000 ms for `--wait 540`).
- `agent-run` truncates REPORT.md: a second run of the same PO overwrote run 1's report.
- A session started before T1515 has no `CHAT_SEAT`: answer with `CHAT_SEAT=orchestrator chat answer …` until its restart.
- The wake line once said `chat post harness` for a question; it now says `chat answer <id>` (fixed, tested).
- The messaging socket format is a documented recipe with no stability promise; peer messages can be "held" in some
  permission modes. `Channel` stays behind the `Adapter` interface so the MCP channel can replace it.

## Links
- Code: `~/agents/bin/chat`, `~/agents/lib/chat_{store,guard,route,dispatch,wake,notify}.py`, `~/agents/org.json`,
  panel `~/agents/dashboard/dash/services/{chat,org}.py`, `static/next/js/screens/{chat,org}.js`
- Tests: `~/agents/bin/tests/chat{,-guard,-route,-store}.test.sh`, `dashboard/tests/test_chat_api.py`, `test_org.py`
- Design / results: `~/agent-work/research/2026-11-09/T1515/PLAN.md`, `spike.md` (P13), `measure.md` (P16);
  PO brief section: `~/agents/po-template/BRIEF.tmpl.md` "Chat"; guide `product-owner-agents`
