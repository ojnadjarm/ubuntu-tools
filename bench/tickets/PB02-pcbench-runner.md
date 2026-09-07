# PB02 — `pcbench`: the runner, the trajectory parser, the fingerprint, the report

**Phase PB · Model: opus · Estimated agent time: 3 h · Depends on: PB01 (command line and transcript shape)**

## Goal
One CLI, `~/agents/bin/pcbench`, that runs a task pack against an arm N times, one trial at a
time, and turns each trial into one JSON row: pass/fail from the task's checker, the trajectory
metrics of PLAN-PCBENCH §2.5 (wall, API time, turns, tokens, cost, tool calls, `pc` verbs,
screenshots, raw recipes, guard hits, `--apply`/ledger lines, KB whole-file reads, owner
disturbance events, residue), and the pre/post machine fingerprint diff. `pcbench report`
turns rows into the markdown table of §2.9. Testable with a fake `claude` (fixture transcripts),
no model call.

## Ground rules
PLAN-PCBENCH §2.6–§2.9 verbatim. Python 3 (stdlib only; `psutil` allowed), one file plus a
`pcbench.d/` helper dir — no daemon, no new dependency (promptfoo/Inspect rejected in PLAN §1.B).
Trials are **sequential** under `flock ~/agents/bench/.lock`; the runner refuses to start while
an `agent@*.service` is active or within 10 min of a fleet timer (`systemctl --user list-timers`).
Night rules for the runner itself: it never opens a window, speaks, or touches the TV; a task's
own `set:` field gates what the trial may do. Tests in `~/agents/bin/tests/pcbench.test.sh`
(`run.sh` picks it up). Never `git commit`/`push`.

## Context
- Trial command (PB01 fixes the exact form): `bwrap … claude -p "$PROMPT" --model $MODEL
  --output-format stream-json --verbose --permission-mode bypassPermissions --setting-sources
  <per PB01> --disallowedTools Agent --append-system-prompt-file ~/agents/bench/TRIAL-PREAMBLE.md
  --json-schema "$(jq -c .answer_schema task.json)" --max-turns $TURNS --max-budget-usd $USD`,
  under `timeout $SECONDS`, cwd `~/agents/bench/runs/<run>/<task>/<arm>/<i>/`, stdout →
  `stream.jsonl`. `--name pcbench-<task>-<arm>-<i>`.
- Metrics from `stream.jsonl` only (the `~/.claude/projects` transcript is a fallback): the
  `result` record gives `duration_ms duration_api_ms num_turns total_cost_usd usage modelUsage
  structured_output permission_denials`; `assistant` records give `tool_use` blocks
  (name + input) and per-message `usage`; `user` records give `tool_result` (exit codes, the
  `FLEET §5` refusal line, `rollback: pc undo` lines).
- Classifier regexes (one table in `pcbench.d/classify.json`, editable): `screenshot` = Bash
  matching `pc (shot|wait [0-9]|find|click-text)` or a `Read` of a `.png`; `pc_verb` = first
  word after `pc `; `raw_recipe` = `top -b|ps aux|ps -eo|pactl (move-sink-input|set-default-sink)
  |wpctl set-default|journalctl|dmesg|docker (ps|inspect|stats)|systemctl (list|status)|ss -|
  sensors|cat /proc/` **when the arm has the equivalent `pc` verb** (a per-arm map); `kb_whole`
  = `Read` or `cat` of `toolbox.md|quirks.md|RUNBOOK.md|README-pc-control.md`; `guard_hit` =
  tool_result containing `FLEET §5`; `apply` = `--apply` in a Bash input; `disturb` = `eye
  speak|pc (open|notify|type|key|click)|wpctl set-volume|pactl set-sink-volume|eye tv on`
  outside a `set: day` task → hard fail.
- Fingerprint (before/after every trial, `pcbench.d/fingerprint.sh`, ≤ 0.5 s): `pactl
  get-default-sink`, `pactl list short sinks|modules|grep null`, `powerprofilesctl get`,
  `systemctl --user --failed --no-legend | wc -l`, `docker ps -a --format '{{.Names}} {{.Status}}'
  | sort | md5sum`, `gdctl show | md5sum`, `tailscale status --json | jq .BackendState`,
  `sudo -n ufw status | head -1`, `tmux has-session -t claude`, `pc mode`, `pc win list | md5sum`,
  `wc -l < ~/agents/log/changes.jsonl`, `uptime -s`, `git -C ~/the-dark-eye rev-parse HEAD`.
  Any diff outside the task's `allowed_side_effects` → `side_effect: true` and pass forced 0.
