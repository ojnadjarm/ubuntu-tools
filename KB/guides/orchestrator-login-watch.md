# Push the owner when the orchestrator loses its Claude login or Remote Control

Ticket: T1436, T1437 · Last verified: 2026-11-01 by bin/tests/orchestrator-login-watch.test.sh (29 ok) and a live dry-run

## When to use
The orchestrator session showed "OAuth token unavailable — run /login" and Remote Control dropped silently. This timer
pushes the owner within ~5 min. Not for plan limits (`plan-usage`) or a dead pane (`sentinel-check`, `pc status orch=`).

## The path we took
Existing: `notify-owner` (ntfy, 24 h dedup on -p high), `claude auth status --json`, `tmux capture-pane`. No watcher existed.
- Inputs: `loggedIn` from `claude auth status --json` (unparseable = unknown, not lost); the whole pane scrollback
  (`capture-pane -peJ -S -`, with colours). The newest notice wins: lost = system notice `● Remote Control disconnected …`
  (bullet and text share one colour); healthy = `/remote-control is active · Continue here…` or `❯ /login` then `⎿ Login successful`.
- Push fix: `/login` for auth or OAuth notices, `/remote-control` for others (e.g. "another connection took over").
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
- T1436 read only the last 40 lines; the notice scrolled out in ~3 min. Now the whole scrollback (tmux history-limit 2000):
  only > 2000 lines of output inside one 5-min tick hides it.
- Reply text is plain after the bullet (`\e[38;5;231m●\e[39m text`); notices colour the text too (`\e[38;5;220m●\e[39m \e[38;5;220mRemote…`).
  Quotes in replies, tool output with "Login successful", and the "Your login expires … run /login" banner never match.
- Session JSONL is not used: it has the notices (`system`/`informational`, `bridge_status`, `local_command` "Login successful"),
  but every process running the session writes it. On 2026-11-01 an SSH `claude --continue` shared the orchestrator's session
  and its "another connection took over" notice landed in the same JSONL while the tmux pane was healthy.
- `~/.claude/sessions/<pid>.json` has `bridgeSessionId` but no connected/disconnected field (2.1.316).

## Links
- Code: ~/agents/bin/orchestrator-login-watch, ~/agents/units/orchestrator-login-watch.{service,timer}
- Tests: ~/agents/bin/tests/orchestrator-login-watch.test.sh (shims for claude, tmux, notify-owner)
