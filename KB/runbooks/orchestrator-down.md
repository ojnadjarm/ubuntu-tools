# Runbook: orchestrator pane not serving (pc status shows orch= not ok)

`claude-orchestrator.service` is **enabled** (owner rule 2026-09-27: the session always comes back after a
reboot; the 09-13 "retired" note was a misunderstanding). While it is disabled `pc status` reports `orch=off`
and `sentinel-check` leaves it alone.

## Boot path (T117, 2026-09-27)

- Linger starts `user@1000` at boot (13.8 s this boot); `default.target` wants the unit. `After=graphical-session.target`
  only orders: with GDM autologin the unit waits for it (15.4 s), without a graphical login it starts anyway.
- Root cause of the pre-09-13 boots with no session: the unit ran `claude --remote-control` in `~`, where the trust
  dialog shows on **every** launch and nothing answered it, so Remote Control never registered (`tmux=alive`, no host
  in the app). Fixed since T45 by `ExecStartPost=eye-channel-accept claude` (trust + channels dialogs), with
  `sentinel-check` as the second line.
- T117 added `ExecStartPre=/usr/bin/nm-online -q -t 60`: Remote Control registers at launch, and Wi-Fi was online
  only at 16.6 s this boot. No network in 60 s fails the start and `Restart=on-failure` retries every 10 s.
  `TimeoutStartSec=180` covers the 60 s network wait plus the 60 s dialog wait.
- Proof without a reboot: `bash ~/agents/bin/tests/orchestrator-boot.test.sh` boots a private `systemd --user`
  (stock targets only) with a copy of the unit enabled into `default.target` (stub claude, private tmux socket).
  Not provable without a reboot: the real claude's first launch after boot (Remote Control registering, which
  conversation `--continue` picks) and the autologin race.
- One Remote Control host: only the unit's session passes `--remote-control "DarkSaddler Command Center"`. A
  hand-run `claude --continue` with `/remote-control` on is a second host; hand over instead (below).

## Handover from a hand-run session

`orchestrator-handover <pid>` (the hand-run `claude --continue`): it detaches into the transient unit
`orchestrator-handover`, waits 20 s, SIGTERMs the pid, starts the unit only once the pid is gone (two `--continue`
sessions fork the conversation), waits for `orch=ok` and pushes the result. Log:
`journalctl --user -u orchestrator-handover`. Abort inside the 20 s: `systemctl --user stop orchestrator-handover`.

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
