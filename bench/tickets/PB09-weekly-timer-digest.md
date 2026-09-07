# PB09 — `pcbench-weekly.timer`: the night set every week, one row in the digest

**Phase PB · Model: sonnet · Estimated agent time: 1.5 h · Depends on: PB02, PB08**

## Goal
A fleet timer runs the night set against the **current** toolbox once a week, appends to
`BASELINE-PCBENCH.md`, writes `~/agents/bench/LAST.json`, and the 08:00 `sentinel-digest`
carries one line (`bench: 17/19 pass, CuP 0.89, 2 regressions: D04 C03`). Kill switch and
roster rules apply like any other timer.

## Ground rules
Plain bash timer like `sentinel-check.timer`/`moodle-keep-weekly.timer` (the runner is
deterministic; only the trials are `claude -p`), not an `agent@` unit. Schedule inside the
quiet window and away from the other timers: **Wed 01:30** (`moodle-keeper` 04:30,
`maintenance` Sun 04:00, `moodle-keep-weekly` Sun 05:00). N=1, new arm only, `--model` = the
fleet model, total cap `--max-budget-usd-total 25`, wall cap 2 h (`TimeoutStartSec=7200`).
Regressions are reported, never pushed (the digest is the channel); a push only if the run
aborts with residue. `agents-stop`/`agents-start` must include the new timer. Never
`git commit`/`push`.

## Context
- `~/.config/systemd/user/pcbench-weekly.{service,timer}`: `ExecStart=%h/agents/bin/pcbench
  run --set night -n 1 --arm new --weekly` (`--weekly` = rebuild the `new` arm, refuse if the
  owner is active or an `agent@*` runs, retry once 30 min later, then give up quietly).
- `agents-stop`/`agents-start` list their timers by name — add `pcbench-weekly.timer`; the
  roster table in `~/CLAUDE.md` gets one row (the orchestrator edits it; leave the row text
  in the report).
- `sentinel-digest/BRIEF.md`: one step, "read `~/agents/bench/LAST.json` if younger than 7 d;
  one line: pass, CuP, regressions vs the previous row".
- `pc doctor`: two rows — `pcbench-residue` (no `pcbench-*` unit, sink, container) and
  `pcbench-last` (LAST.json younger than 8 d, or SKIP before the first run).

### Survey (research first)
- Exists: `agent-enable` (for `agent@` units), the two bash timers, `pc doctor`'s row format.
- Chosen: bash timer + two doctor rows + one digest line.
- Why: identical to how the fleet already runs deterministic jobs; nothing new to learn.

## Steps
1. Units + `--weekly` behaviour in `pcbench`; `systemd-analyze verify`; `systemctl --user
   start pcbench-weekly.service` once by hand on a night with the owner asleep (or `--dry-run`
   by day) and read `LAST.json`.
2. `agents-stop`/`agents-start` + `agents-status` know the timer; digest BRIEF line; doctor rows.
3. Report the roster row for `~/CLAUDE.md`.

## Success check
```bash
systemctl --user list-timers pcbench-weekly.timer --no-pager    # Wed 01:30
jq . ~/agents/bench/LAST.json | head
agents-stop --dry-run 2>/dev/null | grep pcbench || grep -n pcbench ~/agents/bin/agents-stop
pc doctor --quick --json | jq -r '.[]|select(.name|startswith("pcbench"))|"\(.name) \(.status)"'
bash ~/agents/bin/tests/run.sh
```

## Rollback
`systemctl --user disable --now pcbench-weekly.timer`; remove the units, the two doctor rows,
the digest line and the `agents-*` entries.
