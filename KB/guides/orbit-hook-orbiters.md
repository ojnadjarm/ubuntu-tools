# Show running agents as orbiters on the Eye (automatic hook, instant push, sweep)

Ticket: T58, T68, T73, T74-F14, T90, T379, T391, T396 · Last verified: 2026-10-20 (T846) by constants in `bin/orbit-hook`, hook wiring in `~/.claude/settings.json`, `sentinel-check.timer` 15 min, page `CROWD_MS`/`CROWD_MIN_MS`; 2026-10-19 (T493) by `bin/tests/orbit-hook.test.py` 43/43 and Dark Eye `remote-orbiters`/`orbiters` tests (8/8)

## When to use
- An agent does not appear on the Eye, appears twice, shows the wrong label, or vanishes while still working.
- Hooking anything else to subagent start/stop (same pattern: Claude Code `SubagentStart`/`SubagentStop` hooks).
- Not for spawning: orbiters are automatic. **Never hand-send `eye status <id> working` for an agent**: it doubles the orbiter.
  Start the Agent call's description with the ticket ("T58 …"); that is the label (24 chars max).
- The dashboard's Agents list has its own liveness rule: see `agents-list-liveness.md`.

## The path we took
- `~/.claude/settings.json` runs `$HOME/agents/bin/orbit-hook start|stop` (timeout 5 s) on `SubagentStart`/`SubagentStop`.
- `orbit-hook` (272 lines, Python stdlib): POSTs `{id: agent_id[:6], state, label}` to the body's `/bridge/status`
  (`127.0.0.1:<port>` and `x-dark-eye-key` from `~/.config/dark-eye/config.json`), timeout 1.5 s, and never fails: a dead Eye is a no-op.
- Label (T391): the Agent call's `description` read from the parent transcript (`spawn_desc()`, the same read as the guides
  below, polled `SPAWN_WAIT_S` 0.5 s, 0 in a workflow session), cut to 24 chars. The in-hook `meta.json` wait is gone: in CLI 2.1.300
  the meta lands only after the hook returns. With no Agent call (workflow agents), the hook lights the orbiter with `agent_type`
  at once, saves the claim, and spawns a detached `orbit-hook relabel`
  (own session, stdio closed) that polls up to `RELABEL_WAIT_S` 30 s and re-posts `working` with the label, only if the
  claim is still there (so an agent that already stopped is never re-lit). A re-post of the same id only renames the orbiter
  on the page (no chime; the renderer ignores labels) (T73).
