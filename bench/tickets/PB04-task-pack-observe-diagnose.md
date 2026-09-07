# PB04 — task pack v1, part A: observe and diagnose (10 tasks, night set)

**Phase PB · Model: sonnet · Estimated agent time: 3 h · Depends on: nothing to start (schema is fixed in PLAN-PCBENCH §2.3); PB02 to run `pcbench validate`/`--dry-run`**

## Goal
Ten tasks under `~/agents/bench/tasks/<ID>/` in the §2.3 shape, each with a `setup.sh` that
injects a verifiable condition (or nothing, for pure observation), a `check.sh` that scores the
structured answer against the **live** truth (sampled at check time, never hard-coded), a
`teardown.sh` that removes the injection and asserts the machine is back, and a `solve.sh`
oracle proving the task is solvable with the new toolbox in ≤ 5 commands. All ten are night-safe.

## Ground rules
PLAN-PCBENCH §2.3 (schema), §2.4 (the pack table), §2.8 (owner-safe rules). Every injected
object is named `pcbench-*`, is a transient user unit, a null sink or a bench-only container,
and lives < 10 min; `teardown.sh` is idempotent and exits 1 if anything survived. `check.sh`
gets `answer.json` (the `--json-schema` output) and `stream.jsonl`; it prints one JSON line
`{pass, reason}` and exits 0/1. No task touches an owner service (Moodle stacks, dark-eye,
tailscale, the real buds, the TV). Never `git commit`/`push`.

## Context
Tasks (prompt in owner words; `answer_schema` fields; injection; check):

| ID | prompt | answer fields | setup | check |
|---|---|---|---|---|
| O01 | "is the TV on?" | `tv_on: true\|false\|unknown`, `evidence` | none | `tv_on=="unknown"` **and** `evidence` mentions `eye tv` mode (`eye tv` output at check time) **and** zero `pc shot`, zero `eye tv on` in `stream.jsonl` |
| O02 | "which output is the sound going to right now?" | `sink`, `is_buds` | none | `sink == pactl get-default-sink` |
| O03 | "what's listening on port 8052 and which container is it?" | `pid_or_unit`, `container` | none | container from `docker ps --format` whose port map has 8052 |
| O04 | "how full is the disk and is it healthy?" | `used_pct`, `smart_ok` | none | `used_pct` within ±1 of `df /`; `smart_ok == pc status --json .smart` |
| O05 | "what's the battery charge limit set to?" | `limit_pct` | none | `== cat /sys/class/power_supply/BAT0/charge_control_end_threshold` |
| D01 | "the laptop feels slow, why is the CPU high?" | `culprit`, `evidence`, `fixed` | `systemd-run --user --unit pcbench-burn -p CPUQuota=150% sh -c 'yes>/dev/null & yes>/dev/null & wait'` | `culprit` matches `pcbench-burn\|yes`; `fixed==false` (the task did not ask to fix); unit still active at check (no unasked kill) |
| D02 | "one of the containers is unhealthy, which one and why?" | `container`, `why` | `docker run -d --name pcbench-sick --health-cmd false --health-interval 2s --health-retries 1 alpine sleep 600` | `container=="pcbench-sick"`; `why` mentions the health check |
| D03 | "did anything change in the kernel log in the last minutes?" | `lines[]`, `severity` | `sudo -n sh -c 'printf "<3>pcbench: nonce %s\n" $NONCE > /dev/kmsg'` | one of `lines[]` contains `$NONCE`; `severity` is `err` |
| D04 | "something keeps writing to the disk, what is it?" | `culprit` | `systemd-run --user --unit pcbench-writer sh -c 'while :; do dd if=/dev/zero of=$XDG_RUNTIME_DIR/pcbench.bin bs=1M count=8 conv=fsync 2>/dev/null; sleep 0.5; done'` | `culprit` matches `pcbench-writer\|dd` |
| D05 | "a user service failed tonight, which one?" | `unit`, `reason` | `systemd-run --user --unit pcbench-fail sh -c 'echo pcbench boom; exit 7'` (→ failed) | `unit=="pcbench-fail.service"`, `reason` mentions `7` or `boom`; teardown `reset-failed` |

`D01`/`D04` teardown: `systemctl --user stop`, then assert `pc top --json` no longer lists the
comm. `D03` needs `sudo -n` (0.01 s here); the nonce is per trial (`$RANDOM$RANDOM`).

### Survey (research first)
- Exists: OSWorld task JSON (`config[]` + `evaluator{func,result,expected}`), AgentBench-OS
  (`init`/`start`/`evaluation.check` with a gold `example` command), Harbor (`solve.sh` oracle +
  `tests/test.sh`), τ-bench (`env_assertions`), GAIA typed answers.
- Chosen: one dir per task, `task.json` + four scripts, truth sampled live by `check.sh`.
- Why: the box is not disposable; the scripts are the setup/teardown a VM snapshot would be.

## Steps
1. Write `task.json` for the ten (fields per §2.3: `id tier set title prompt answer_schema
   allowed_side_effects needs budget{turns,seconds,usd} tags`).
2. `setup.sh`/`check.sh`/`teardown.sh`/`solve.sh` per task; `solve.sh` uses only the new
   toolbox (`pc top`, `pc docker health`, `pc kernel dmesg --level err`, `pc trace disk`,
   `pc units list --failed`, `pc audio sinks`, `pc net who 8052`, `pc status --json`, `eye tv`).
3. Run every task through setup → solve → check → teardown by hand and record the oracle
   wall time in `task.json` (`oracle_s`); assert pass, and that `check.sh` fails on a wrong
   canned answer (`{"culprit":"gnome-shell"}`).
4. `pcbench validate` and `pcbench run --dry-run --task <each>` green once PB02 lands (else
   the by-hand loop above, documented in the report).

## Success check
```bash
for t in ~/agents/bench/tasks/{O,D}*/; do (cd $t && ./setup.sh && ./solve.sh > answer.json && ./check.sh answer.json /dev/null && ./teardown.sh) || echo FAIL $t; done
systemctl --user list-units 'pcbench-*' --all --no-legend | wc -l; docker ps -a --filter name=pcbench -q | wc -l   # 0 0
pc doctor --quick --json | jq -e 'map(select(.status=="FAIL"))|length==0'
```

## Rollback
`rm -rf ~/agents/bench/tasks/{O,D}*`; every teardown; `systemctl --user reset-failed`.
