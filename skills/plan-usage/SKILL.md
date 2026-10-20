---
name: plan-usage
description: Read the Claude plan limits (5-hour and weekly used %, reset times); gate with `plan-usage --check 80`. Use for "limits", "usage", "how much plan is left", "weekly %", "5-hour limit", "when does it reset", before big runs, every "Pulse:" prompt.
---

Triggers: plan's own numbers, endpoint /usage reads, lesson build, orchestrator.

# plan-usage

1. Run `plan-usage` (script: `~/agents/bin/plan-usage`; `--json` for fields, `--cached` without network).
2. Gate: `plan-usage --check 80` exits 1 when either window is at or above 80%, 2 when there is no reading.
3. Rules:
   - Lesson builds stop at **weekly 80%** (owner standing order).
   - The weekly reset time is printed; spare weekly budget before the reset is use-it-or-lose-it, so keep
     the standing queue moving while under 80%.
   - `source cache` = the live read failed; `stale` = older than 30 min. Say so, never present it as live.
4. Never print or copy the OAuth token; the script reads it and never echoes it.

Guide with pitfalls: `~/agents/KB/guides/plan-usage.md`. Hourly pulse: `orchestrator-pulse.timer`, log
`~/agents/log/pulse.log`, rules in `~/agents/KB/orchestrator.md` "Pulse".
