# Audit log — `~/agents/log/actions.jsonl`

One JSON object per line, one line per tool call, appended by whichever agent is running.
Read it with `agents-log [--since 2h] [--session ID] [--grep X] [--kind agent|bench|interactive] [--errors [--all]] [--agent ID] [--stats] [--pc] [--raw]`; never parse it
by hand. The file is machine-local and is never committed.

## Fields

| Field | Type | Meaning |
|---|---|---|
| `ts` | string | local time, `%Y-%m-%dT%H:%M:%S%z` |
| `session` | string | the agent session id, first 8 characters (opencode's after its `ses_` prefix; empty when the agent has none) |
| `agent` | string | rostered agent name (`$AGENT_NAME`), `bench` for a pcbench trial (`$PCBENCH_RUN`), empty for an interactive session; `--kind` filters on it (a `/bench/runs/` cwd also counts as `bench`) |
| `cwd` | string | working directory of the call |
| `tool` | string | tool name as the agent names it (`Bash`, `Edit`, `Write`, `mcp__…`) |
| `op` | string | searchable verb: for `Bash`, the command basename + its first argument (≤40 chars); otherwise the tool name |
| `summary` | string | redacted detail: the command line (≤500), the MCP arguments (≤200), or the file path (≤500) |
| `ok` | bool | `true` for a PostToolUse row, `false` for a PostToolUseFailure row (Claude adapter); absent where the adapter cannot tell; `--errors` keeps the `false` rows |
| `error` | string | failed calls only: the redacted error text; past 400 chars the first 100 + `\n…\n` + the last 300 |
| `agent_id` / `agent_type` | string | the subagent or workflow lane the call ran in (Claude hook input); absent in the main session; `--agent ID` filters on the id prefix |

## Failure classes

`toolsmith-inputs` counts failed agent and interactive rows (bench rows apart as `bench_rows`), computes `failures.rate_pct` on `real` only, and clusters `real` only (`auditlib.error_class`, TSP-045):
- `guarded`: exit 97 or a `refused inside the … sandbox` line, the guard doing its job.
- `probe`: the status-setting command is a yes/no check answering no: `test`/`[`/`which` exit 1, `grep -q`/`diff -q`/`cmp -s`/`command -v` exit 1, `systemctl is-active|is-enabled|is-failed` exit 1 or 3.
- `red-first`: a `test FAIL` from a command line naming a `*.test.sh`/`*.test.py` file.
- `real`: everything else.

## Redaction

`hooks/audit-log.py` redacts before writing: `token`/`password`/`secret`/`api_key`/`authorization`/`*SECRET*KEY`/`*PRIVATE*KEY`/uppercase `PASS`
assignments (lowercase `pass=` counters are kept), `bearer …`, `--[…-]token|api-key|secret|pass[word]` followed by `=` or a space, `-p<value>` after `mysql*`/`mariadb*` (not `find -path`), `sshpass -p[ ]<value>`, the password in `curl -u/--user user:<value>` (each also when the value is quoted, up to the closing quote), the password in `scheme://user:<value>@` URLs, and key-shaped literals (`sk-`, `ghp_`, `xoxb-`,
`github_pat_`, …), `x-…-key` header values and 40+ hex literals after `=`/`:` (not `sha256:` digests) become `<redacted>`. MCP inputs are redacted value by value before JSON encoding, so secrets inside JSON-string fields are caught. Cases live in `bin/tests/audit-redact.test.py` — add one there
before trusting a new secret shape.

## Who writes it

- **The core** is `~/agents/hooks/audit-log.py`, agent-agnostic. It reads the generic event
  `{tool, input, cwd, session, agent}` on stdin, or is imported for its `record(tool, input, cwd, session, agent)`.
  It writes under `$HARNESS_HOME` and always exits 0 — an audit failure never blocks a tool call.
- **Each adapter maps its own agent's event shape onto that generic event.**
  - `adapters/claude/hooks/audit-log.py` — a PostToolUse hook; maps `tool_name`/`tool_input`/`cwd`/`session_id`.
  - `adapters/opencode/audit-from-stream` — a filter in `adapters/opencode/run`'s pipe, not a
    hook. Verified against opencode 1.18.29: a tool call is
    `{"type":"tool_use","part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{…}}}}`.
    Tool names are lowercase there and are mapped onto the canonical ones (`bash` → `Bash`), as is
    `filePath` → `file_path`. Like the codex/gemini stubs, it passes `$AGENT_NAME` as `agent`. It only covers `agent-run` sessions, not an interactive TUI.
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
day. A turn is one `message.id`: a reply split over several lines counts once, usage included. `--since` keeps a session whose **last** turn is inside the window and still reports its whole
history, so the row matches the session, not the window. Unknown line types are ignored, so a CLI
format change degrades instead of failing. `ccusage` reports 0 sessions on this box's transcript
format; `/usage` is interactive and per-session — hence this reader.

`--by ticket` (T552) prints one row per T-id found in each subagent's `agent-*.meta.json`
`description` (worker and workflow lanes; no T-id → `untagged`; main sessions left out): turns,
cache-read M, cache-write M, output k, wall min (first to last turn) and agents, sorted by cache-read,
then a TOTAL. `--errors --cluster` has an `agents` column (distinct session + `agent_id`).
