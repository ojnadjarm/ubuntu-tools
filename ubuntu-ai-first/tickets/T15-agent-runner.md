# T15 — Agent runner: scheduled headless Claude agents under systemd

**Phase 3 · must · Model: opus · Estimated agent time: 90 min**

## Goal
A persistent agent is a folder `~/agents/<name>/` with a `BRIEF.md`; one systemd user timer runs it with `claude -p --model opus`, keeps logs and a report, notifies the owner on failure, and can be listed/stopped with one command.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Claude native binary `~/.local/bin/claude` (no node needed). `claude -p` flags available: `--model`, `--permission-mode bypassPermissions`, `--output-format json`, `--max-budget-usd`, `--name`, `--append-system-prompt-file`, `--no-session-persistence`. Auth is the OAuth account in `~/.claude.json`; check that a `-p` run works from a non-login shell first (`env -i HOME=$HOME PATH=... claude -p "say ok"`).
- Session env for desktop/browser tools: `~/agents/bin/env.sh`. Playwright wrapper `~/agents/bin/playwright-mcp` (T12). `notify-owner` (T04). Linger is on (T03).
- Hooks in `~/.claude/settings.json` also run in `-p` mode (SessionStart injects ADHD rules and the machine brief) — fine.
- `~/CLAUDE.md` says persistent agents live under `~/agents/<name>/` and the roster table is in that file (T19 fills it).

## Steps
1. Layout per agent: `~/agents/<name>/BRIEF.md` (the prompt), `agent.env` (optional: `MODEL`, `BUDGET_USD`, `TIMEOUT`, `ON_CALENDAR`), `state/` (agent-owned scratch), `logs/YYYY-MM-DD-HHMM.log` + `.json` (`--output-format json`), `REPORT.md` (last run: start, end, exit, cost, 5-line summary written by the agent itself — the brief template tells it to).
2. `~/agents/bin/agent-run <name>`: sources `env.sh` and `agent.env`, prepends a standard system prompt file `~/agents/AGENT-PREAMBLE.md` (who you are, where to log, call `pc status` first, use `notify-owner` only for the cases the brief allows, write REPORT.md, never git commit), runs `claude -p` in `~/agents/<name>` with `--model ${MODEL:-opus} --permission-mode bypassPermissions --name agent-<name>`, tees output, records exit code and duration into `logs/index.tsv`, and on non-zero exit sends `notify-owner -p high "agent <name> failed: see logs"`.
3. systemd user templates `~/.config/systemd/user/agent@.service` (`ExecStart=%h/agents/bin/agent-run %i`, `TimeoutStartSec=${TIMEOUT:-3600}` via a default of 1 h, `MemoryMax=8G`, `Nice=5`, `WorkingDirectory=%h/agents/%i`) and `agent@.timer` (`OnCalendar` supplied per instance through a drop-in `agent@<name>.timer.d/schedule.conf` written by `agent-enable`). `agent-enable <name> "<OnCalendar>"`, `agent-disable <name>`, `agent-now <name>` (`systemctl --user start agent@<name>`).
4. `agents-status`: table of agents (name, enabled, schedule, next run, last run, last exit, last duration) from systemd + `logs/index.tsv`; `agents-stop` kill switch: stops all `agent@*` units and `claude agents` background sessions, disables timers, sends one push.
5. Create a trivial `~/agents/hello/BRIEF.md` ("run pc status, write REPORT.md with 3 lines, exit") to prove the pipeline; disable its timer afterwards (keep the folder as the template). Document the layout in `~/agents/README.md` (T19 extends it).

## Success check
```bash
agent-enable hello "*:0/30" && agent-now hello && sleep 90 && agents-status   # hello: last exit 0
cat ~/agents/hello/REPORT.md                                                 # 3 lines written by the agent
systemctl --user list-timers | grep agent@hello
agent-disable hello && agents-status | grep hello                            # disabled
agents-stop; echo exit=$?                                                    # 0, one push received
```

## Rollback
Disable all `agent@*` timers; delete the templates, `~/agents/bin/agent-*`, `agents-*`, `~/agents/hello`.
