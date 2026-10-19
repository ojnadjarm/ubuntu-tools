# Brief check: lint a brief for CHECK/claims/time box/report cap, run its CHECK before handback

Ticket: T381, T419 · Last verified: 2026-10-19 by `bin/tests/brief-check.test.sh` (13/13), `adapters/claude/hooks/subagent-stop-gate.test.py` (13/13) and a lint of the 50 newest briefs

## When to use
Writing a brief (orchestrator): `brief-lint` it before spawning. Finishing a ticket (agent): `agent-verify` the brief
before handback. Not a test runner: the CHECK line names the real test or probe.

## The path we took
- Spec: T373 IMPROVE.md §8 ("done" is self-reported; T328 shipped 6 regressions). Outside evidence: a runnable
  pass/fail check plus a Stop gate is the largest harness win (LangChain TB2 52.8 → 66.5).
- Two single-purpose CLIs, no shared lib: `brief-lint` (pure read, regex rules, follows `_common-*.md` the brief
  names) and `agent-verify` (one `bash -c` of the first `CHECK:` line, timeout, atomic JSON write).
- Data flow: brief `CHECK: <cmd>` → `agent-verify` → `$AGENT_WORK/evidence/<ticket>/check.json`
  (`ok`, `rc`, `seconds`, stdout/stderr tails) → SubagentStop hook `adapters/claude/hooks/subagent-stop-gate.py` reads it.
- Gate (T419): agent transcript (`agent_transcript_path`, else `<session>/subagents/**/agent-<id>.jsonl`) → first
  user prompt → first `…briefs/T<nn>….md` path → brief has a `CHECK:` line → `check.json` missing, not JSON or not
  `"ok": true` = exit 2 with the `agent-verify` command on stderr. Passes (0): `stop_hook_active`, no brief path, no
  CHECK line, brief missing, any hook error (fail open). Wiring is owner-go: owner-todo "subagent-stop-gate" block.

## Exact commands
```bash
brief-lint ~/agent-work/briefs/T381-*.md          # ok / FAIL: missing check, claims, timebox, report-cap
brief-lint --summary ~/agent-work/briefs/T3*.md   # pass N/M plus per-rule counts
agent-verify ~/agent-work/briefs/T381-*.md        # green rc=0 → ~/agent-work/evidence/T381/check.json; exit 0/1, 2 = no CHECK
agent-verify --timeout 900 --ticket T381 <brief>
python3 ~/agents/adapters/claude/hooks/subagent-stop-gate.test.py   # 13 checks, temp HOME/AGENT_WORK
```
Brief line shape: `CHECK: <command>` at line start (optionally `- ` and backticks), e.g.
`CHECK: ~/agents/bin/tests/brief-check.test.sh`.

## Pitfalls (measured)
- Baseline 2026-10-18: 0/50 newest briefs had a CHECK line; 27/50 named claims, 26/50 a time box, 27/50 a report cap.
- Only the first `CHECK:` line runs; chain with `&&` for more than one command.
- The CHECK runs in the caller's cwd; use absolute paths.
- Evidence is overwritten per run: the latest verdict wins.
- T396: a brief naming ailearning/portfolio/vass/fleet without its ledger prints `WARN`; rc unchanged. See `decisions-ledger.md`.
- T401: `/dev/zero` fed into `script`/`tmux` prints `WARN <file>:<line>`; `brief-lint --tests` scans `bin/tests/*.sh`. See `runaway-guard.md`.
- T419: the gate blocks once only: on the retry `stop_hook_active` is true, so a CHECK the agent cannot make green
  still hands back (report it red). Gate has its own SubagentStop group: inside the orbit-hook group a re-run of
  `adapters/claude/install` would drop it (merge-settings replaces groups holding its commands).
- T419: the ticket comes from the brief path, not `--ticket`; an `agent-verify --ticket X` with another name is not seen.
- T412: the CHECK runs in its own session; a timeout `killpg`s the whole group (rc 124), so backgrounded test suites and browsers die too. A child that calls `setsid` itself still escapes.

## Links
- Code: `~/agents/bin/brief-lint`, `~/agents/bin/agent-verify`, `~/agents/adapters/claude/hooks/subagent-stop-gate.py`
- Tests: `~/agents/bin/tests/brief-check.test.sh` (fixtures `bin/tests/fixtures/brief-check/`, temp AGENT_WORK)
- Design: `~/agent-work/research/2026-10-18/night/T373/IMPROVE.md` §8
