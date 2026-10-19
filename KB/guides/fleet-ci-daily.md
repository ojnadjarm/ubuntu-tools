# Nightly fleet CI: the ~/agents test suite on a timer

Ticket: T459 · Last verified: 2026-10-19 by `bin/tests/fleet-ci-daily.test.sh` (31 checks) and one run of `fleet-ci-daily` under the user manager

## When to use
Reading, changing or re-running the once-a-day run of `bin/tests/run.sh -j 8` over the fleet's own tooling. A ticket still runs its own changed tests; this catches what nobody's ticket ran.

## The path we took
Copied from `ailearning-ci-daily` (T140/T402/T407): the runner owns the suite, `ci-autofix` owns the red policy unchanged.
- `bin/fleet-ci-daily`: `flock` (`state/fleet-ci.lock`, second run exits 75), `ci-window --quiet` (wait for 1-min load < 4), `run.sh -j 8`, output to `~/agents/log/fleet-ci/<date>.txt` (one file a day, the re-run overwrites it; the red tail is kept in the ci-fix note). Red ends with `ci-load: contention (…)` when the load before or after was > 6, then `✖ fleet ci red: <failing files>` (the cause line ci-autofix keys on, so each set of failing files is its own cause).
- `units/fleet-ci-daily.{service,timer}`: daily 02:10 (after the 00:50–01:50 window), `ci-autofix --repo ~/agents … "fleet nightly" -- fleet-ci-daily`; `TimeoutStartSec=7200`, `CI_BUDGET=6900`, `CI_RUN_NEED=900` (run ~155 s).
- Red: one `ci-fix` attempt per cause per 24 h, one re-run (after a quiet wait on contention), `notify-owner -p high` only if still red; green after a fix resolves the `fleet nightly ci failed` need.
- `pc doctor` row `fleet-ci`: the newest log's `PASS|FAIL n/m files` line; red, no summary, none, or older than 48 h is a WARN (never a FAIL: a red suite is not a broken machine).
- Kill switch: `agents-stop` stops the service and the timer.

## Exact commands
```bash
systemctl --user start fleet-ci-daily.service          # run it now through ci-autofix (a red run starts a real ci-fix agent)
fleet-ci-daily                                          # suite only, no fixer, no push
tail -3 ~/agents/log/fleet-ci/$(date +%F).txt           # today's result
pc doctor --brief | grep fleet-ci                       # the doctor row
cat ~/agents/state/ci-fix/$(date +%F).md                # red runs, fix attempt, re-run
bash ~/agents/bin/tests/fleet-ci-daily.test.sh          # fixtures: green, red, contention re-run, lock, units, doctor row
```

## Pitfalls (measured)
- A `$` in a unit's `ExecStart` must be `$$` and `%` must be `%%`: `$$(date +%%F)` reaches bash as `$(date +%F)` (probe unit, 2026-10-19).
- `systemd-run` does not expand `%h` in its command: the hand probe exited 127 in 162 ms; pass `$HOME` from the shell.
- Units are copied, not linked: after editing `~/agents/units/fleet-ci-daily.*`, `cp` them to `~/.config/systemd/user/` and `systemctl --user daemon-reload`.

## Links
- Code: `~/agents/bin/fleet-ci-daily`, `~/agents/bin/ci-autofix`, `~/agents/units/fleet-ci-daily.{service,timer}`, `~/agents/bin/pc-doctor` (`fleet_ci`)
- Tests: `bash ~/agents/bin/tests/fleet-ci-daily.test.sh`
- Related: `KB/guides/ailearning-ci-daily.md` (the same red policy), `KB/guides/runaway-guard.md` (CI window)