- Claims file `$XDG_RUNTIME_DIR/dark-eye/orbit-claims.json` (flock'd): orbiter id → transcript path, start time, agent id.
- Sweep: `sentinel-check` runs `orbit-hook sweep` every 15 min (every start/stop hook sweeps too). An orbiter goes out when its
  transcript is unmoved for `ORBIT_STALE_S` (1800 s), or at once when an end signal covers it (T90, `stopped()`): a task
  notification or `TaskStop` of its own task id or its workflow run's (the agent began before it and wrote nothing > 60 s after),
  its journal `result`/`failed` row, or a later `started` row with its label whose agent began after it went silent (a resumed run).
  The signals come from the shared stdlib module `~/agents/lib/agent_ends.py` (same parser as the dashboard); the parent transcript
  is read incrementally, offsets kept in `$XDG_RUNTIME_DIR/dark-eye/orbit-scans.json` (first read of a 24 MB transcript 0.12 s, then ~1 ms).
- TaskStop fast path: the PostToolUse audit hook (`adapters/claude/hooks/audit-log.py`) spawns a detached `orbit-hook taskstop`
  on every `TaskStop`; it records the stop at once (the transcript line may not be written yet) and sweeps. Stop to gone: 0.11–0.16 s. A transcript not found yet is re-resolved each sweep, and dropped only after 12 h (the Eye's own expiry).
- One resolver `subagent_file()` for start, label and sweep: `<session>/subagents/agent-<id>.*`, then any depth under
  `subagents/` (workflow agents live in `subagents/workflows/wf_*/`), then, for the sweep only, a glob over all projects
  (7.6 ms CPU per call vs 0.4 ms for the session glob, measured 2026-09-24; start and relabel poll at 20 Hz so they skip it).
- Guides at start (T379): `start` also prints `hookSpecificOutput.additionalContext` with the top 3 `guide` hits (2 lines each,
  ~230 tokens) for the Agent call's `description` (T396: plus the owner-decisions digest, ≤ 300 tokens, of each project the description names; `decisions-ledger.md`), read from the parent transcript: the oldest pending `Agent` tool_use not yet
  taken (same `subagent_type` first; taken ids in `$XDG_RUNTIME_DIR/dark-eye/orbit-spawns.json`), polled
  0.5 s (0 in a workflow session) without a lock; only the take of a row (read, pick, save of orbit-spawns.json) holds the claims
  lock (T493: 6 parallel starts 3.32–3.51 s → 0.86–1.03 s at load 34–47, `evidence/T493/`). Printed before the Eye POST, so a dead Eye still hands the guides over. No hit, no output.
- Page side (T58): the body pushes the orbiter list over the page's existing long-poll (`reply.orbiters` in
  `remote-www/index.html`); the 20 s `/remote/orbiters` poll (`CROWD_MS`) stays as fallback; every agent stays at least
  `CROWD_MIN_MS` 6 s and leaves with the done chime. The body replays working orbiters after a renderer respawn.

## Exact commands
```bash
eye status                                          # the Eye's current orbiters (JSON)
python3 ~/agents/bin/tests/orbit-hook.test.py       # 43 checks, temp HOME/XDG + fake Eye; selftest proves the real one unreachable
~/agents/bin/orbit-hook sweep </dev/null            # the sweep by hand (what sentinel-check does)
cat "$XDG_RUNTIME_DIR/dark-eye/orbit-claims.json"   # what the hook thinks is lit
cd ~/the-dark-eye/body && node --test test/remote-orbiters.test.js test/orbiters.test.js
```

## Pitfalls (measured)
- Page polled every 20 s: time from `eye status` to on screen p50 16.2 s / p95 17.7 s, and an 8 s agent never showed.
  Push over the long-poll: p50 113 ms / p95 135 ms (12 trials, sandbox body, 60 fps kept). A 1 s agent stayed 7.6 s.
- Label race (T58): the first hook read the *previous* spawn's description from the parent transcript, so agent
  `a84d58` showed as "Test agent: machine haik". Fixed then by reading the agent's own `meta.json`; since T391 the label is the Agent call's description (above).
- Workflow agents (T68): the resolver only looked one folder deep, so the sweep measured idle from the start and put every
  workflow agent out at 30 min while it was still writing, labelled "worker". The old script fails 4 of the 11 checks.
- Workflow agents showed "worker" (T72, fixed T73): their `meta.json` landed 2.10–2.15 s after the transcript's first line
  (27 of 34 under 3 s, none under 2.05 s), i.e. just after the old 2.0 s wait ended. The workflow runtime evidently writes it only
  **after** the hook returns (the lag tracked the wait), so a longer in-hook wait would only delay it; hence the detached relabel, which also cuts
  the time the hook holds a workflow agent from 2.0 s to 0.5 s. The old script fails 2 of the 15 checks.
- Workflow agents still held 0.5 s for nothing (T74-F14): in 60 recent workflow agents the meta landed 0.56–0.70 s after the
  first line, never inside the hook. A `subagents/workflows/` folder now skips the wait: the hook returns in 0.06 s instead of 0.57 s.
  A plain agent in such a session (41 of 663) is lit as `agent_type` and renamed by relabel when its meta lands (about 0.1 s, estimate).
  The old script fails 2 of the 18 checks.
- Plain agents never got their label in the hook (T391, CLI 2.1.300): the 0.5 s meta wait always timed out, so every plain agent
  was lit as `agent_type`, held 0.5 s for nothing and renamed later by relabel. Fixture bench, 20 starts each, 2 runs: hook p50
  0.61–0.65 s before, 0.13–0.17 s after, label right at once. The old script fails 2 of the 37 checks.
- Stopped agents stayed lit (T90, 2026-09-25): `TaskStop` fires no `SubagentStop`, so a stopped T87 build (`ab28de`) kept its
  orbiter until the idle sweep: 30 min idle + up to 15 min to the next sweep, the owner saw two "BUILD" orbiters. Now 0.11–0.16 s via the
  TaskStop hook, else the next sweep (≤ 15 min). Dry run on the live claims: `ab28de` stopped, the 2 live agents lit. The old script fails 4 of the 29 checks.
- A resumed run keeps its run id: a stop of the old task must not end the new run's agents, so a stop only covers agents that
  began before it (same-second stamps count as before; tests date the stop 30 s back).
- Put back live orbiters after a fix by re-running the start post; restarting dark-eye is the owner's call, never an agent's.
- The two hook-time checks (< 0.35 s) are load-sensitive: at load 23–26 they failed at 0.40–0.47 s, then passed 41/41 on a re-run (T487).
- Tests must not reach the real Eye: the suite runs with a temporary HOME/XDG config pointing at a fake bridge.

## Links
- Code: `~/agents/bin/orbit-hook`, `~/agents/lib/agent_ends.py` (end signals), `~/agents/adapters/claude/hooks/audit-log.py` (TaskStop trigger), `~/agents/bin/sentinel-check` (sweep), hook config `~/.claude/settings.json`,
  page `~/the-dark-eye/body/src/remote-www/index.html` (`crowdSet`, `CROWD_MIN_MS`), body `body/src/main.js` + `body/src/orbiters.js`
- Tests: `~/agents/bin/tests/orbit-hook.test.py`, `~/the-dark-eye/body/test/{remote-orbiters,orbiters}.test.js`
- Briefs: `~/agent-work/briefs/T58-orbiters-instant.md`, `T68-orbit-sweep-workflow-agents.md` · backups `~/agents/backups/T58/`
- Docs: `KB/toolbox.md` (orbiters paragraph), `KB/runbooks/eye-relay.md`
- Hook-time sources (T379, CLI 2.1.300, measured in `claude -p` probes): the subagent's `meta.json` and transcript land only
  **after** the hook returns (never seen in a 1.5 s in-hook poll), and the hook input has no prompt (`prompt_id` is the parent
  turn's). The parent's assistant row with the `Agent` tool_use lands ~0.06 s after the hook fires, so poll it.
- Workflow agents get no guides from the hook: their prompt is in the script, not an Agent call. Fixed at the source (T391): the
  `/research-swarm` template prepends `First run \`guide <lane words>\`` to every agent prompt (`agent()` opts have no system/context field). 3-day sample: plain subagents with >= 10 calls
  already ran `guide` in the first 15 calls 26/31 (84 %), the hook now covers 29/31 (94 %); workflow agents 5/105 (5 %), uncovered.
- Query is the description only: adding the prompt or the brief head made `guide`'s count-of-words ranking favour the longest
  index lines (explainer-engine first for unrelated tickets).
