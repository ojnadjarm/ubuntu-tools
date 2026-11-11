# Compact an idle Claude session automatically (before the 1 h prompt cache expires)

Ticket: T1657 · Last verified: 2026-11-11 by `bin/tests/idle-compact.test.sh` (28 checks) and a dry run on the live registry

## When to use
A long-lived interactive Claude session in tmux (the orchestrator) finished its work and sits idle: compact it so the
next prompt does not re-pay the whole context. Not for headless runs (`adapters/claude/run` never resumes a session).

## The path we took
- Exists: Claude Code has native idle compaction (`idleCompaction`, default on, v2.1.290+; fires at 90 % of the 1 h TTL
  when context >= `CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS`, default 200000, floor 100000; transcript trigger `"idle"`).
  Measured: it never fired here (0 `"trigger":"idle"` boundaries in the orchestrator transcripts; 2026-11-10 21:34 the
  session sat 519 min at 240 k and the next prompt rewrote 239 k uncached). So a fleet timer types `/compact` instead.
- Idle signal (cheapest reliable): registry `~/.claude/sessions/<pid>.json` `status` idle, and idle minutes from the
  newest of its `statusUpdatedAt` and the mtime of the transcript, its subagents and workflows. No hook needed.
- Gates: registry idle, >= `IDLE_COMPACT_AFTER` min (45), context >= `IDLE_COMPACT_MIN_TOKENS` (100000), no compaction
  boundary after the newest request, pane runs that claude pid (pane_pid ancestor + argv), not in copy mode, no turn,
  no `◯` agent row, empty prompt box (`orchlib.sh` probes, ghost text ignored), pane unchanged over 2 s.
- Trigger: `/compact` + Enter via `tmux send-keys`; the session's own Compact instructions apply. Read-back: waits up to
  240 s for the new `compact_boundary`, logs `before=` and `after=` (postTokens).
- Modules: `decide` (pure verdict), `sessions` (registry), `facts` (transcript tokens, compacted flag, last write),
  `pane_reason` (pane probes), `status` (read-back). Config via env or `config.env`; nothing else is written.
- Threshold 100000: break-even measured at about 36 k (opus prices as multiples of input: cache read 0.1, 1 h write 2,
  output 5; summary 3.4 k median and post size 16.4 k over 29 compactions; 63 % of 217 idle gaps >= 45 min ran past
  60 min). 100 k is Claude Code's own floor for the same feature: below it the saving is small and the working detail lost.

## Exact commands
```bash
idle-compact                 # dry run: "would: <session> idle <m> min, <tokens> tokens → compact" or "skip: <why>"
idle-compact status          # enabled, timer, firings, tokens saved, last firing
bash ~/agents/bin/tests/idle-compact.test.sh
# off: IDLE_COMPACT=off in ~/.config/pc-harness/config.env (also IDLE_COMPACT_AFTER, IDLE_COMPACT_MIN_TOKENS)
tail "$AGENT_WORK/idle-compact/idle-compact.log"
```

## Pitfalls (measured)
- 81 of 217 idle gaps (37 %) ended between 45 and 60 min, inside the TTL: a firing there costs about 24 k
  input-equivalents for nothing; the 63 % past 60 min pay for it (break-even above).
- Keep `IDLE_COMPACT_AFTER` under 60: after the TTL the compaction itself reads the context uncached.
- Typed text from the phone (Remote Control) is not in the pane; the registry `busy` status and the 2 s re-check cover a
  prompt that is being sent.
- Test fixture: `tmux -L <socket>` via `IDLE_COMPACT_TMUX_SOCKET`; a fake `claude` (`exec -a claude bash`) registers itself
  with its `TMUX_PANE` and appends a boundary on `/compact`.

## Links
- Code: `~/agents/bin/idle-compact`, `~/agents/bin/orchlib.sh`, `~/agents/units/idle-compact.{service,timer}`
- Tests: `bin/tests/idle-compact.test.sh` (private tmux server, fake CLAUDE_DIR, stub systemctl)
- Brief: `~/agent-work/briefs/T1657-idle-compact.md`
