# The notes brain

This directory is the notes brain's home. `BRIEF.md` is the contract for the session that
runs here. The orchestrator role and delegation sections of `~/CLAUDE.md` do not apply to this
session (it is not the orchestrator); the fleet contract in `~/agents/AGENTS.md` applies in full.

## Arming the first turn

`~/agents/bin/notes-brain-arm` is the unit's `ExecStartPost`: it waits for a stable prompt box,
types the first turn, presses Enter only once the prompt line echoes the turn whole, then verifies
`notes` is connected in `eye brains`. Up to three attempts, a turn already submitted is never
re-sent — a turn is retried only while it still sits on the input line, unsubmitted — and the
arming is checked once and then re-waited before the owner is pushed. It always exits 0 and
caps its own worst case (`notes-brain-arm --budget`, 181 s) under the unit's `TimeoutStartSec=300`,
so systemd cannot kill it and send `Restart=on-failure` into a loop. Fixture proof:
`tests/notes-brain-arm.test.sh` (transient frame, partially drained line, late turn, a turn
scrolled out of the visible pane, trust dialog, budget vs the source and synced unit's timeout).

The echo check assumes the terminal UI keeps the live input line as the last prompt-glyph line
(every stub models it that way, no test drives a real pane); if that ever changes it fails closed
— line cleared, owner pushed, nothing submitted.

The record: in the 2026-09-15 incident the journal says `no prompt box after 60 s (trust dialog?)
— nothing typed`. Nothing was typed and no keystroke was lost; the defect was giving up silently.
The dropped and partially drained panes in the fixture are plausible pane failures the script must
survive, not a replay of that incident.
