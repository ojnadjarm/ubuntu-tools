# Planner seeds: which FOLLOWUPS.md lines are shipped, due or still open

Ticket: T953, T996 · Last verified: 2026-10-20 (T996) by bin/tests/followups.test.sh (50 ok) and `followups --run --line N` on each of the 17 T566 check lines (against the 10-20 nightly: 12 fail, 5 error `not yet`, 0 syntax errors)

## When to use
A planner reads `research/2026-10-19/T566/FOLLOWUPS.md` (the orchestrator's seed list) and wants to skip lines already shipped or not due yet. Not for backlog items: `fleet-survey --shipped`.

## The path we took
- Existed: `fleet-survey --shipped` (backlog items vs history.md), `ticket-id`; nothing read FOLLOWUPS.md. Chosen: one read-only Python CLI; fleet-survey calls it (`### followups` section) instead of carrying a copy.
- Per `- ` line: T-id (first T<n>), date (first YYYY-MM-DD), kind (`guide line` / `nightly wait` / `seed`), status: `struck` > `shipped?` > `due` > `open`.
- `shipped?` = a history.md line after the seed's origin (its T-id's first history line, else its date) led by the same T-id, or by a later non-planner ticket naming it, sharing a code word (path, flag, CLI or env name) with the seed's open text.
- `due` = a named date (`10-21`, `21 Oct`) later than the origin and not after today, or a `next|first … nightly` wait with a `log/fleet-ci/<date>.txt` dated after the origin.
- T996: a line may end with `` check: `<bash>` `` (read existing logs only; rc 0 pass, 1 fail, other = error). The check is cut off before classifying, so its dates and code words never make a line due or `shipped?`. `--run` runs the due ones under `nice -n 19 timeout 30` (FOLLOWUPS_TIMEOUT); `--apply` strikes passes `(passed <date> by followups --run)`.
- Check helpers (prepended by `--run`): `cpu RE` / `wall RE` sum cpu_s / wall of `$NIGHTLY_ROWS` (the newest fleet-ci log's main pass: the first test-timings-history row per `ok|FAIL <file>` at or after its `fleet-ci-daily <ts>` header; `SKIP unchanged` files have none); `le V MAX`, `ge V MIN` print the comparison and exit 2 on a non-number (no row, jq `null`); `newer FILE YYYY-MM-DD`, `after YYYY-MM-DDTHH:MM` exit 2 `not yet`. `$NIGHTLY` is the log path.

## Exact commands
```bash
followups --open                 # one row per unstruck line, last line `N open, M due, K shipped?`
followups --json | jq '.lines[] | select(.status == "shipped?")'
followups path/to/OTHER.md
followups --checks               # L<n> T<id> <status> <check> per unstruck line with a check
followups --run                  # morning: judge every due check, one `L<n> T<id> pass|fail|error <s> <last line>` row
followups --run --line 48        # one line, due or not (try a new check against the last nightly)
followups --run --apply          # strike the passing lines in place
```
Write a check as `le $(cpu '/cpp-hot\.') 250`, `ge $(grep -c '^SKIP unchanged' "$NIGHTLY") 15`, `newer <file> 2026-10-20 && le $(jq .x <file>) N`; no backticks inside.
Strike a verified line as `- ~~<text>~~ (shipped T<n>, checked T<you>)`; strike only the shipped sentence when the rest is still open.

## Pitfalls (measured)
- Ticket mentions alone are noise: without the code-word rule 28 of 64 unstruck lines were `shipped?` (planner and pitfall lines name many tickets); with it 9, then 7 after T953 struck 11 lines.
- Dates that name a past event (`live plan 10-20 11:00`) or a range (`6-10 dB`) are not due dates: only dates after the origin count, `M-D` needs two digits.
- `shipped?` is a hint: read the named history line before striking (T720 stays `shipped? by T780` for its struck doc sentence while its nightly part is still open).
- Two full suites can run the same night (10-20: rows at 02:1x from another run, the nightly header at 02:22:11): history rows before the log's header are not the nightly's, so `cpu` starts at the header and takes the first row per file.
- A test skipped as unchanged has no row: `le $(cpu X) N` is then an `error` (no number), not a pass at 0 CPU s.
- Lines with no nightly/date words (`next film build`) are never due: add the date (`due 10-21`) or `--run` skips them (T785, T740).
New CLI in ~/agents/bin: run `~/agents/install.sh --links` or live sessions get "command not found".

## Links
- Code: ~/agents/bin/followups; section in ~/agents/bin/fleet-survey
- Tests: `bash ~/agents/bin/tests/followups.test.sh` (check fixture: pass, fail, timeout, no-row error, not due, --apply)
