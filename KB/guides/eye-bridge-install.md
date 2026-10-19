# Install, move or upgrade the Eye ↔ Claude Code bridge (eye-relay, eye-channel, eye tap)

Ticket: T280 · Last verified: 2026-10-07 by `~/the-dark-eye/bridge/relay/tests/run.sh` (7/7 files, installer sandbox 21/21) and a live switch

## When to use
Installing the voice channel on a box, adding a brain, or moving its files. Not for the body itself (`bridge/install.sh`).

## The path we took
- The bridge is generic, so it lives in `~/the-dark-eye/bridge/relay/` with one idempotent `install.sh` (`--dry-run`, `--uninstall`).
- ubuntu-tools keeps only gitignored links: `~/agents/eye-relay/mcp-main.json` → `~/.config/dark-eye/` (read by
  `claude-orchestrator.service`; one more `mcp-<brain>.json` per brain added to `EYE_RELAY_BRAINS`) and the legacy `eye-relay/state` link.
- Config `~/.config/dark-eye/relay.env` (brains, `EYE_UNANSWERED_S`, `EYE_NOTIFY`); state `~/.local/state/dark-eye/relay/`.

## Exact commands
```bash
~/the-dark-eye/bridge/relay/install.sh --dry-run
~/the-dark-eye/bridge/relay/install.sh            # rerun prints "no change: already installed"
ln -sfn ~/.config/dark-eye/mcp-main.json ~/agents/eye-relay/mcp-main.json   # fleet link, once per brain
~/the-dark-eye/bridge/relay/tests/run.sh
```

## Pitfalls (measured)
- A running `eye-channel` resets its offset to 0 if the spool path vanishes for one 0.5 s poll, then replays the whole
  spool (29772 B here) into the session. Move a live state dir with two `mv --exchange -T` steps, never `mv` + `ln`.
- Stop the relay first (`pc units stop eye-relay.service --user --apply`): a stop drains its 50 s poll; the bus holds 200 lines.
- `bridge/install.sh` used to reset `~/.local/bin/eye` to `eye.sh` (drops the watchdog tap); it keeps the tap since T280.

## Links
- Code: `~/the-dark-eye/bridge/relay/` (`README.md` there), runbook `KB/runbooks/eye-relay.md`
- Tests: `~/the-dark-eye/bridge/relay/tests/run.sh`
- Design: `~/agent-work/research/2026-10-07/T280/ARCHITECTURE.md`
