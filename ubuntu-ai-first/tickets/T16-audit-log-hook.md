# T16 — Audit log of agent actions

**Phase 3 · must · Model: opus · Estimated agent time: 45 min**

## Goal
Every command and file change made by any Claude session on this machine is appended to one local log, so the owner and the sentinel can answer "what did the agents do last night" and self-repair can find the culprit.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Hooks live in `~/.claude/settings.json` (`SessionStart`, `Stop` already used by the Moodle harness). A `PostToolUse` hook receives JSON on stdin with `session_id`, `cwd`, `tool_name`, `tool_input`, `tool_response`. Use the `claude-code-guide` agent if the exact schema is in doubt.
- Log target: `~/agents/log/actions.jsonl`. Must never slow tool calls down (append only, < 20 ms, no network) and must never fail the tool (always exit 0).
- Machine-specific: do not sync into `~/moodle-harness`.

## Steps
1. `~/.claude/hooks/audit-log.sh`: python3 one-shot that reads stdin, writes one JSON line: ts, session_id, cwd, tool, and a compact summary (Bash: `command` truncated to 500 chars; Edit/Write: `file_path`; MCP tools: tool name + first 200 chars of input). Skip Read/Grep/Glob to keep the log small. `chmod +x`.
2. Register under `PostToolUse` with matcher `Bash|Edit|Write|MultiEdit|NotebookEdit|mcp__.*` in `settings.json` (merge with python, keep existing hooks and `effortLevel: medium`).
3. Rotation: logrotate user config or a daily check in the keeper (T18): keep 30 days, gzip.
4. `~/agents/bin/agents-log [--since 2h] [--session ID] [--grep X]`: pretty prints the log (time, session short id, tool, summary).
5. Add "audit log" to `~/agents/KB/machine.md`.

## Success check
```bash
claude -p --model sonnet "run: echo audit-test-$RANDOM" >/dev/null; tail -1 ~/agents/log/actions.jsonl | python3 -m json.tool | head   # contains the echo command
agents-log --since 10m | grep -c audit-test        # >= 1
python3 -c "import json;[json.loads(l) for l in open('$HOME/agents/log/actions.jsonl')];print('valid jsonl')"
```

## Rollback
Remove the `PostToolUse` entry from `settings.json`; delete the hook, `agents-log` and the log dir.
