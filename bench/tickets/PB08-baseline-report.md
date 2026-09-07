# PB08 — `BASELINE-PCBENCH.md`: the first report, in the owner's terms

**Phase PB · Model: sonnet · Estimated agent time: 1.5 h · Depends on: PB07**

## Goal
`~/agents/bench/BASELINE-PCBENCH.md` holds the first A/B in the shape of PLAN-PCBENCH §2.9:
the headline (pass rate and Completion-under-Policy per arm), the per-tier table, the
trajectory deltas (wall, tool calls, screenshots, raw recipes, guard hits, residue, cost),
pass^3 per task, and a ≤ 10-line "what this proves / what it does not" section the owner can
read on the phone. Plus the wiring so the next run appends rather than rewrites: the
`<!-- pcbench:begin/end -->` block for the latest table, dated headings for history.

## Ground rules
Numbers only from `rows.jsonl`; no hand-edited figures. Any task where the **oracle** failed
in either arm is excluded from the headline and listed as "task broken" (Epoch's OSWorld
lesson). Keep the file under 200 lines. Never `git commit`/`push`.

## Context
- `pcbench report --baseline` (PB02) writes the block; this ticket writes the prose around
  it and the task-level appendix (one line per task: pass^3 old / new, median wall, screenshots).
- Also: one paragraph in `~/agents/KB/toolbox.md` §6 ("the bench: `pcbench run --set night`,
  read `BASELINE-PCBENCH.md` before claiming the agents got better"), one line in
  `README-pc-control.md`'s PT section, `pc explain pcbench` resolving (the KB paragraph gives it
  a heading), and a memory note for the orchestrator (`~/.claude/projects/-home-oscar-nadjar/memory/`)
  that the metric now exists.

## Steps
1. `pcbench report <run> --baseline`; read `rows.jsonl` for outliers (timeouts, budget hits,
   `disturb` flags) and list them.
2. Write the prose: headline, per tier, the five sample tasks from the owner's proposal
   (D01 CPU, C01 buds, D02 container, D03 kernel log, O01 TV) as their own small table,
   the delta table, "proves / does not prove", and "next tasks worth adding".
3. KB/README/memory lines above.

## Success check
```bash
head -30 ~/agents/bench/BASELINE-PCBENCH.md
grep -c 'pcbench:begin' ~/agents/bench/BASELINE-PCBENCH.md      # 1
pc explain pcbench | head -3
wc -l < ~/agents/bench/BASELINE-PCBENCH.md                        # ≤ 200
```

## Rollback
Delete the file; revert the paragraph in `toolbox.md` and the README line.
