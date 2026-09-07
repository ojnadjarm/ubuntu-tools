# Claude Code adapter

`HARNESS_AGENT=claude`. The reference adapter: everything the harness can do is wired here, and
the other adapters are measured against it.

## Files

| File | What |
|---|---|
| `run` | the `agent-exec` contract → `claude -p … --output-format json`; writes `cost_usd` and `tokens` to `$META_OUT` |
| `install` | symlinks `skills/*`, merges the hooks into `~/.claude/settings.json`, adds the `@AGENTS.md` include to `~/CLAUDE.md` |
| `uninstall` | reverses exactly those three, and nothing else |
| `merge-settings.py` | the idempotent JSON merge both use |
| `settings.fragment.json` | the hooks this harness owns, with `@HARNESS_HOME@` substituted at install time |
| `hooks/session-start.sh` | 2-line wrapper: `harness context --json` |
| `hooks/audit-log.py` | maps Claude's PostToolUse event onto `hooks/audit-log.py`'s generic record |

## Flags `run` uses

`-p <prompt>`, `--model`, `--permission-mode bypassPermissions`, `--name agent-<n>`,
`--append-system-prompt <AGENT-PREAMBLE.md>`, `--output-format json`, `--max-budget-usd`.
Cost comes from `.total_cost_usd`, tokens from `.usage`, the result text from `.result`.

## What `install` writes

Only the `hooks` key of `~/.claude/settings.json`, and only these four events:

| Event | Command | Replaces |
|---|---|---|
| `SessionStart` | `adapters/claude/hooks/session-start.sh` | `~/.claude/hooks/moodle-session-start.sh` **and** `machine-status.sh` — `harness context --json` emits exactly their merged output (proved by `bin/tests/harness-context.test.sh`) |
| `PostToolUse` | `adapters/claude/hooks/audit-log.py` | `~/.claude/hooks/audit-log.sh` (a symlink to the same file since GH09; `install` deletes it) |
| `SubagentStart` / `SubagentStop` | `bin/orbit-hook start` / `stop` | — (the Eye's orbiters; Claude-only, see `~/the-dark-eye`) |

`permissions` (including `defaultMode`, `allow` and `deny`), `model`, `effortLevel`,
`outputStyle`, the `Stop` hook owned by the Moodle harness and every other key are preserved
untouched. A second `install` prints `no changes`.

The `set-moodle-harness` skill no longer wires hooks itself — it verifies them and defers here.

## Not touched, ever

- `~/.claude/CLAUDE.md` — the user's own global instructions.
- `~/.claude/skills/eye/SKILL.md` — a symlink into `~/the-dark-eye`, a separate project.
- `~/.claude/hooks/*` owned by the Moodle harness (`moodle-*.sh`), and `~/.claude/settings.local.json`.

## Known Claude-only pieces

`orbit-hook` (the Eye's agent orbiters), the `Monitor`-tool listen loop used by the `eye` skill,
and `claude agents --json`, which `agents-stop` and `pc status` use to find background runs. Other
adapters must record their child PID in `<agent>/state/pid` (`agent-exec` does) for the kill
switch to reach them.

## Machine notes that live here, not in the KB (GH18)

These were in `KB/quirks.md`, `KB/toolbox.md` and `README-pc-control.md` until the docs wording
pass; they are true only for this adapter.

- The `claude` binary is `~/.local/bin/claude` and needs no node, so it works in the non-login
  shells systemd gives (`nvm`'s node is not on that PATH).
- `$HARNESS_CONTEXT_DIR` is `~/.claude`: the live copy of the **Moodle coding** harness whose git
  source is `~/moodle-harness` (edit live, then `~/moodle-harness/sync.sh`; never push).
  `hooks/machine-status.sh` there is machine-specific and stays out of that repo.
- The Playwright MCP is registered as
  `~/agents/bin/playwright-mcp --config ~/.claude/playwright-mcp.json` (user scope); MCP config
  changes reach only **new** sessions.
- The portable skills are symlinked into `~/.claude/skills/`; `~/.claude/skills/eye/SKILL.md` is
  a symlink into `~/the-dark-eye` and is never touched by `install`.
- `bin/baseline.sh` tars `$HARNESS_CONTEXT_DIR/{settings.json,hooks,skills,*.md}` before a config
  change.
- `claude agents --json` is what `agents-stop` and `pc status` use to find background runs, and
  `PushNotification` exists only in Remote Control; both are Claude-only (see the table above).
- The orchestrator unit `$ORCHESTRATOR_UNIT` (`claude-orchestrator.service` on this install) and
  the tmux session `$ORCHESTRATOR_TMUX_SESSION` (`claude`) keep their names by owner decision D5;
  `pclib.sh`'s guards read the config values, never the literals.
