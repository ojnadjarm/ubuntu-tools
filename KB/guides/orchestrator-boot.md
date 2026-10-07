# Orchestrator session after boot, prove a user unit's boot path without rebooting, hand over a hand-run session

Ticket: T117 · Last verified: 2026-09-27 by `bin/tests/orchestrator-boot.test.sh` (10 checks, 8 s)

## When to use
The orchestrator did not come back after a reboot, or any user unit's boot behaviour must be proven without a
reboot, or a hand-run `claude --continue` must move into `claude-orchestrator.service`. Pane states: runbook
`KB/runbooks/orchestrator-down.md`.

## The path we took
- Unit enabled into `default.target` (linger); `eye-channel-accept` answers trust + channels; `nm-online` waits for Wi-Fi.
- Boot proof: a fresh private `systemd --user` (`systemd-run --user --scope -p Delegate=yes env XDG_RUNTIME_DIR=<tmp>
  SYSTEMD_UNIT_PATH=<tmp> /usr/lib/systemd/systemd --user`) with only stock targets plus a sed copy of the unit.
- Handover: `orchestrator-handover <pid>` in a transient unit, so it outlives the session it stops.

## Exact commands
```bash
bash ~/agents/bin/tests/orchestrator-boot.test.sh
orchestrator-handover <pid-of-hand-run-claude>      # starts the real unit; abort: systemctl --user stop orchestrator-handover
```

## Pitfalls (measured)
- `systemd-run` needs the real `XDG_RUNTIME_DIR`; put the private one inside `env`, or it fails "Failed to connect to user scope bus".
- The private manager needs `exit.target` + `systemd-exit.service` in its path for `systemctl --user exit`; its `inaccessible/` nodes are mode 000, so `chmod -R u+rwX` before `rm -rf`.
- Enabling the unit next to a live hand-run session: `sentinel-check` restarts it within 15 min (`orch=dead`) and forks the conversation; `touch ~/agents/sentinel/state/{orch-repaired,orch-notified}` until the handover.
- `orchestrator-handover <real pid>` is live even piped into `head`: never run it to "look".

## Links
- Code: `~/.config/systemd/user/claude-orchestrator.service`, `~/agents/bin/orchestrator-handover`, `~/the-dark-eye/bridge/relay/eye-channel-accept`
- Tests: `bin/tests/orchestrator-boot.test.sh`, `bin/tests/orchestrator-health.test.sh`
