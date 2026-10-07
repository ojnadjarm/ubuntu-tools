# Wait on a background job, and how the sentinel catches stuck wait loops

Ticket: T67 · Last verified: 2026-09-24 by both fixture suites (12 + 17 checks pass; the 2 workflow-owner fixtures added 2026-09-24 by code-review F04 not yet run under bwrap) and `sentinel-waits --dry-run`

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
- Owner = the Bash-tool shell (argv sources `.claude/shell-snapshots/`) → its `tasks/<id>.output` → the subagent transcript
  holding that id, searched recursively under `<session>/subagents/` (workflow agents live in `workflows/wf_*/`, 69% on
  2026-09-24; before that fix their loops counted as never ended). Ended = handed back and idle 2 min, or idle 30 min (orbit-hook's rule).
- `sentinel-runaway` rule 1 kills only `until/while … sleep` shells under a scratchpad, > 60 min, whose owner session is gone
  (no `claude` ancestor, no `claude` naming the session id); it skips `wait-for`. Before 2026-09-24 it killed any 60-min
  scratchpad shell, and twice hit a live session (sentinel.log 09-15, pids 594947 and 1293483).

## Exact commands
Run these in a background Bash call (`run_in_background`); the call returning is the notification.
```bash
wait-for --label build --pid 4242                                     # until the process exits
wait-for --label dia --file run.log --match '^\{|Traceback' --job 4242  # until the log matches; exit 3 if 4242 dies first
wait-for --label up --until 'curl -sf localhost:8080/health' --job 4242 --every 5
wait-for --list            # live waits: pid, age, label, target (--json for the dashboard)
sentinel-waits --dry-run   # what the reaper would kill now, kills nothing
bash ~/agents/bin/tests/wait-for.test.sh        # 12 checks, own child processes only, 5.4 s
bash ~/agents/bin/tests/sentinel-waits.test.sh  # 2 stubbed checks (owner(), one-line reap log), then 19 inside a bwrap PID namespace
```
Exit codes: 0 condition met · 3 job died, or `--file` without `--job` stalled · 143 killed · 2 usage.

## Pitfalls (measured)
- Age alone cannot judge a wait: in 87 background loops from this machine's transcripts, the finished ones took p50 2 min,
  p90 26 min, max 178 min (pcbench), and 16 never notified anyone. Hence liveness, not a timeout; unregistered loops are
  judged only after 20 min (N), a file counts as stalled after 15 min unchanged with no writer (M, 30x the slowest 30 s poll).
- The T65 r-dia loops ran about 60 min unseen because they lived under `research/…`, outside the scratchpad
  that `sentinel-runaway` rule 1 watched. `sentinel-waits` would have taken them at the first tick after 20 min.
- `--file` without `--job` can only detect a dead job by the 15-min stall; always pass `--job <pid>` when you have it.
- `--until` runs `bash -c` every poll (default 10 s): keep the condition cheap, raise `--every` for heavy checks.
- `wait-for` vs `pc wait-for`: agents confuse them. Only the first waits on jobs; the second is desktop UI.
- Adoption, first day (41 transcripts newer than `bin/wait-for`): 64 `wait-for --label` calls, but still 6 hand-written
  `until/while … sleep` loops. The fallback reaper is still needed.
- Testing the reaper against real processes could kill a live agent (FLEET §5.6). The suite re-execs itself under
  `bwrap --unshare-pid --proc /proc` and a selftest first proves the host's `claude` processes are invisible.
- Cost at idle: `sentinel-waits --dry-run` with no waits registered takes 0.03 s per 15-min tick.

## Links
- Code: `~/agents/bin/wait-for`, `~/agents/bin/sentinel-waits`, called from `~/agents/bin/sentinel-check` (after `sentinel-runaway`)
- Tests: `~/agents/bin/tests/wait-for.test.sh`, `~/agents/bin/tests/sentinel-waits.test.sh`
- Design: `~/agents/research/2026-09-23/T67/design.md` · Fleet rule: `~/agents/AGENTS.md` §3 · Toolbox: `KB/toolbox.md` (sentinel section)
- State: `$XDG_RUNTIME_DIR/agent-waits/`, `~/agents/sentinel/state/{sentinel.log,waits-seen.tsv}`
