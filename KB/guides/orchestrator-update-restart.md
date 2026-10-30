# Keep the orchestrator session on the newest Claude Code (restart onto a new version without a reboot)

Ticket: T1430 · Last verified: 2026-10-30 by `bin/tests/orchestrator-update-restart.test.sh` (34 checks, 37 s) and one real unit run (noop, 2.1.314 = 2.1.314)

## When to use
The auto-updater installed a new Claude Code but the orchestrator pane still runs the old binary. Not for other
sessions (Vass, liaison jobs) and not for the auto-updater itself.

## The path we took
- No updater hook exists (the native updater only repoints `~/.local/bin/claude` → `~/.local/share/claude/versions/<v>`),
  so a nightly timer (04:30, `Persistent=true`) runs `orchestrator-update-restart`.
- Running version: basename of `/proc/<orchestrator pid>/exe`; installed: `claude --version`; "new for N h": mtime of the
  launcher link. Equal → `noop`.
- Safe gates (else `wait`, retried next run): registry `~/.claude/sessions/<pid>.json` status idle, pane not in copy mode,
  no `esc to interrupt`/`Waiting for … background`, no `◯` agent row under the input box, no subagent/workflow file of
  the session touched in 10 min, empty input line, no `discord-liaison/state/escalations/*.md`, outside 08-01 unless the
  new version is 24 h old.
- Restart: `/exit` typed, wait for the pid to end, `systemctl --user start claude-orchestrator.service`, read back
  version + same `sessionId` (`--continue` keeps the id, measured). Failure → one `notify-owner` line, exit 1.
- Pane probes live in `bin/orchlib.sh`, shared with `orchestrator-pulse`; `decide` is a pure function the test sources.

## Exact commands
```bash
orchestrator-update-restart --dry-run              # prints and logs the verdict, changes nothing
tail ~/agents/log/orchestrator-update-restart.log  # one line per run
bash ~/agents/bin/tests/orchestrator-update-restart.test.sh
```

## Pitfalls (measured)
- An open escalation file blocks the restart with no time limit: on 2026-10-30 two from 10-27/10-28 were still open.
- `--continue` resumes the newest conversation in `~`; if another session there is newer the read-back sees a new id and notifies.
- Fake claude in tests: `bash` copied to `versions/<v>` and run as `exec -a claude` in a subshell, so `/proc/<pid>/exe`
  names the version and the pid is a child of the pane pid as in the real unit.
- `systemctl --user start` is a no-op while the tmux server holds another session (unit still active); the read-back then
  fails and notifies; sentinel-check repairs within 15 min.

## Links
- Code: `~/agents/bin/orchestrator-update-restart`, `~/agents/bin/orchlib.sh`, `~/agents/units/orchestrator-update-restart.{service,timer}`
- Tests: `bin/tests/orchestrator-update-restart.test.sh` (private tmux server, stub systemctl/notify-owner/claude)
- Brief: `~/agent-work/briefs/T1430-orchestrator-auto-update-restart.md`
