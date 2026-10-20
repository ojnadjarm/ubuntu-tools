# Brief check: lint a brief for CHECK/claims/time box/report cap, run its CHECK before handback

Ticket: T381, T419, T488, T633, T913 · Last verified: 2026-10-20 (T947: `brief-lint --help`, `unniced_heavy` code read, `--backlog` on 2 live backlogs); before: 2026-10-20 by `bin/tests/brief-check.test.sh` (13/13), `bin/tests/agent-verify.test.sh` (37/37), `adapters/claude/hooks/subagent-stop-gate.test.py` (13/13) and a lint of the 50 newest briefs

## When to use
Writing a brief (orchestrator): `brief-lint` it before spawning. Finishing a ticket (agent): `agent-verify` the brief
before handback. Not a test runner: the CHECK line names the real test or probe.

## The path we took
- Spec: T373 IMPROVE.md §8 ("done" is self-reported; T328 shipped 6 regressions). Outside evidence: a runnable
  pass/fail check plus a Stop gate is the largest harness win (LangChain TB2 52.8 → 66.5).
- Two single-purpose CLIs, no shared lib: `brief-lint` (pure read, regex rules, follows `_common-*.md` the brief
  names) and `agent-verify` (one `bash -c` of the first `CHECK:` line, or with `--ticket T<n>` in a multi-CHECK file the one under its `## [k.] T<n>` heading, rc 2 when absent (T774), timeout, atomic JSON write).
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
brief-lint --backlog BACKLOG.md [--min 20] [--top 8]   # planner backlog: one line per problem, `backlog: N tickets, P problems`, rc 1 on any (T913)
agent-verify ~/agent-work/briefs/T381-*.md        # green rc=0 → ~/agent-work/evidence/T381/check.json; exit 0/1, 2 = no CHECK
agent-verify --timeout 900 --ticket T381 <brief>
agent-verify --recheck [--since 7d]               # re-run every red check.json first run inside the window; exit 1 if any stays red
pc failures                                       # still-red ones show as `check T4xx <age since first red>`
python3 ~/agents/adapters/claude/hooks/subagent-stop-gate.test.py   # 13 checks, temp HOME/AGENT_WORK
```
Brief line shape: `CHECK: <command>` at line start (optionally `- ` and backticks), e.g.
`CHECK: ~/agents/bin/tests/brief-check.test.sh`.

## Pitfalls (measured)
- Baseline 2026-10-18: 0/50 newest briefs had a CHECK line; 27/50 named claims, 26/50 a time box, 27/50 a report cap.
- Only the first `CHECK:` line runs; chain with `&&` for more than one command.
- The CHECK runs in the caller's cwd; use absolute paths.
- Evidence is overwritten per run: the latest verdict wins. A `--recheck` keeps the earlier runs in `runs[]`
  (started, rc, ok, seconds); a fresh `agent-verify <brief>` starts a new record without them.
- T488: `--recheck` runs the stored `check` in the stored `cwd` (home if gone), not the brief's current CHECK line. The
  window counts from the first run, so a lasting red stops being re-run after 7 d. Nightly in `fleet-ci-daily` after the suite (rc unchanged).
  A CHECK that is the whole suite (T410) re-runs the whole suite.
- T633: a red under load is re-run after `quiet-gate --wait` (one 300 s budget per pass); green then tags the loaded run
  `verdict: load` in `runs[]`. A red still standing gets `verdict: drift` (a `grep '^RE' FILE` whose newest FILE's line 1 no longer
  matches RE; `drift{file,regex,line}`) or `real` (red when quiet). Gate timed out and no drift: no verdict, printed `busy`.
- T913 `--backlog FILE [--min N] [--top K]` (defaults 20, 8): per `## [k.] T<n>` section it needs `- Size S|M`, `auto-ok|owner-go`, `- Files:`, `- Success:` and exactly one `CHECK:`; ids unique and consecutive; ≥ N CHECKs; the first K tickets' Files pairwise disjoint (brace lists expanded, `(new)`/`(after …)` stripped, a dir covers its children); a heavy command (`run.sh`, `blender`, `cpp-ci`, `mv-render`, `godot`, `build.sh`, `ffmpeg`, `make.sh`, any `--measure`) in command position needs `nice -n 19` or `ci-window &&` (a grep naming make.sh is not a call). Live 2026-10-20 (T947): T893 and T939 backlogs, 20 tickets, 0 problems each.
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
