# Audit log — `~/agents/log/actions.jsonl`

One JSON object per line, one line per tool call, appended by whichever agent is running.
Read it with `agents-log [--since 2h] [--session ID] [--grep X] [--stats] [--pc] [--raw]`; never parse it
by hand. The file is machine-local and is never committed.

## Fields

| Field | Type | Meaning |
|---|---|---|
| `ts` | string | local time, `%Y-%m-%dT%H:%M:%S%z` |
| `session` | string | the agent session id, first 8 characters (empty when the agent has none) |
| `cwd` | string | working directory of the call |
| `tool` | string | tool name as the agent names it (`Bash`, `Edit`, `Write`, `mcp__…`) |
| `op` | string | searchable verb: for `Bash`, the command basename + its first argument (≤40 chars); otherwise the tool name |
| `summary` | string | redacted detail: the command line (≤500), the MCP arguments (≤200), or the file path (≤500) |

## Redaction

`hooks/audit-log.py` redacts before writing: `token`/`password`/`secret`/`api_key`/`authorization`
assignments, `bearer …`, `--password=`, `-p<value>`, and key-shaped literals (`sk-`, `ghp_`, `xoxb-`,
`github_pat_`, …) become `<redacted>`. Cases live in `bin/tests/audit-redact.test.py` — add one there
before trusting a new secret shape.

## Who writes it

- **The core** is `~/agents/hooks/audit-log.py`, agent-agnostic. It reads the generic event
  `{tool, input, cwd, session}` on stdin, or is imported for its `record(tool, input, cwd, session)`.
  It writes under `$HARNESS_HOME` and always exits 0 — an audit failure never blocks a tool call.
- **Each adapter maps its own agent's event shape onto that generic event.**
  - `adapters/claude/hooks/audit-log.py` — a PostToolUse hook; maps `tool_name`/`tool_input`/`cwd`/`session_id`.
  - `adapters/opencode/audit-from-stream` — a filter in `adapters/opencode/run`'s pipe, not a
    hook. Verified against opencode 1.18.29: a tool call is
    `{"type":"tool_use","part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{…}}}}`.
    Tool names are lowercase there and are mapped onto the canonical ones (`bash` → `Bash`), as is
    `filePath` → `file_path`. It only covers `agent-run` sessions, not an interactive TUI.
  - `adapters/codex/audit-from-stream`, `adapters/gemini/audit-from-stream` — filters for a
    line-delimited JSON event stream. **Stubs**: neither CLI is installed here, so their field
    names come from the documented shape and stay unverified.

To support a new agent, write one converter to the generic event. Nothing else changes.

## Token meter — `agents-log --tokens`

The audit log counts tool calls, not tokens. `agents-log --tokens [--since 7d] [--session ID]`
reads the Claude transcripts (`$CLAUDE_PROJECTS_DIR`, default `~/.claude/projects/*/*.jsonl`,
read-only) and prints one row per session: turns, mean/median/max context carried per turn
(`input` + `cache_read` + `cache_creation`), total cache-read (M) and output (k), images, Read
re-reads of the same path, and tool-result KB by tool (top 3); then a TOTAL row and one line per
day. `--since` keeps a session whose **last** turn is inside the window and still reports its whole
history, so the row matches the session, not the window. Unknown line types are ignored, so a CLI
format change degrades instead of failing. `ccusage` reports 0 sessions on this box's transcript
format; `/usage` is interactive and per-session — hence this reader.
