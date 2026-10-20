# Wait on a background job, and how the sentinel catches stuck wait loops

Ticket: T67, T408, T438, T449 · Last verified: 2026-10-20 (T947: dash front read from code, miss/hit timed); before: 2026-10-20 by T846 audit (`wait-for`/`sentinel-waits --help`, MIN_AGE 1200 / STALL 900 / WAITING_IDLE 10800 / HANDBACK_IDLE 120, 15-min timer, hook registration; suites not run); before: 2026-10-19 (T449: `wait-for.test.sh` 18, `sentinel-waits.test.sh` 29, `wait-nudge.test.py` 29, the 4 pgrep forms below re-measured; T438: 2 handback-schema checks, replay of the T429 transcript; T408: `wait-for.test.sh` 18, `sentinel-waits.test.sh` 4 new owner checks, replay of the T407 transcript); before: 2026-09-24 by both fixture suites (12 + 17 checks pass; the 2 workflow-owner fixtures added 2026-09-24 by code-review F04 not yet run under bwrap) and `sentinel-waits --dry-run`

## When to use
- You started something long (a build, a benchmark, a render, a subagent's log) and need to be told when it ends: use `wait-for`.
- Never a hand-written `until …; do sleep …; done` loop: it is unregistered, and if its job dies it polls until the sentinel kills it.
- Not for the desktop: waiting on a window, focus or on-screen text is `pc wait-for --window|--focus|--text|--gone` (a different tool).
- Debugging a loop that would not die, or changing the reaper: read "The path we took" and the design doc.

## The path we took
- Survey: `timeout`, `tail --pid`, `inotifywait`, `wait-for-it`/`dockerize`, `pc wait-for`, `sentinel-runaway` rule 1 and
  `orbit-hook sweep`. None records who waits on what, and none can tell a dead job from a slow one. So we built a small bash
  `wait-for` (coreutils + `/proc`) and a `sentinel-waits` step on the existing 15-min `sentinel-check` timer. No new daemon or unit.
- `bin/wait-for` writes a registry entry `$XDG_RUNTIME_DIR/agent-waits/<pid>.json` (label, kind, target, job, session, task id),
  polls, removes the entry on exit. It has no timeout (owner, 2026-09-23): it ends when the condition holds or the job dies.
- `bin/sentinel-waits` (Python, one pass over `/proc`) judges registered waits by their owner agent, and unregistered
  `until/while … sleep` shells by: every PID they name is dead, or every file they name is unchanged 15 min with no writer,
  or their owner agent ended. Owner ended: TERM (KILL after 3 s), a `stuck-wait killed` line in `sentinel/state/sentinel.log`
  and an audit record. Owner still running: one `stuck-wait seen` line, deduped in `waits-seen.tsv`, no kill.
- Owner = the outermost Bash-tool shell (argv sources `.claude/shell-snapshots/`; a piped or backgrounded loop forks a
  subshell with the same argv, judged 'session gone' before 2026-10-17) → its `tasks/<id>.output` → the subagent transcript
  holding that id, searched recursively under `<session>/subagents/` (workflow agents live in `workflows/wf_*/`, 69% on
  2026-09-24; before that fix their loops counted as never ended). Ended = handed back (`SubagentHandback`, a last-line `end_turn`, or a last-line StructuredOutput
  tool_result, how 267 of 300 workflow agents ended on 2026-10-17) and idle 2 min, or idle 30 min (orbit-hook's rule).
- `sentinel-runaway` rule 1 kills only `until/while … sleep` shells under a scratchpad, > 60 min, whose owner session is gone
  (no `claude` ancestor, no `claude` naming the session id); it skips `wait-for`. Before 2026-09-24 it killed any 60-min
  scratchpad shell, and twice hit a live session (sentinel.log 09-15, pids 594947 and 1293483).

## Exact commands
Run these in a background Bash call (`run_in_background`); the call returning is the notification.
```bash
wait-for --label build --pid 4242                                     # until the process exits
wait-for --label dia --file run.log --match '^\{|Traceback' --job 4242  # until the log matches; exit 3 if 4242 dies first
wait-for --label up --until 'curl -sf localhost:8080/health' --job 4242 --every 5
p=$(pgrep -o -f '[f]rames-ab.sh') && wait-for --label ab --pid "$p"   # wait on a job by name; skips when it is already gone
wait-for --label ab --until "! pgrep -f '[f]rames-ab.sh'" --every 30  # same, as a condition: bracket the first letter
wait-for --list            # live waits: pid, age, label, target (--json for the dashboard)
sentinel-waits --dry-run   # what the reaper would kill now, kills nothing
bash ~/agents/bin/tests/wait-for.test.sh        # 18 checks, own child processes only, 11 s
python3 ~/agents/bin/tests/wait-nudge.test.py   # 29 checks, temp HARNESS_HOME
bash ~/agents/bin/tests/sentinel-waits.test.sh  # 29 checks: stubbed owner() and reap-log checks, then the rest inside a bwrap PID namespace
```
Exit codes: 0 condition met · 3 job died, or `--file` without `--job` stalled · 143 killed · 2 usage.
The last line always says why: `done after N s`, `done at once, the condition already held at start`, `job P died before the
condition held (exit 3)`, `stalled: … (exit 3)`, `killed by SIGTERM after N s, condition not met (exit 143)`. A wrapper's exit code
(`wait-for …; tail -1 f` exits as `tail`) hides wait-for's: read that line, or `echo rc=$?` right after wait-for.

## Pitfalls (measured)
- Age alone cannot judge a wait: in 87 background loops from this machine's transcripts, the finished ones took p50 2 min,
  p90 26 min, max 178 min (pcbench), and 16 never notified anyone. Hence liveness, not a timeout; unregistered loops are
  judged only after 20 min (N), a file counts as stalled after 15 min unchanged with no writer (M, 30x the slowest 30 s poll).
- The T65 r-dia loops ran about 60 min unseen because they lived under `research/…`, outside the scratchpad
  that `sentinel-runaway` rule 1 watched. `sentinel-waits` would have taken them at the first tick after 20 min.
- `--file` without `--job` can only detect a dead job by the 15-min stall; always pass `--job <pid>` when you have it.
- `--until` runs `bash -c` every poll (default 10 s): keep the condition cheap, raise `--every` for heavy checks.
- `--until '! pgrep -f X'` never ends: pgrep matches wait-for's own argv (and its `bash -c`), which holds X. Use
  `p=$(pgrep -o -f '[X]rest') && wait-for --pid "$p"` or `--until "! pgrep -f '[X]rest'"`. An unbracketed
  `pgrep -o -f X` with the job gone returns the caller's own shell (its argv holds X), so `--pid` waits forever
  (T363, measured); a bracketed pattern still matches a caller whose argv holds the bare name. Do not start X
  in the same command line (the caller's shell argv matches too). Measured 2026-10-15: bare form hung until `timeout` (rc 124), bracketed rc 0;
  the audit log shows frames-ab, t146-end and quiet-gpu waits re-armed for this reason. Re-measured 2026-10-19 (T449): bare, job gone →
  caller's pid, rc 124; bracketed, job gone, bare name elsewhere in the same command → caller's pid, hung 128 s;
  bracketed, clean command → no pid, rc 1; bracketed, job live → `done after 3 s`. If you started X, use `X & p=$!`.
- T408 (2026-10-19): two T407 waits "returned early" with no `wait-for:` line: `sentinel-waits` killed them (sentinel.log 02:34:57,
  02:49:57) because a subagent's last line was `end_turn` 3–6 min idle. A subagent that ends its turn with a background wait running
  is waiting for that wait's notification, not done. Now a registered wait's owner ends only on `SubagentHandback`/StructuredOutput
  (+2 min) or 3 h idle (`WAITING_IDLE`, above the 178 min measured max); unregistered loops keep the end_turn rule.
- T438 (2026-10-19): T429's registered wait was killed at 750 s (sentinel.log 08:22:49) although T408 had shipped: every
  `api-request-shape` record lists the `SubagentHandback` tool schema, so the substring `"name":"SubagentHandback"` in the
  64 KB tail read as a handback after 2 min idle. Now only an `assistant` record's `tool_use` counts (`handed_back()`).
  Not the Bash tool's 600 s cap: a `run_in_background` call has none (the wait ran 750 s).
- `--until '! systemctl --user is-active -q X.service'` holds at once for a `Type=oneshot` unit: it is `activating`, not `active`,
  while it runs (T407, measured). Wait on `--pid "$(systemctl --user show -p MainPID --value X.service)"`. `done at once` flags such a condition.
- `wait-for` vs `pc wait-for`: agents confuse them. Only the first waits on jobs; the second is desktop UI.
- Adoption, first day (41 transcripts newer than `bin/wait-for`): 64 `wait-for --label` calls, but still 6 hand-written
  `until/while … sleep` loops. The fallback reaper is still needed.
- Nudge (T376, 2026-10-18): the async PostToolUse audit hook (`adapters/claude/hooks/audit-log.py` → `hooks/wait_nudge.py`)
  returns a one-line `additionalContext` with the exact `wait-for` equivalent of an `until/while … sleep` loop, an
  `X && break` polling loop, or a leading/after-`&` `sleep N` (N ≥ 10). Measured: delivered to a main-thread session on
  the next turn (headless `claude -p` quoted it). A subagent's async output lands in the MAIN thread, not the
  subagent (4 subagent probes reached the orchestrator as false nudges), so the hook skips calls with `agent_id`;
  nudging subagents needs a synchronous PostToolUse entry (settings.json, owner-go). Adoption:
  `python3 ~/agents/hooks/wait_nudge.py --share 14` (baseline 2026-10-18: 105 wait-for vs 265 hand waits, 28.4 %).
- Block (TSP-040, T436, 2026-10-19): the PreToolUse hook `hooks/sleep-loop-block.py` (same parser, `wait_nudge.loop_wait`)
  denies an `until/while … sleep` or `X && break` loop before it runs, in subagents too (measured: a haiku subagent got the deny
  and the line); the reason is the `wait-for` line to run. Loops in quoted data or heredoc bodies pass; `bash -c '…'`/`eval` loops
  are blocked. A deliberate loop fixture (reaper tests) goes in a script file run with `bash f.sh`. Replay of 7 days of audit
  summaries: 139 denies of 15 269, 0 on data. Live: registered as a PreToolUse Bash hook in `~/.claude/settings.json` (checked 2026-10-20).
  Dash front (T896): `hooks/sleep-loop-block.py` is a `#!/bin/dash` script that reads stdin (`gnucat` when present) and exits 0
  unless the call holds `pkill`/`pgrep`, or `sleep` with `until`/`while`/`for`; only then it execs `python3 -IS
  sleep-loop-block-impl.py` (the parser). Measured 2026-10-20 (T947, 15 runs): miss 1.7 ms median, hit 28 ms (T896: miss 3.0 ms with the front, 39 ms without).
  Test: `python3 ~/agents/hooks/sleep-loop-block.test.py`.
- Testing the reaper against real processes could kill a live agent (FLEET §5.6). The suite re-execs itself under
  `bwrap --unshare-pid --proc /proc` and a selftest first proves the host's `claude` processes are invisible.
- Cost at idle: `sentinel-waits --dry-run` with no waits registered takes 0.03 s per 15-min tick.

## Links
- Code: `~/agents/bin/wait-for`, `~/agents/bin/sentinel-waits`, called from `~/agents/bin/sentinel-check` (after `sentinel-runaway`)
- Tests: `~/agents/bin/tests/wait-for.test.sh`, `~/agents/bin/tests/sentinel-waits.test.sh`
- Design: `~/agent-work/research/2026-09-23/T67/design.md` · Fleet rule: `~/agents/AGENTS.md` §3 · Toolbox: `KB/toolbox.md` (sentinel section)
- State: `$XDG_RUNTIME_DIR/agent-waits/`, `~/agents/sentinel/state/{sentinel.log,waits-seen.tsv}`
