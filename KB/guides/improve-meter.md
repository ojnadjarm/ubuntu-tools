# Daily metrics of the self-improvement loop: improve-meter

Ticket: T48-L1 · Last verified: 2026-10-20 (timer enabled, next 06:45; metrics.tsv rows 2026-09-22 and 10-13..10-20); test 2026-09-26 `bin/tests/improve-meter.test.sh` (25/25 ok)

## When to use
You need the loop's daily numbers (orchestrator context per turn, headless cache_creation per run, `pc doctor` wall,
pcbench pass rate, corpus WER, idle watts) or a before/after row for an improve ticket's keep-or-roll-back check.
Not for per-turn voice latency (use `eye-latency`).

## The path we took
`bin/improve-meter` is a read-only Python script: it prints a header and one TSV row over the last 24 h.
`--append` writes that row to `~/agents/improve/metrics.tsv`, replacing a row of the same date.
`improve-meter.timer` runs `improve-meter.service` (`improve-meter --append`) daily at 06:45 (`Persistent=true`), enabled since 2026-10-13 (CR-004); units in `~/.config/systemd/user/`.

## Exact commands
```bash
improve-meter                     # print header + today's row
improve-meter --idle off          # skip the 60 s `pc idle` sample
improve-meter --append            # store the row in improve/metrics.tsv
bash ~/agents/bin/tests/improve-meter.test.sh
```

## Pitfalls (measured)
- The timer appends one row a day (2026-09-22, then daily from 2026-10-13); a keep-or-roll-back needs 2 daily rows, so wait a day or append by hand.
- `idle_psys_w` is `-` unless `pcbench away` says the owner is away; a forced sample while he is present is not comparable (7.13 W vs 4.16 W baseline).
- `pcbench_pass` reads `bench/LAST.json` as it stands; the meter has no staleness column.
- `headless_cc_k` skips meta.json rows whose token counters are all 0 (e.g. a Workflow run, `code-review/logs/2026-10-15-134226-kjpl` at $30.75), as `agent-run` does; counting it halved the 10-16 value (11.2k vs 22.5k).
- `doctor_s` runs in parallel with the parsing: about 0.4 s of noise (3.7–4.3 s vs 3.9 s alone).

## Links
- Code: `~/agents/bin/improve-meter` (paths overridable with `IMPROVE_*`, see the test)
- Units: `~/.config/systemd/user/improve-meter.timer`, `improve-meter.service`
- Tests: `~/agents/bin/tests/improve-meter.test.sh`
- Design / results: `~/agent-work/research/2026-09-22/T48-self-improvement-plan.md`, `~/agent-work/research/2026-09-22/T48-L1-result.md`
