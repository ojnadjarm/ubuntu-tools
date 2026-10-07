# Show a subagent as an orbiter (orbit-lite)

Ticket: T58 · Last verified: 2026-08-28 by `bin/tests/orbit-lite.test.sh`

## When to use
A subagent should appear on the Eye with the Agent call's description as its label.

## The path we took
The SubagentStart hook runs `orbit-lite start` with the hook JSON on stdin. The label is `description` from
`<transcript_dir>/agent-<id>.meta.json`; without it the label is the agent type. Posts go to `$ORBIT_OUT`.
Real hook timings are in `log/orbit-lite.log` (one line per start: hook time, meta file time, label posted).

## Links
- Code: `bin/orbit-lite` · Tests: `bin/tests/orbit-lite.test.sh` · Timings: `log/orbit-lite.log`
