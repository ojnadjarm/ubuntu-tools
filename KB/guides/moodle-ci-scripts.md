# Run a Moodle plugin's PHPUnit / Behat and check only the phpcs violations a change adds

Ticket: T389, T420 (behat --parallel) · Last verified: 2026-10-20 by T846 audit (`mtest --help`, `phpcs-delta --help`, paths, selenium 3.141.59 status); 2026-10-19 by fixture local_t420par (6 features) on 5.2, `tests/mtest-parallel.test.sh` 10/10, `tests/phpcs-delta.test.sh` 4/4

## When to use
Any Moodle plugin work in a docker env (`~/moodle-envs/<ver>`, vass on 4.5): running tests after a change, or checking
"no new phpcs errors" on scope-only diffs. Not for the full Bitbucket mirror: that is `/moodle-ci full`.

## The path we took
- Existed: Moodle's own `util.php --diag` / `init.php` (phpunit + behat), `moodle-plugin-ci codechecker`, phpcs `--report=json`
  and `--stdin-path`, the harness `moodle-container.sh`. Nothing combined them; agents wrote 312 `cd ~/moodle-envs/4.5 &&
  docker compose exec` lines and 34 hand-made `git show HEAD:` + phpcs comparisons in 12 days.
- Chosen: two thin scripts in the `/moodle-ci` skill (`scripts/mtest`, `scripts/phpcs-delta`) on top of those tools.

## Exact commands
```bash
S=~/.claude/skills/moodle-ci/scripts
$S/mtest phpunit <plugin-dir|tests/x_test.php> [--filter test_name]   # init only when stale
$S/mtest behat <plugin-dir|x.feature> [--tags @x]
$S/mtest behat <plugin-dir> --parallel 6                                # N run sites, features round-robin
~/.claude/skills/moodle-ci/tests/mtest-parallel.test.sh               # selftest, stubbed docker/curl
$S/phpcs-delta [--base develop] [plugin-dir]                           # exit 1 on new errors
~/.claude/skills/moodle-ci/tests/phpcs-delta.test.sh                   # selftest, throwaway repo
```

## Pitfalls (measured)
- `vendor/bin/phpunit path/x_test.php` without `--testsuite` fails with `Class "..._testcase" not found` when the
  test relies on a base class another test file `require_once`s: 5 of 18 single-file runs in 12 days. mtest always
  uses `--testsuite <component>_testsuite --filter <class>`.
- A branch switch changes plugin versions, so the phpunit env goes stale ("initialised for different version"): 8
  failed runs in 12 days. A reinit is a full reinstall: 200–230 s on 4.5 (vass), 114 s on 5.2.
- `init.php` also runs composer self-update/upgrade; mtest passes `--disable-composer`.
- Behat `--diag` does not check "enabled"; mtest also requires `behat.yml` + `test_environment_enabled.txt`.
- phpcs-delta matches by sniff + message + line text: a moved pre-existing violation is not new; a violation on an
  edited line counts as new (that is the scope-only rule).

- Behat `--parallel N`: N = min(N, MTEST_SELENIUM_CAP (8) minus busy hub sessions, feature count). Shared selenium is
  3.141.59 standalone with no session limit: 16 concurrent sessions all started; throughput 2.3 nav/s at 1, 6.7 at 8,
  9 at 16 (per-session latency 2.8x at 8), so the default cap is 8.
- Moodle splits features over runs in contiguous chunks: one plugin's 6 features all landed in behatrun3. mtest writes
  `behatrunI/behat/mtest.yml` (suite paths cut to its share) and runs `behat -c mtest.yml --config behat.yml`: Behat
  loads the first flag, Moodle picks the run (DB prefix `bht_I_`) from `--config`. A different config file name alone
  makes every run hit the single site `bht_` (duplicate-key failures). A path argument is filtered out by suite paths.
- Run sites need `public/behatrunI -> .` symlinks (5.1+; dirroot on 4.x); mtest creates them.
- Concurrent headful Chromes on one Xvfb throttle each other: 3 of 6 scenarios timed out ("JS not ready after 10 s")
  until mtest.yml added `disable-backgrounding-occluded-windows`, `disable-renderer-backgrounding`,
  `disable-background-timer-throttling`.
- `init.php --parallel` over existing run sites drops them and then fails (`bht_1_course does not exist`); mtest runs
  `util.php --drop` first. 6 concurrent installs exhaust postgres `max_locks_per_transaction` (64): mtest passes
  `--maxruns=3` (MTEST_INIT_JOBS). Init: 108 s for 3 sites, ~290-500 s for 6 under load.
- A parallel install leaves no single site (`util.php --diag`: "This is not a behat test site!"), so once the env has
  run sites every mtest behat run uses them (plain runs use run 1); readiness is `util_single_run.php --diag --run=I`.
- Timing on 5.2, 6 one-scenario features (warm, see T420 timings.txt): single 73-212 s, --parallel 3 43-144 s,
  --parallel 6 87-108 s; same 6/6 passes. Machine load (other agents) dominates the spread; compare runs back to back.

## Links
- Code: `~/.claude/skills/moodle-ci/scripts/{mtest,phpcs-delta}` (repo copy `~/moodle-harness/skills/moodle-ci/` via `sync.sh`)
- Tests: `~/.claude/skills/moodle-ci/tests/{phpcs-delta,mtest-parallel}.test.sh`
- Measurement: `~/agent-work/research/2026-10-18/night/T389/REPORT.md`, `~/agent-work/research/2026-10-19/T420/` (selenium-capacity, timings)
