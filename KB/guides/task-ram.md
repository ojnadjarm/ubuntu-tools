# Task RAM: per-ticket notes that survive a compaction

Ticket: T1841 · Last verified: 2026-11-23 by `bash bin/tests/ram.test.sh` (11/11) and `bash bin/tests/task-ram-hook.test.sh` (17/17)

## When to use
A ticket agent that would lose its findings, dead ends, decisions or next steps in a compaction: note them with `ram`;
the hook hands them back. Not for tool output, file contents, what the brief or repo already says, or lasting lessons
(those are `memory note`). Off (`TASK_RAM=off` in config.env) until T1842's verdict.

## The path we took
Design: `$AGENT_WORK/research/2026-11-23/T1839/design.md`. Notes live in `$AGENT_WORK/ram/T<n>/notes.md`, one line each
(`- HH:MM <kind> · <line> · <src>`, 240 characters at most, redacted by `lib/redact.py`), 4,096 B cap: the oldest
`done`, then `fact` lines move to `notes.old.md`. One hook, `adapters/claude/hooks/task-ram`, always exit 0:

| Event | Does |
|---|---|
| `SubagentStart` | brief path in the spawn prompt (spawn-context's finder, own ledger `task-ram.json`) to ticket; state `$XDG_RUNTIME_DIR/task-ram/<session>-<agent>.json`; start line (+ digest when notes exist); `ram gc` |
| `PostToolUse` (Bash) | no state and no `RAM_TICKET`: exit. `RAM_TICKET` and no state: start line. Else the last 256 KiB of the agent's transcript: an unseen `compact_boundary` gives the digest; else 70 % of the window, once per window, gives the warning |
| `SubagentStop` | `evidence/T<n>/check.json` ok: `ram close` |

Window: `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, then the agent definition's `autoCompactWindow`, then `settings.json`, else 200,000.

## Exact commands
```bash
ram note T<n> fact "retry limit is 5" --src lib/net.py:41   # kinds: fact tried decided next done
ram note T<n> next "run suite; fix case 3; write guide"       # one next slot, rewritten whole
ram show T<n>                                                  # digest: next, decided, tried, newest facts, 2,000 chars
ram close T<n>                                                 # notes.md -> $AGENT_WORK/evidence/T<n>/ram.md, folder removed
ram gc                                                         # folders untouched for 48 h removed
RAM_TICKET=F1 claude -p "..."                                  # headless run without a brief
TASK_RAM=on claude ...                                         # kill switch: the environment wins over config.env
```

## Pitfalls (measured)
- Note when you learn, drop or decide something you would not want to redo; at the 70 % warning, note the rest.
- The hook shares spawn-context's brief finder but must keep its own ledger, or one of the two loses the prompt.
- A transcript ending in an 8 MB image row: the tail read stays at 256 KiB and prints nothing (test case).
- Hook p95 on PostToolUse Bash: 17.3 ms with no ticket (hook-bench -n 50); audit-log beside it 14.9 ms.
- New CLI in ~/agents/bin: run `~/agents/install.sh --links` or live sessions get "command not found".

## Links
- Code: `bin/ram`, `adapters/claude/hooks/task-ram`, `adapters/claude/settings.fragment.json`
- Tests: `bash bin/tests/ram.test.sh`, `bash bin/tests/task-ram-hook.test.sh`
- Design / results: `$AGENT_WORK/research/2026-11-23/T1839/`
