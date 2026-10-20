# Daily ailearning full suite on a timer

Ticket: T140, T340 · Last verified: 2026-10-20 by `--help`, unit files, `systemctl --user list-timers`, `ailearning-ci.jsonl` (T846); earlier: 2026-09-29 by a hand run (`systemctl --user start ailearning-ci-daily.service`): rc 0, 423 s; dumps 2026-10-11 (T314); changed-only declutter 2026-10-12 by `bin/tests/ailearning-ci-daily.test.sh` (T340); oldest-marker-first order 2026-10-17 (F46); auto-fix first 2026-10-18 by `bin/tests/ci-autofix.test.sh` (T402); load guard 2026-10-19 by `ci-autofix.test.sh`, `ailearning-ci-daily.test.sh`, `ci-window.test.sh` (T407); shared wait budget 2026-10-19 by the same three suites (T408)

## When to use
Reading, changing or re-running the once-a-day `npm run ci` of ailearning. Agents run `npm run test:changed`, never the full suite.

## The path we took
Copied from `pcbench-weekly` (bash `.service` + `.timer`, log in `~/agents/log/`). `bin/ailearning-ci-daily` copies the repo with `rsync -a`, minus `content/.render` and `out/`
(the build and e2e write `dist/` and `out/`; `git worktree` would be a git write) to `/var/tmp/ailearning-ci.*`, adds `--mute-audio` to
the copy's `tests/lib/browser.mjs`, loads node from nvm, runs `npm run ci:core` (= `npm run ci` minus declutter), then
`npm run declutter -- <slug> --size 1366x768` for each `CHECKED` unit whose files changed since its last green declutter run, appends one
row to `ailearning-ci.jsonl` (`mode` nightly or full), pushes once on a failure (EXIT trap, also on a timeout TERM) and deletes the copy.
A `flock` on `~/agents/state/ailearning-ci.lock` makes a second run exit 75 at once; an unknown option exits 2. A run outside the
`ailearning-ci-{daily,weekly}.service` cgroup (by hand, from an agent) logs to `ailearning-ci-manual.log` and never pushes when killed (rc 143).

**Changed-only declutter (T340):** a full declutter (U01–U07 at 1366) takes ~8150 s, so the nightly checks only changed units. Marker
per unit: `~/agents/state/ailearning-declutter/<slug>` = sha256 over `git ls-files -co` of `units/<slug>/`, `u/<slug>/`,
`public/bundles/<slug>/` plus the shared files (`src/kit src/core src/site/sheet tools/declutter.mjs tools/declutter vite.config.ts
package-lock.json`; any shared change = every unit), written only when that unit's declutter exits 0. Once a run is past 1500 s and one
unit has run, the rest are deferred (logged, not a failure) so the nightly fits `TimeoutStartSec=3600`; units run oldest marker first
(no marker first), so a deferred unit goes first the next night (before 2026-10-17 the fixed `CHECKED` order deferred 06/07 every night). Weekly:
`ailearning-ci-weekly.timer` (Sun 05:30, after pcbench 02:00, maintenance 04:00, moodle-keep-weekly 05:00) runs `ailearning-ci-daily
--full`: declutter of every `CHECKED` unit, no `ci:core`, `TimeoutStartSec=14400`, log `ailearning-ci-full.log`.

