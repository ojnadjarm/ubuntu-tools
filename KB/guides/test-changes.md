# Changing an existing test: a declared, reviewed step (test-changes)

Ticket: T1591 · Last verified: 2026-11-10 by `bin/tests/test-changes.test.sh` (39/39), `agent-verify.test.sh`, `brief-check.test.sh`, moodle-ci `mci.test.sh` + `moodle-stop-reminder.test.sh`, and an mfixture plugin in 5.2 (`mci quick` without a note: testchanges red; `mci full` with `MCI_TEST_NOTE`: 16 ok, 0 red)

## When to use
Any work that touches an existing test file (PHPUnit, Behat, node/vitest, pytest, `*.test.sh`). Owner *intent* (2026-11-10):
agents tend to "fake" tests, so a changed test needs a stated reason and a second reviewer. New test files are free.

## The rule
1. Existing tests are frozen by default. Never weaken, skip or delete an assertion or a test to get green.
2. A task that changes a feature's behaviour may change its tests. List each changed test under a `## Test changes` heading
   (in the report, the brief's `<T>-report.md`, or `$AGENT_WORK/evidence/<T>/test-changes.md`), one line each:
   `- <file> · <test> · <requirement that changed> · <assertion before> → <assertion after>`
3. A second reviewer (the orchestrator, or an agent that did not write the change) approves that list before "done" is relayed.

## The path we took
Before: the freeze lived only in briefs (hand `sha256sum` of `tests/` before/after: T1445, T1451, T1483, T1488); nothing checked it.
Chosen: one CLI on `git diff <base>`; regexes per dialect for assertions, skips and test definitions; no suite run (0.1 s on ~/agents).
Mutation testing (infection, stryker) would catch more but needs the suite and minutes; out of scope.
- `test-changes [--repo DIR] [--base REF | --ticket T<n>] [--scope PATH]... [--committed-only] [--note FILE|DIR]...`
  A test file counts when it exists in the base and its diff removes a line or adds a skip (pure additions are new tests).
  Per file: `removed assertion`, `weakened: strict → loose` (assertEquals/toBe/== → assertNotNull/truthy), `changed assertion`,
  `added skip` (markTestSkipped, `.skip(`, `xit(`, pytest skip/xfail, bare `return`, `exit 0`), `deleted test`, `renamed test`.
  Prints `NEEDS REVIEW: test changes`; exit 0 none or all noted, 1 a file has no note line (needs the file name and `→`/`->`), 2 usage.
- `--ticket T<n>`: base = parent of the oldest `T<n>:` commit; files = those commits plus uncommitted ones (`--scope` limits these).
- `agent-verify <brief>`: runs it with `--ticket` on the cwd's repo and each claimed path's repo (uncommitted files only when
  claimed); notes = the brief, `<briefdir>/<T>-report.md`, `$AGENT_WORK/evidence/<T>/`. Prints the list, stores
  `test_changes {noted, report}` in check.json, exits 1 while a file has no note (the CHECK's own `ok` is unchanged).
- `mci` step `testchanges` (quick, schema, full): `test-changes --repo <plugin>` vs HEAD; notes from `MCI_TEST_NOTE`.
  The Moodle stop hook adds "Existing tests changed (…)" to its reason when a `*_test.php`/`.feature` in the base changed.
- `brief-lint`: rule `test-changes` (the brief, or its `_common` file, must say "test change(s)").

## Exact commands
```bash
test-changes --repo ~/agents --ticket T1591                       # what the reviewer reads
test-changes --repo <plugin-dir> --note ~/agent-work/evidence/T<n>/test-changes.md
MCI_TEST_NOTE=~/agent-work/evidence/T<n>/test-changes.md ~/.claude/skills/moodle-ci/scripts/mci quick <plugin-dir>
agent-verify ~/agent-work/briefs/T<n>-<slug>.md                    # NEEDS REVIEW block + verdict
```
Brief line: `Test changes: existing tests are frozen; a changed test needs a "Test changes" note (guide test-changes), reviewed before done.`

## Pitfalls (measured)
- Pure additions to an existing file first counted as changed: on ~/agents (2026-11-10) agent-verify.test.sh (8 new cases, 0 removed
  lines) showed `NO NOTE`; now a file needs a removed line or an added skip.
- A renamed shell case first read as `deleted test: 'lint flags 4/4 …'`; names removed and added in one hunk now pair as `renamed test`.
- Real hit: `--ticket T1575` flags `removed assertion` in `pcbench-weekly.test.sh` (a calendar check), 0.16 s.
- The shared ~/agents tree is dirty with other agents' tests (T1590 had 2 test files uncommitted at 14:26); agent-verify
  counts uncommitted files only when the ticket claimed them, else only its `T<n>:` commits.
- Shell lines count as assertions only with `ok`/`nok` (or `assert*`); a bare `[ … ]` line before an `&& ok` on the next line
  is not listed, so the file still shows but the line may not: read the diff it names.
- `mci full` on a plugin that is its own fresh git repo: grunt went red (moodle-plugin-ci restores its backup over `.git/objects`,
  which git makes read-only: "Permission denied"); `chmod -R u+w .git` made it green (fixture, 5.2). A fixture without a privacy
  provider is red in privacy, not in testchanges.
- New CLI in ~/agents/bin: `~/agents/install.sh --links` (live sessions get "command not found" otherwise).

## Links
- Code: `~/agents/bin/test-changes`, `~/agents/bin/agent-verify`, `~/agents/bin/brief-lint`, `~/.claude/skills/moodle-ci/scripts/mci`, `~/.claude/hooks/moodle-stop-reminder.sh`
- Tests: `bash ~/agents/bin/tests/run.sh --only 'bin/tests/test-changes.test.sh'` (and agent-verify, brief-check); moodle-ci `tests/mci.test.sh`, `tests/moodle-stop-reminder.test.sh`
- Design: `~/agent-work/research/2026-11-10/T1591/ARCH.md`
