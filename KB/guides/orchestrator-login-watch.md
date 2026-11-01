# Push the owner when the orchestrator loses its Claude login or Remote Control

Ticket: T1436 · Last verified: 2026-11-01 by bin/tests/orchestrator-login-watch.test.sh (23 ok) and a live dry-run under systemd

## When to use
The orchestrator session showed "OAuth token unavailable — run /login" and Remote Control dropped silently. This timer
pushes the owner within ~5 min. Not for plan limits (`plan-usage`) or a dead pane (`sentinel-check`, `pc status orch=`).

## The path we took
Existing: `notify-owner` (ntfy, 24 h dedup on -p high), `claude auth status --json`, `tmux capture-pane`. No watcher existed.
- Inputs: `loggedIn` from `claude auth status --json` (unparseable = unknown, not lost); last 40 non-blank pane lines,
  lost when the last marker is a lost one (`run /login`, `OAuth token unavailable`, `login expired`, `Signed out of Claude`,
  `API Error: 401`, `Remote Control disconnected`) and not `Login successful` / `Remote Control credential renewed`.
- Decision: none, notify, hold (lost, pushed < 6 h ago), renotify (>= 6 h), clear (healthy with an open incident).
- State `~/agents/log/orchestrator-login-watch.state` (`<since> <last push>`), log `~/agents/log/orchestrator-login-watch.log`
  (one line per push or recovery). Never types into the pane, restarts nothing, prints no token or email.

## Exact commands
```bash
orchestrator-login-watch --dry-run            # auth=… pane=… incident=… → decision
systemctl --user list-timers orchestrator-login-watch.timer
cat ~/agents/log/orchestrator-login-watch.log
bash ~/agents/bin/tests/orchestrator-login-watch.test.sh
```
Owner fix in the push: SSH (Termux) → `tmux attach -t claude` → `/login`.

## Pitfalls (measured)
- `notify-owner -p high` strips digits from the dedup key and drops repeats for 24 h: the -k key is the push epoch mapped to letters.
- The pane line scrolls away: on 2026-11-01 the real "Remote Control disconnected — OAuth token unavailable" line left the
  last 40 lines within ~3 min of orchestrator output, so the first timer run saw a clean pane. The pane signal only catches it
  while it is on screen; the session registry (`~/.claude/sessions/<pid>.json`) has `bridgeSessionId` but no proven disconnected field.
- The orchestrator talking about these markers in its own transcript would match them too (same pane text).

## Links
- Code: ~/agents/bin/orchestrator-login-watch, ~/agents/units/orchestrator-login-watch.{service,timer}
- Tests: ~/agents/bin/tests/orchestrator-login-watch.test.sh (shims for claude, tmux, notify-owner)
