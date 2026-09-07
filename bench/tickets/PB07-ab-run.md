# PB07 — the A/B run: old vs new, night set, N=3, model held constant

**Phase PB · Model: sonnet (the runner is deterministic; the trials run the fleet model) · Estimated agent time: 1 h, plus ~6 h of machine time · Depends on: PB02, PB03, PB04, PB05**

## Goal
`~/agents/bench/runs/<ts>-ab/` with `rows.jsonl` for 20 night tasks × 2 arms × 3 trials
(120 trials), the fleet model (`opus`, as `agent-run` uses) in both arms, sequential, started
after 23:30 and finished before `moodle-keeper` at 04:30 — or split over two nights with the
same run id. Every trial's `setup`/`teardown` verified by the runner, zero residue at the end.

## Ground rules
PLAN-PCBENCH §2.6 (protocol) and §2.8 (night rules). The runner refuses to start if the owner
is active (`pc mutter idle` < 10 min **and** TV mode not `off`) or any `agent@*` is running;
it pauses for the `sentinel-check` tick (no trial may start within 60 s of `:00/:15/:30/:45`)
so an injected fault is never "repaired" mid-trial. Budgets per trial: `--max-turns 40`,
`--max-budget-usd 1.50`, `timeout 480`. Arms interleaved per task (`old,new,old,new,…`) so
drift over the night hits both equally. Never `git commit`/`push`. Push the owner only if the
run aborts.

## Context
- Sequence per task: `pcbench run --arm old --task T -n 3` then `--arm new`, interleaved by
  the `--ab` flag (`pcbench run --ab --set night -n 3 --model opus --run <ts>-ab`).
- Expected cost: ~120 × ≤ $1.50 ⇒ cap the run at `--max-budget-usd-total 150`; the runner
  stops and reports partial rows when the cap is reached.
- `sentinel-runaway` rule 1 kills scratchpad shell loops > 60 min — bench units are transient
  user units, not scratchpad loops; `pcbench run --dry-run --set night` on the evening before
  proves every setup/teardown pair in < 15 min total and shows nothing in the sentinel log.

### Survey (research first)
- Exists: OSWorld "k runs averaged, fixed max steps", τ-bench pass^k, Harbor `--n-attempts`.
- Chosen: N=3, pass^3 per task, medians for the trajectory metrics, arms interleaved.
- Why: N=3 is the smallest N where pass^k separates flaky from solid; 120 trials fits one night.

## Steps
1. Evening: `pcbench arm build old && pcbench arm build new`; `pcbench validate`;
   `pcbench run --dry-run --set night`; `pc doctor` PASS; note `agents-status`.
2. 23:30: `pcbench run --ab --set night -n 3 --model opus --run <ts>-ab` under `nohup`
   in the bench dir (not the tmux session `claude`); the runner writes `progress.txt`
   (`trial i/120 task arm state`) every trial.
3. Morning: `pcbench report <run>`; `pc doctor`; `systemctl --user list-units 'pcbench-*'`;
   `pactl list modules short | grep -c PCBENCH`; `docker ps -a --filter name=pcbench`;
   `tail ~/agents/log/changes.jsonl` (only paired lines).
4. Hand the run id to PB08.

## Success check
```bash
wc -l < ~/agents/bench/runs/*-ab/rows.jsonl                       # 120 (or the partial count with the reason in progress.txt)
jq -s 'map(select(.residue>0 or .side_effect)) | length' ~/agents/bench/runs/*-ab/rows.jsonl   # 0
pcbench report "$(ls -d ~/agents/bench/runs/*-ab | tail -1)" | head -40
```

## Rollback
Nothing to roll back: the run only appends under `~/agents/bench/runs/`; every task's
teardown ran. If the run aborted mid-trial: `pcbench cleanup` (every teardown, reset-failed,
unload PCBENCH sinks, `docker rm -f pcbench-*`).
