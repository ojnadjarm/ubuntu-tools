---
name: weekly-code-review
description: The fleet's weekly code-review swarm (agent@code-review, Sat 03:00). Use to run, selftest, read, undo or change it, or restore a retired tool or skill. Review lanes over ~/agents and skills, refuters per finding, test-first fixes, retirement with a one-line restore.
---

Triggers: 2 refuters, third on a split, 3 for removals, verified backups, not useful, never for low use, allowlist sandbox, fleet skills.

# weekly-code-review

Guide with the measured pitfalls: `~/agents/KB/guides/code-review-swarm.md`. Architecture: `~/agent-work/research/2026-09-24/T74/architecture.md`.

1. **Read the last run**: `cat ~/agents/code-review/REPORT.md`; full list `~/agents/code-review/state/runs/<run>/findings.md`
   (`<run>` = `<date>-<HHMMSS>`, the latest is in `state/current-run`).
2. **Undo a fix**: `code-review restore <run> <F-id>` (nothing is deleted: what the fix left goes to the backup's `displaced/`).
   **Bring back a retired item**: run column 3 of `~/agents/backups/retired/<date>/MANIFEST.tsv` (column 4 = why).
3. **Change what lanes may do**: edit `~/agents/code-review/LANES.md` (binding for every lane); areas, lenses and
   policy live in `lib/code_review/` (`common.AREAS`, `lanes.LENSES`, `policy.CONTAINMENT`, `policy.policy()`); orchestration in `code-review/swarm.js`;
   the sandbox in `bin/code-review-sandbox` (+ `code-review-netproxy`). The swarm itself can never edit these.
4. **Verify after any change**: `bash ~/agents/bin/tests/code-review.test.sh` (no model), then
   `bash ~/agents/code-review/selftest/run.sh` (real swarm on the seeded fixture; oracle + snapshot must pass).
5. **Run for real once**: `agent-now code-review` (hours; one push at the end). Never SendMessage to its workflow agents.

Rules: edits only where `code-review policy` says `edit`. Judge by usefulness, never by use counts: `code-review retire`
needs `--why broken|duplicate|superseded|obsolete` (+ `--by` and a side-by-side `--proof` for duplicate/superseded), no
remaining references, and all 3 refuters agreeing. A fix counts only after `code-review tests <id> after` prints verified.
Owner-go work goes to `improve/queue/CR-*` via `code-review queue-new`.
