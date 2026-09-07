# Toolsmith backlog

Ranking: score = evidence weight × expected gain ÷ sessions. Evidence weight is 1 (one citation)
to 3 (multiple independent citations, e.g. a benchmark run plus a code location). Expected gain
is a 1-3 estimate of the Success check's before-to-target improvement. Higher score ranks first.
Cap 10 rows with status `proposed` or `go` at once — anything beyond the cap waits. Any row stuck
at `proposed` for 4 weeks with no `go` moves to `dropped` with a one-line reason appended below
its row.

Updated 2026-09-07 (run 1). Say `go TSP-nnn`, or `go all auto-ok` (skips owner-go rows).

| rank | id | title | class | status | metric before → target | sessions | score |
|---|---|---|---|---|---|---|---|
| 1 | TSP-003 | O02 `sink` schema description | auto-ok | measuring | O02 pass new 0/3 → ≥2/3 | 1 | 9 |
| 2 | TSP-001 | `sudo` guard closes the secure_path hole | owner-go §5 | measuring | sudo guard cases 0 → ≥6; guard_hits S02/S04 ≥1 | 1 | 6 |
| 3 | TSP-002 | `--apply` invalidates changed cache keys | auto-ok | proposed | C02 pass new 1/3 → 3/3 | 1 | 6 |
| 4 | TSP-005 | tokens + tool histogram per run in `index.tsv` | auto-ok | proposed | token columns absent → present every run | 1 | 4 |
| 5 | TSP-006 | audit hook matcher `*` (web, read, grep) | owner-go | done | tool names in audit 5 → ≥10 | 1 | 4 |
| 6 | TSP-007 | `pc idle` + `BASELINE-IDLE.tsv` weekly | auto-ok | proposed | idle rows 0 → 1/week | 1 | 4 |
| 7 | TSP-009 | `agents-stop` reads `state/pid`; agent-* name check | auto-ok | proposed | fixture kills 0/1 → 1/1 | 1 | 4 |
| 8 | TSP-004 | `agents-log --raw` raw→pc mapping | auto-ok | proposed | raw-coverable count unknown → weekly number | 1 | 2 |
| 9 | TSP-008 | `pc status --brief` FAIL list from `$REC`; drop `ok_if` | auto-ok | proposed | brief FAIL tags 7 → all | 1 | 2 |
| 10 | TSP-010 | `moodle-keep` honours `MOODLE_ENVS_DIR` | auto-ok | proposed | envs found under custom dir 0 → 1 | 1 | 1 |
| - | TSP-000 | example (reference only) | auto-ok | proposed | pc status wall time (ms) 420 → 120 | 1 | - |

Waiting below the cap (no file yet): seed 11 `timeout` wrapper — measured 100 ms per call, but
only `pc-doctor` (9 calls) and cold SMART use it; opens when a slot frees.
