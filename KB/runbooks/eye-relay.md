# Eye relay: the owner's voice into Claude Code sessions via channels (T38)

The Monitor tool stops after 30 minutes (`timeout_ms` ≤ 1800000, no persistent option in 2.1.280).
This relay has no timer anywhere: Claude Code's **channels** (research preview) let an MCP server
push `notifications/claude/channel` into the running session. Events queue in order and arrive
together if the session is busy (code.claude.com/docs/en/channels-reference).

## Pieces

| Piece | What |
|---|---|
| `eye-relay.service` (user unit, `~/agents/units/`) | `bin/eye-relay main notes`: one long-poll (50 s) per brain on `/bridge/listen`, each line appended + fsynced to `eye-relay/state/<brain>.spool`. It polls a brain **only while that brain's `eye-channel` holds `state/<brain>.lock`**, so `eye brains` keeps its old meaning (connected = a session is really listening). While unsubscribed, the Eye's bus holds up to 200 lines as before. A stop waits for the in-flight poll (≤ 50 s, `TimeoutStopSec=70`), so a restart loses nothing. |
| `bin/eye-channel <brain>` | Stdlib MCP stdio server that Claude Code spawns. Declares `claude/channel` and takes the brain's lock (one consumer per brain). It streams the spool from `state/<brain>.offset` and saves the offset after each push. Lines use the `eye listen-loop` format (`VOICE:`, `VOICE [remote]:`, `EVENT:`, `EYE OFFLINE/BACK`), unsplit. |
| `eye-relay/mcp-<brain>.json` | The `--mcp-config` for one brain (`eye-main`, `eye-notes`). |
| `bin/eye-channel-accept <tmux-target>` | Confirms the "Loading development channels" dialog, which Claude Code shows on **every** launch with `--dangerously-load-development-channels`, and the workspace trust dialog in either order (T45). Trust: moves to "Yes, I trust this folder" and presses Enter only after reading that line back as selected (the default "No, exit" kills the session); exits 1 otherwise. After channels it waits `ACCEPT_GRACE` (3 s) for a trust dialog. Test: `bin/tests/eye-channel-accept.test.sh` (fake TUI on a private `TMUX_SOCKET`). |

## Subscribe a session (launch flags; no settings.json change)

```
claude … --mcp-config ~/agents/eye-relay/mcp-<brain>.json --dangerously-load-development-channels server:eye-<brain>
```
then `eye-channel-accept <tmux-session>`. Startup shows `Channels (experimental) messages from server:eye-<brain> inject directly in this session`.
Lines arrive as `← eye-<brain>: VOICE: …`. **Never also arm `eye listen-loop` in that session.** The bus hands each line to one poller only, so two ears split his words.
Only the brain's own session gets the flag. Workers must not get it: a session that loads the server without the flag drops the lines silently after the offset has moved.

## Switch-over (orchestrator applies at the next restart)

1. `~/.config/systemd/user/claude-orchestrator.service`: in **both** `claude` commands of `ExecStart`, add
   `--mcp-config %h/agents/eye-relay/mcp-main.json --dangerously-load-development-channels server:eye-main`,
   and add the line `ExecStartPost=%h/agents/bin/eye-channel-accept claude`.
2. `~/agents/units/notes-brain.service` (then copy to `~/.config/systemd/user/`): in both `claude` commands add
   `--mcp-config %h/agents/eye-relay/mcp-notes.json --dangerously-load-development-channels server:eye-notes`. Add
   `ExecStartPost=%h/agents/bin/eye-channel-accept notes` **above** the `notes-brain-arm` line.
3. `~/agents/notes/BRIEF.md` rule 1 ("Arm the ear"): replace the Monitor step with "The ear is the `eye-notes` channel,
   already on at launch; never arm `eye listen-loop`. Check `eye health`, then say one line that the ear is up."
   Keep `Monitor` in `--tools`: the settle timer (rule 4) still uses it.
4. `/eye` skill (live `~/.claude/skills/eye/`, then `~/moodle-harness/sync.sh`): "if this session was launched with
   the `eye-main`/`eye-notes` channel, do not arm the Monitor listen-loop."
5. `systemctl --user daemon-reload`, restart the two sessions at a quiet moment, then check: `eye brains` shows both
   connected, `ss -tnp | grep "pid=$(systemctl --user show -p MainPID --value eye-relay),"` shows 2 long-polls.

## Switch-over applied (T38b, 2026-09-22)

- Steps 1–4 done. `notes` runs on the channel: `eye-channel notes` holds `notes.lock`, the relay holds 1 long-poll, the
  notes session armed no Monitor. The orchestrator runs outside the unit (`claude --continue` in his terminal), so `main`
  switches when he relaunches it from `~` with:
  `claude --continue --mcp-config ~/agents/eye-relay/mcp-main.json --dangerously-load-development-channels server:eye-main`
  then picks `1. I am using this for local development` + Enter on the channels dialog (once per launch).
- The `/eye` skill file is a symlink to `~/the-dark-eye/bridge/SKILL.md`; `~/moodle-harness/sync.sh` does not carry it.
- Channel + `--continue` verified in a sandbox (private tmux socket, fixture state dir, `--tools Read`): the conversation
  resumed and fixture lines arrived as `← eye-sbx: …`. A session whose prompt does not explain the channel may flag its
  lines as prompt injection; the brain's brief must say the ear is the channel.
- `--continue` does not resume a `claude -p` conversation ("No conversation found to continue").
- A launch shows every dialog in turn: trust (new dir only), channels, then any `settings.json` warning. An invalid
  `permissions.allow` rule shows a "Settings Warning" on every launch, which blocks `notes-brain-arm` (it waits for the prompt box).

## Trust dialog in `~` (T45, 2026-09-22)

- Claude Code 2.1.280 keeps home-directory trust **session-only**: accepting the dialog in `~` never writes
  `projects["$HOME"].hasTrustDialogAccepted` in `~/.claude.json` (it stays `false`), so the orchestrator sees the dialog on every launch.
- Fix is script-side: `eye-channel-accept` answers it. Hand-editing `~/.claude.json` was rejected: it defeats a deliberate
  product choice, races the running session's own writes to that file, and a later version may reset it.
- Symptom before the fix: `systemctl --user start claude-orchestrator` sat 60 s in `ExecStartPost`, then tmux `claude` exited.

## Known windows

- Relay killed with SIGKILL or crashing mid-poll: ≤ 1 line (the bus gives it to the dead poll). A normal stop or restart drains.
- The Claude process dying after a push is written but before it is read: that push. Claude Code sends no ack.
- `eye-channel` killed between a push and its offset save: 1 duplicate, never a loss.
- The spool is never trimmed (≈100 B a line). To trim, stop the brain's session and empty both `<brain>.spool` and `<brain>.offset`.

## Checks

- Selftest (fixture bridge on the body's own `queue.js`; random port and secret, a temp state dir, 0 connections to the real bridge asserted):
  `TMPDIR=<scratch> ~/agents/eye-relay/tests/selftest.sh [N] [gap_s]` (`EYE_RELAY_POLL_MS=50000` for real timing).
- Idle (measured 2026-09-22): relay 17.7 MB RSS unsubscribed and 18.6 MB subscribed, 10–20 ms of CPU per minute. `eye-channel` 12.6 MB, 10 ms of CPU per minute.