**Auto-fix first (T402, FRICTION #9: 8 of 12 high pushes in 14 d were this CI).** The daily unit runs `ci-autofix --repo <repo> --log
<log> "ailearning nightly" -- ailearning-ci-daily`. The wrapper exports `CI_AUTOFIX=1`, so the runner never pushes (except rc 143, a
timeout) and ends its log with `✖ ci failed at <step> (rc N): <last>`. On red (rc not 0/2/75/143) the wrapper appends to
`~/agents/state/ci-fix/<date>.md` the cluster line (`auditlib.error_cluster` + the log's last failure line) and a 40-line log tail,
renders `~/agents/ci-fix/BRIEF.template.md` (`@LABEL@ @REPO@ @NOTE@ @LOG@ @CAUSE@`) into `BRIEF.md`, runs `agent-run ci-fix` once
(TIMEOUT 2400, no timer; works only in the repo, never commits or pushes, verifies only the failing test), re-runs the CI, and pushes
`notify-owner -p high -k "<label> ci: <cause minus digits>"` only if still red; green after the fix runs `pc need resolve "<label> ci
failed" --apply`. One attempt per cause per 24 h (`~/agents/state/ci-fix/attempts.tsv`, epoch + cause key); a repeat pushes at once.
Architecture: the runner owns the suite, the wrapper owns the red policy (single responsibility; any CI command wraps unchanged,
open/closed); agent, push and need verbs are reached only as `$HOME/agents/bin/<verb>`, so the test swaps them by a fake HOME.
`TimeoutStartSec=10800` (run 3600 + fixer 2400 + re-run 3600).

**Load guard (T407; 2026-10-19 red: home-perf LCP and sheet-change frames at load ~14 from T405's visualcheck).** Before `ci:core` the
runner runs `ci-window --quiet`: `wait-for` until the 1-min load < 4, cap 1800 s, then goes on either way; the line `ci-window: 1-min load
X …` is in the log. A red `ci:core` whose e2e failures are all `PERF_JOBS` (home-perf, sheet-change, sheet-cold, the `ALONE` jobs of
`tests/run-e2e.mjs`) at a 1-min load > 6 (before or after) logs `ci-load: contention (…)`. ci-autofix treats that line, or a fixer
`REPORT.md` written in this attempt that starts `Cause: … contention`, as contention: it waits `ci-window --quiet` before its one re-run
(also when the cause already had its 24 h attempt, instead of pushing at once); green resolves the need, still red pushes. Thresholds are
never loosened. **One budget (T408):** worst case was 3 load waits × 1800 s + 2 runs + the fixer > the unit's 10800 s timeout.
`ci-autofix` exports `CI_DEADLINE` (start + 10500 s) and `CI_RUN_NEED` (2700 s, above the 2245 s slowest nightly); every
`ci-window --quiet` caps itself at `CI_DEADLINE - now - CI_RUN_NEED` (`… (cap N s, shared budget: M s to the deadline)` or
`ci-window: no wait budget left …`), and the re-run is skipped with `budget: N s left before the unit timeout, a re-run needs
2700 s; skipped` in the note plus one push. Fleet rule: agents start no heavy run 00:50–01:50 (`ci-window && <cmd>`, `runaway-guard.md`). The declutter `START_BY`
clock starts after the guard, so a long wait does not defer every unit. The rendered fixer `BRIEF.md` writes `$HOME` as `~`
(no-machine-values).

## Exact commands
```bash
systemctl --user start ailearning-ci-daily.service     # run it now (~8 min + declutter of changed units; run budget 3600 s, unit TimeoutStartSec=10800, source ~/agents/units)
systemctl --user start ailearning-ci-weekly.service    # full declutter U01–U07 at 1366 (~2.3 h; log ~/agents/log/ailearning-ci-full.log)
ailearning-ci-daily --mark 02-layers                    # after `npm run declutter -- 02 --size 1366x768` passed by hand: the nightly skips it
ls ~/agents/state/ailearning-declutter/                 # one marker per unit green at its current files
tail -1 ~/agents/log/ailearning-ci.jsonl                # last result
cat ~/agents/state/ci-fix/$(date +%F).md                 # today's red runs, fix attempt and re-run result
cat ~/agents/ci-fix/REPORT.md                            # what the last fixer did
bash ~/agents/bin/tests/ci-autofix.test.sh              # stub agent-run/notify-owner/pc, fixture CI
less ~/agents/log/ailearning-ci.log                     # last timer output (hand runs: ailearning-ci-manual.log)
ls ~/agents/log/ailearning-ci-dumps/                    # failure dumps (only written on a failure)
```

## Pitfalls (measured)
- 2026-10-19 (T407): load ~14 from a night research job doubled sheet-change first paint (504 vs ~130 ms) and failed two perf jobs; the fixer found no code bug and the 01:21 re-run, still under load, pushed high. Now: wait for load < 4, contention re-runs when quiet.
- 2026-10-18 (T402): `agent-run` pushes high when an agent exits non-zero, so a failed fixer pushed twice (agent + still red); ci-autofix now calls it with `AGENT_RUN_NO_PUSH=1` (tests: `ci-autofix.test.sh`, `agent-run.test.sh`).
- 2026-10-15 (F02): a hand run with an unknown flag fell through to a real run, truncated the green nightly log and, killed, sent a false high push; fixed by the lock, the manual log and the cgroup check (test: `bin/tests/ailearning-ci-daily.test.sh`).
- node is not on PATH in `bash -lc`: nvm loads only in interactive shells, so the runner sources `~/.nvm/nvm.sh`.
- The suite's browser is headless but had no `--mute-audio`; the runner patches only the throwaway copy.
- The e2e summary line is ~300 chars and lists failed ids last; the push and jsonl `last` keep only `e2e: N jobs in S s, K failed: ids` (cut at 90), so failed jobs stay visible (test: `bin/tests/ailearning-ci-daily.test.sh`).
- `hygiene` runs `git ls-files`, so the copy keeps `.git` (12 MB); total copy 326 MB (2026-10-10).
- `content/.render` (1.5 GB raw narration WAVs) and `out/` (1.3 GB) are gitignored and unread by `npm run ci`; the e2e scripts `mkdir out/shots` themselves, so rsync excludes both (`cp -a` wrote 3.1 GB a night).

- Failure dumps (T314): the runner exports `E2E_DUMP_DIR=~/agents/log/ailearning-ci-dumps/<date-HHMM>` (override root with `AILEARNING_CI_DUMPS`), so dumps outlive the deleted copy. `tests/lib/dump.mjs` writes `<stamp>-<tag>.{png,json}` only when `lesson.mjs` fails a watch-stop cta click (`stop-N`) or the practice give-up check (`giveup-<id>`); a passing run writes nothing and costs nothing (full ci 425 s, 2026-10-11). Open lead for the 2/6 flake: the last stop's "Your turn" cta races the watch's own advance to the chooser (`advance: true` hides the cta about 1.6 s of watch time after the test lands); not reproduced under 20x CPU throttle.

## Links
- Code: `~/agents/bin/ci-autofix`, `~/agents/ci-fix/` (fixer brief template), `~/agents/bin/ailearning-ci-daily`, `~/agents/units/ailearning-ci-{daily,weekly}.{service,timer}` (installed to `~/.config/systemd/user/`)
- Roster: `~/agents/KB/orchestrator.md`