- Row schema (`trial.json`): `{run, task, tier, arm, i, model, pass, checker_exit, side_effect,
  disturb, residue, wall_s, api_s, turns, tool_calls, bash_calls, pc_calls, pc_verbs{}, screenshots,
  raw_recipes, kb_whole, guard_hits, applies, ledger_lines, undo_ok, tokens{in,out,cache_r,cache_w},
  cost_usd, answer, timed_out, budget_hit}`; rows appended to `runs/<run>/rows.jsonl`.

### Survey (research first)
- Exists: promptfoo (`python:` provider + `--repeat`, web matrix), Inspect AI (`sandbox_agent_bridge`,
  API-key routing), Harbor (docker-only, ATIF trajectories), `claude plugin eval` (early-access
  gate, arms are with/without plugin), `agent-run` (one run, no metrics beyond cost).
- Chosen: a ~300-line Python `pcbench` around `claude -p --output-format stream-json`.
- Why: every option still needs the same custom classifier over tool calls; the extras
  (viewer, provider plumbing, node/uv dependency, API-key routing instead of OAuth) buy nothing
  the phone-readable markdown report needs. PLAN-PCBENCH §1.B has the full table.

## Steps
1. `pcbench list [--set night|day] [--tier T]`, `pcbench validate` (every task dir has
   `task.json` + `setup.sh` + `check.sh` + `teardown.sh`, schema keys present, `answer_schema` is
   valid JSON schema, `set`/`tier` in the enum), `pcbench arm status` (which arm dirs exist;
   PB03 builds them).
2. `pcbench run --arm old|new [--set night] [--task ID…] [-n N] [--model M] [--dry-run]`:
   guard (flock, no `agent@*` active, timer distance), per trial: fingerprint → `setup.sh` →
   trial → `check.sh <answer.json> <stream.jsonl>` → `teardown.sh` → fingerprint → residue
   (`pc doctor --quick --json` residue row + `systemctl --user list-units 'pcbench-*'`,
   `pactl list modules short | grep -c pcbench`, `docker ps -a --filter name=pcbench`) → row.
   `--dry-run` runs setup/check/teardown with a canned answer and no model (the pack's own test).
3. `pcbench parse <stream.jsonl>` → the metric object (used by 2; the unit under test).
4. `pcbench report <run>… [--baseline]`: per-arm table (pass rate, pass^N per task, median
   wall/turns/tool calls, screenshots per task, raw recipes, guard hits, residue, cost) and the
   delta table; `--baseline` rewrites the block between `<!-- pcbench:begin/end -->` in
   `~/agents/bench/BASELINE-PCBENCH.md` and writes `~/agents/bench/LAST.json` (the digest row).
5. Tests: fixture `stream.jsonl` pairs from PB01's spike (+ one synthetic with a guard hit, a
   screenshot Read and a `--apply`) → exact expected metric objects; a fake `claude` on PATH
   (`tests/fixtures/pcbench/bin/claude` that cats a fixture) drives one `pcbench run --task D01
   -n 1` end to end with the real `setup.sh`/`teardown.sh` (transient unit, < 5 s) and asserts the
   row, the fingerprint equality and zero residue.

## Success check
```bash
pcbench validate && pcbench list --set night | wc -l              # ≥ 12 once PB04/PB05 land
PATH=~/agents/bin/tests/fixtures/pcbench/bin:$PATH pcbench run --task D01 -n 1 --arm new --model fake
jq '.pass,.tool_calls,.screenshots,.residue' ~/agents/bench/runs/*/rows.jsonl | tail -4
pcbench report "$(ls -d ~/agents/bench/runs/* | tail -1)" | head -20
bash ~/agents/bin/tests/run.sh                                     # green
systemctl --user list-units 'pcbench-*' --all --no-legend | wc -l  # 0
```

## Rollback
Delete `~/agents/bin/pcbench`, `~/agents/bin/pcbench.d/`, the test and fixtures; `rm -rf
~/agents/bench/runs`. No shared file is edited by this ticket.
