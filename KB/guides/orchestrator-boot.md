# Orchestrator session after boot, prove a user unit's boot path without rebooting, hand over a hand-run session

Ticket: T117, T469, T474 · Last verified: 2026-10-20 by unit, uninstall.sh and sentinel-check read (installed unit = repo copy, enabled); 2026-10-19 by `bin/tests/orchestrator-boot.test.sh` (15 checks, 16 s at load 20) and `uninstall.sh` read (T487)

## When to use
The orchestrator did not come back after a reboot, or any user unit's boot behaviour must be proven without a
reboot, or a hand-run `claude --continue` must move into `claude-orchestrator.service`. Pane states: runbook
`KB/runbooks/orchestrator-down.md`.

## The path we took
- Unit lives in the repo (`units/claude-orchestrator.service`, installed by `install.sh`); session and Remote Control name come from config.env via `env.sh`.
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
- `ExecStop` must be `-`-prefixed: when claude exits the session is already gone, `tmux kill-session` exits 1 and the unit logged "Failed with result 'exit-code'" (3x in 7 d before T469). With the `-`, only `Restart=always` brings it back.
- `uninstall.sh` keeps `claude-orchestrator.service` (prints `kept`); only `uninstall.sh --with-orchestrator` runs `disable --now` on it
  and stops the session (T474; checked in a container by `bin/tests/install-fresh.sh`).
- `orchestrator-handover <real pid>` is live even piped into `head`: never run it to "look".
- orchestrator-boot.test.sh speed floor (T585): the fixture drops in `RestartSec=1` and stubs `nm-online` (fresh box has no network), but
  `eye-channel-accept` sleeps ~5.5 s per start (2 s after each Enter, 0.5 s per Down, 1 s poll), twice per run: 16 s at load 20.
- In the fresh box (`install-fresh.sh --suite`) the test is `# host-only`: with `nm-online` stubbed it gets past ExecStartPre, then
  ExecStartPost fails (`eye-channel-accept` lives in ~/the-dark-eye, not installed) and the unit restart-loops (NRestarts=5).

## Links
- Code: `~/agents/units/claude-orchestrator.service` (installed to `~/.config/systemd/user/`), `~/agents/bin/orchestrator-handover`, `~/the-dark-eye/bridge/relay/eye-channel-accept`
- Tests: `bin/tests/orchestrator-boot.test.sh`, `bin/tests/orchestrator-health.test.sh`
