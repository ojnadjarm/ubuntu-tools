# Agent runner (technical reference)

A persistent agent is a folder `~/agents/<name>/` run headless by `claude -p` from a systemd
user timer. `~/agents/hello/` is the working template.

## Layout

| Path | What |
|---|---|
| `<name>/BRIEF.md` | the prompt (required — a folder without it is not an agent) |
| `<name>/agent.env` | optional `MODEL`, `BUDGET_USD`, `TIMEOUT` (seconds), shell syntax |
| `<name>/state/` | agent-owned scratch |
| `<name>/logs/YYYY-MM-DD-HHMMSS-xxxx.log` / `.json` | stderr + result text, and the raw `--output-format json` |
| `<name>/logs/index.tsv` | one row per run: start, end, exit, seconds, cost_usd, log |
| `<name>/REPORT.md` | last run: metadata written by the runner + up to 5 lines written by the agent |
| `~/agents/AGENT-PREAMBLE.md` | system prompt appended to every agent run |

## Commands (`~/agents/bin`, on PATH via `~/.local/bin`)

- `agent-run <name>` — one run, outside systemd (used by the unit; fine by hand).
- `agent-enable <name> "<OnCalendar>"` — writes `~/.config/systemd/user/agent@<name>.timer.d/schedule.conf`
  and enables the timer. The calendar expression is validated with `systemd-analyze calendar`.
- `agent-disable <name>` / `agent-now <name>` — stop the timer / run once through systemd.
- `agents-status` — name, enabled, schedule, next run, last run, last exit, last duration.
- `agents-stop` — kill switch: stops every active `agent@*.service`, every `agent@*.timer` plus
  `sentinel-check.timer`, `moodle-keep-weekly.timer` and `pcbench-weekly.timer` (stopped, not
  disabled), kills background
  `claude agents` sessions (never interactive ones), sends one high-priority push.
- `agents-start` / `agents-stop --resume` — re-enables exactly the units the roster in `~/CLAUDE.md`
  lists and prints `list-timers`.

## Units

`agent@.service` (`Type=oneshot`, `TimeoutStartSec=3600`, `MemoryMax=8G`, `Nice=5`,
`WorkingDirectory=%h/agents/%i`) and `agent@.timer` (`OnCalendar` only from the per-instance drop-in).
systemd runs one instance of a service at a time, so an overrunning agent cannot stack.
A non-zero exit sends `notify-owner -p high`.

## Bash timers (not `agent@`)

`sentinel-check`, `moodle-keep-weekly` and `pcbench-weekly` are plain bash runners on their own
`.timer`/`.service` pair, not `claude -p` agents — no `BRIEF.md`, no `agent-run`. `agents-stop`
stops them by name; `agents-start` re-enables them from the roster row's unit name in `~/CLAUDE.md`.

`pcbench-weekly` (PB09) runs the whole task pack A/B on Sunday 02:00, then
`pcbench report --baseline`. It never starts while the owner is at the machine: `pcbench away`
reads `pc status --json` (lock + idle, lid, MPRIS players, seat logins) and both the runner and
`pcbench run --require-away` refuse on a hit. A skip is logged to
`~/agents/log/pcbench-weekly.log`, counted in `bench/state/weekly-skips`, and pushes the owner
once at three in a row. `pcbench-weekly --dry-run` prints the verdict and the command.

## Adding an agent

1. `mkdir ~/agents/<name> && $EDITOR ~/agents/<name>/BRIEF.md`
2. `agent-now <name>` — check `REPORT.md` and `logs/`.
3. `agent-enable <name> "Mon..Fri 08:00"` and add the row to the roster in `~/CLAUDE.md`.

## Notes

- `agent-run` takes a `flock` on `<dir>/.lock`, runs with stdin closed, and traps TERM/INT so a
  killed run still writes its `index.tsv` row, cost and `REPORT.md`. `REPORT.md` is truncated at
  the start of every run and rebuilt from the runner metadata plus what the agent wrote.
- The audit hook's ~20 ms per-call latency is a soft target, not a hard limit.
- `sentinel-check` escalates one failure signature to Claude at most once per 6 h; bash fixes
  still run every 15 min and the owner is pushed once when suppression starts.
