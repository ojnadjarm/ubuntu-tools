# Runbook: orchestrator pane not serving (pc status shows orch= not ok)

**Retired 2026-09-13 (owner decision):** `claude-orchestrator.service` is disabled. The owner runs
the orchestrator himself (`claude --continue` in his own terminal, outside tmux); the unit's
`claude --remote-control $HARNESS_HOST` session showed up as a duplicate host entry in the Claude
app. While the unit is disabled `pc status` reports `orch=off`, which is healthy (`--check` passes)
and `sentinel-check` never repairs or pushes for it. To bring the tmux session back:
`systemctl --user enable --now claude-orchestrator.service` — the states below apply again.

`tmux=alive` only says the session exists; `orch=` says what its pane is doing
(`ok` = Claude running and no dialog, `trust-prompt`, `shell`, `dead`). Remote Control on the
phone is down whenever `orch` is not `ok`, even with `tmux=alive` (2026-09-13: 9 h unnoticed).

1. Look, never guess: `tmux capture-pane -pt claude | tail -20` and `pc status | sed -n '/^AGENTS/,/^$/p'`.
2. `trust-prompt`: the pane shows "Is this a project you trust?". Answer it with
   `tmux send-keys -t claude Down Enter` ("Yes, I trust this folder"; the folder is the owner's
   home). `sentinel-check` does this itself once per episode, then re-reads after 5 s.
3. `shell` (Claude exited, a bare prompt) or `dead` (pane exited, or no session):
   `systemctl --user restart claude-orchestrator.service`. `sentinel-check` does this once per
   episode; a second failure pushes the owner instead of restarting again.
4. Verify: `pc status --check` exit 0 and `orch=ok` in `pc status --brief`.
5. Why the prompt comes back after every reboot: Claude Code (2.1.270) never persists trust for
   the home directory (`projects["$HOME"].hasTrustDialogAccepted` stays false and is
   ignored; the binary says "home-directory trust is never saved"). There is no supported flag to
   pre-accept it; the only escape hatches are running the orchestrator from a non-home project
   directory (changes the session's CLAUDE.md and memory paths — owner decision) or the internal
   `CLAUDE_CODE_SANDBOXED=1` env (undocumented, not applied).

State files: `~/agents/sentinel/state/orch-repaired` and `orch-notified` mark the episode; both are
removed on the first tick with `orch=ok`. Test: `bash ~/agents/bin/tests/orchestrator-health.test.sh`.
