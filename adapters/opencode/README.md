# OpenCode adapter

`HARNESS_AGENT=opencode`. Verified end to end against **opencode 1.18.29** on this machine
(GH16): `agent-now hello` produced a `REPORT.md`, an `index.tsv` row, audit entries and a push.

## Install the CLI

```bash
curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path   # -> ~/.opencode/bin
```

No sudo, no node: the installer drops one static binary. `~/.opencode/bin` is not on the PATH
of a systemd shell, so `run` resolves the binary itself (`$OPENCODE_BIN`, then `command -v`,
then `~/.opencode/bin/opencode`). `opencode` ships free models that need no credential
(`opencode models`), which is what the GH16 smoke run used.

## Files

| File | What |
|---|---|
| `run` | the `agent-exec` contract → `opencode run --format json --auto`; writes `cost_usd`/`tokens` to `$META_OUT` and audits every tool call |
| `install` | symlinks `skills/*` into `~/.config/opencode/skills/`, adds `AGENTS.md` to `instructions` in `~/.config/opencode/opencode.json` |
| `uninstall` | reverses exactly those two |
| `audit-from-stream` | maps opencode's JSON events onto `hooks/audit-log.py`'s generic record; sits in `run`'s pipe |

## Flags `run` uses

`run --format json` (raw JSON events, one object per line), `--auto` (auto-approve permissions —
the analogue of Claude's `--permission-mode bypassPermissions`), `--model provider/model`,
`--title agent-<n>`, and the message as a positional after `--`.

Result text = every `part.type == "text"` event joined; `cost` and `tokens` come from
`part.type == "step-finish"`; tool calls are `part.type == "tool"` with
`part.tool` (lowercase) and `part.state.input`.

## Where the contract and the skills come from

`instructions` in `~/.config/opencode/opencode.json` loads `~/agents/AGENTS.md` in every session,
whatever the cwd. opencode would also find it by walking up from `~/agents/<name>/`, but the
config entry is what makes it work from any directory. Skills are read from
`~/.config/opencode/skills/<name>/SKILL.md`; the agentskills.io frontmatter this harness writes
(`name` + `description`) is exactly what opencode requires.

## What is lost against the Claude adapter

| Claude | opencode | Effect |
|---|---|---|
| `--append-system-prompt` | none | the system file (`AGENT-PREAMBLE.md`) is prepended to the message with a separator |
| `--max-budget-usd` | none | `BUDGET_USD` is ignored; the `--timeout` in `agent-exec` is the only cap |
| `--model opus` | `provider/model` | a bare model name in `agent.env` is ignored and opencode's default is used; set `OPENCODE_MODEL=provider/model` to pin one |
| `claude agents --json` | none | background runs are found through `<agent>/state/pid`, which `agent-exec` writes |
| PostToolUse hook | JSON event stream | auditing is a pipe in `run`, not a hook, so it only covers `agent-run` sessions — not an interactive `opencode` TUI |
| `orbit-hook` (the Eye's orbiters) | none | Claude-only, see `~/the-dark-eye` |
