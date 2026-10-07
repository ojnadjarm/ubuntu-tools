# Daily metrics of the self-improvement loop: improve-meter

Ticket: T48-L1 · Last verified: 2026-09-26 by `bin/tests/improve-meter.test.sh` (25/25 ok)

## When to use
You need the loop's daily numbers (orchestrator context per turn, headless cache_creation per run, `pc doctor` wall,
pcbench pass rate, corpus WER, idle watts) or a before/after row for an improve ticket's keep-or-roll-back check.
Not for per-turn voice latency (use `eye-latency`).

## The path we took
`bin/improve-meter` is a read-only Python script: it prints a header and one TSV row over the last 24 h.
`--append` writes that row to `~/agents/improve/metrics.tsv`, replacing a row of the same date.
Nothing runs it on a schedule: the 06:45 `improve-meter.timer` (T48 plan, L3) is a new unit and waits for the owner's go.

## Exact commands
```bash
improve-meter                     # print header + today's row
improve-meter --idle off          # skip the 60 s `pc idle` sample
improve-meter --append            # store the row in improve/metrics.tsv
bash ~/agents/bin/tests/improve-meter.test.sh
```

## Pitfalls (measured)
- With no runner, `improve/metrics.tsv` holds one row (2026-09-22); a keep-or-roll-back needs 2 daily rows, so append by hand.
- `idle_psys_w` is `-` unless `pcbench away` says the owner is away; a forced sample while he is present is not comparable (7.13 W vs 4.16 W baseline).
- `pcbench_pass` reads `bench/LAST.json` as it stands; the meter has no staleness column.
- `doctor_s` runs in parallel with the parsing: about 0.4 s of noise (3.7–4.3 s vs 3.9 s alone).

## Links
- Code: `~/agents/bin/improve-meter` (paths overridable with `IMPROVE_*`, see the test)
- Tests: `~/agents/bin/tests/improve-meter.test.sh`
- Design / results: `~/agents/research/2026-09-22/T48-self-improvement-plan.md`, `~/agents/research/2026-09-22/T48-L1-result.md`
