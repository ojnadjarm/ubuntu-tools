# Planner survey: the fleet numbers for a backlog wave in one command

Ticket: T554, T620, T629, T637, T726, T741, T859, T860, T901 · Last verified: 2026-10-20 (T901: --help + code read of `flaky()`, `_input_mtimes()`, `shipped()`); before: 2026-10-20 by T846 read-only audit (`--help`, code, paths), `bin/tests/fleet-survey.test.sh` (87 ok) and live runs (`--creative --shipped` 15/15 sections, 10.9 s at load ~20; `--measure` 17/17, 71-85 s at load 19-23)

## When to use
A planner (wave, backlog, night run) needs today's measurements: failures, error clusters, tokens by ticket, doctor,
fleet-ci reds, untested scripts, stale guides, red check.json, slow tests, flaky tests, perf CV, fresh-suite score, claims.
Run `fleet-survey` once instead of ~40 probes (T550 spent ~60 tool calls on it). Not for diagnosing one item: open
the source command it names.

**Wave planners start from `fleet-survey --creative --shipped`** (T629): the two creative stacks (counts, MV_* knobs,
newest drops, motion build.json cpu_s + steps_cpu, perf-cpp.csv gpu_ms_p50, cpp-ci stages + last ledger row) and per-wave counts
with the open/unticketed items (`--shipped all`: every earlier item with its T-number and state), so no backlog repeats a shipped title. T599/T582/T550 planners spent ~25 of 73–79 turns and
6.1–6.4M cache-read tokens gathering this by hand. **Add `--measure`** (T637, ≤ 90 s) for what T615/T631 still timed
by hand: CI reds re-run alone, hooks p50, CLI p50, /tmp residue, duplicate definitions.

## The path we took
- Existed: `toolsmith-inputs` (JSON for toolsmith, different sections), `pc failures`, `agents-log --errors --cluster`,
  `agents-log --tokens --by ticket` (T552), `pc doctor`, `guide --stale`, `claims list`. Chosen: one read-only Python
  CLI that calls them and reads the files directly; no new collectors.
- Shape: `SECTIONS` = list of (name, function); each function returns rows or raises `NA(why)`. `section()` wraps any
  exception into one `n/a: <why>` row (fail soft). All 13 but doctor run in a thread pool, doctor alone after them (T741); output is `### <name>` + rows
  (measurements.txt shape) or `--json` `{section: {ok, ms, rows}}`.
- SOLID: one function per section (single responsibility); a new section is one function + one `SECTIONS` row
  (open/closed); CLIs only via `run()` from `$HARNESS_HOME/bin` (one seam: tests swap the whole bin with stubs).
- Roots: `HARNESS_HOME` (else `~/agents`), `AGENT_WORK` (else `~/agent-work`); skill scripts from `~/agents/skills`
  and `~/.claude/skills` (symlinks de-duplicated, `synced/`, `tests/`, `node_modules/` skipped).

| section | source |
|---|---|
| failures | `pc failures --since` |
| clusters | `agents-log --errors --cluster --since`, header + top 20 + TOTAL |
| tokens by ticket | `agents-log --tokens --by ticket --since`, top 25 rows |
| doctor | `pc doctor --quick --brief` (non-OK rows) |
| fleet-ci | newest `~/agents/log/fleet-ci/*.txt`: score, ci-load, red line |
| untested | executables in bin/ and skill dirs, plus .py/.sh/.js in lib/, hooks/, adapters/*/hooks/, whose name or stem is no word in any test file |
| stale guides | `guide --stale 14` |
| red check.json | `~/agent-work/evidence/*/check.json` with `ok: false`, mtime inside `--since` (the file is the newest `agent-verify --recheck` verdict); split still-red / `window, heals <time>` / `superseded: fleet-ci`; `[verdict load|drift|real]` (agent-verify --recheck) when present |
| slow tests | top 5 by p50 of each file's last 5 runs in `~/agents/state/test-timings-history.tsv` (run.sh appends `date file seconds rc load1`, 30 days kept), n < 3 tagged noisy, plus `outlier` rows (> 5x p50 and > 30 s) and a top CPU block by p50 cpu_s; `last run` rows from `test-timings.tsv` until the history exists |
| flaky | `state/test-timings-history.tsv` rows in the window (`--since`, else 7d): files whose rc flipped red<->green. A flip is flaky only when every input is older than its first run; an input changed between the two runs = dev, changed later = unsure (only current mtimes are known). Inputs: the test; for `bin/tests/<x>.test.*` `bin/<x>*`, for `<skill>/tests/*` every non-generated file under the skill dir (`GENERATED`: node_modules, __pycache__, dot dirs, out/, output(s)/, cache/, build/, dist/, tmp/, *.pyc, *.log); plus bin files a word in the test or those tools names, one hop (T860). Header `N flaky, D dev flips …, U unsure … in <window>`, rows `<file>  red r / runs n, flips f, last MM-DD HH:MM, load at red a/b` |
| perf cv | `avg_fps` of `~/agents/state/gamedev-perf/perf.csv`: n, mean, sd, cv, min, max |
| fresh suite | first `PASS|FAIL n/m` line of the newest `evidence/*/fresh-suite*.txt` by mtime, file named, with its age |
| claims | `claims list` |
| followups (when `bin/followups` exists) | `followups --open --json`: `N open, M due, K shipped?` then one row per due seed (T953) |
| creative motion-video (`--creative`) | `skills/motion-video`: scripts/ and `tests/*.test.*` counts, MV_* names in every text file of `scripts/` and `templates/` (node_modules skipped; mv-knobs-doc.test.sh's scope, T953), newest `~/agent-work/motion/*/out/build.json`: `cpu_s` + top 3 `steps_cpu`, with its age; newest 3 drops |
| creative gamedev (`--creative`) | `skills/gamedev`: counts, last `state/gamedev-perf/perf-cpp.csv` row (`gpu_ms_p50`, per pass, status, age), `stages="…"` of `scripts/cpp-ci`, newest `cpp-ci` row of `log/creative-ci.jsonl` whose summary project is not scratch (`CI_SCRATCH_ROOTS`, else $TMPDIR and /tmp, or a scratchpad) with its stages and age, newest 3 drops |
| shipped (`--shipped [open\|all]`) | per-wave counts, then open/unticketed items (`all` or `--shipped-all`: every item); `research/*/T*/BACKLOG.md` `## N. title` rows; `## T<n> · title` / `## T<n> title` headings too (T859, k = position); label `wave N <planner>`, `wave <planner>` when the header has no `wave N`, `moodle wave [N] <planner>` when it says `moodle harness wave` (those take no history wave tags); T-number from a brief whose first line is `# T… — …#N (from …/T<planner>/BACKLOG.md)`; else the `## N. T<n> title` heading, else a history `T<n> (wave N #k)`/`(wN #k)` tag; `T716*` = a double use per `ticket-id dups` (T741); shipped when `history.md` has a `- [date] [hh:mm] T…` line (not `brief written`), else open; no id = unticketed |
| ci reds alone (`--measure`) | `FAIL <file> <s>` lines of the newest fleet-ci log, shortest first: one `quiet-gate --wait 10`, then `run.sh --only <file> -j 1` each until 50 s (`rc`, seconds, suite seconds; `timeout`/`skipped: budget`) |
| tmp residue (`--measure`) | `du -sb` of every entry of `$FLEET_SURVEY_TMP` (else /tmp), by kind (`tmp.*`, leading lowercase words, `(other)`), top 10 by MB |
| dup defs (`--measure`) | top-level `def x(` / `x() {` names in >= 3 files of bin/, lib/, hooks/, skill scripts (main/usage/die skipped), file:line |
| hooks p50 (`--measure`, after the rest) | settings.json PreToolUse/PostToolUse/PostToolUseFailure hooks x5 on a fixture event; HARNESS_HOME, HOME, XDG_RUNTIME_DIR = a mktemp dir (header counts the audit rows that landed there) |
| cli p50 (`--measure`, after the rest) | 9 read-only CLIs x3 (`CLIS`), wall ms p50 + the 3 runs + rc; stops at 80 s |

## Exact commands
```bash
fleet-survey                     # text, window 24h
fleet-survey --since 2d          # wider window for failures, clusters, tokens, red check.json
fleet-survey --creative --shipped  # wave planners: + creative stacks + per-wave counts, open/unticketed items
fleet-survey --shipped all       # every earlier wave item with its T-number and state
fleet-survey --measure           # + ci reds alone, tmp residue, dup defs, hooks p50, cli p50 (<= 90 s)
fleet-survey --json | jq '."red check.json".rows'
fleet-survey --since 7d | sed -n '/^### flaky/,/^### perf/p'   # red<->green flips, dev/unsure counts (T860)
fleet-survey --shipped | grep '^moodle wave'                  # Moodle harness waves (T859)
bash ~/agents/bin/tests/fleet-survey.test.sh
```

## Pitfalls (measured)
- Full `pc doctor --brief` took 17.1 s at load 7.9 and 24.4 s at load 14.9 (the 25 s section timeout); the survey's own
  parallel sections push timing rows to WARN. The survey uses `--quick` (11 s at load 15); run `pc doctor --brief`
  by hand for the sub-command sweep.
- Substring matching for "untested" hid scripts (`pc` matches everything); it matches whole words
  (`[\w.+-]+`) plus test-file stems (`x.test.sh`, `test_x.py` → `x`).
- T741: doctor beside the pool read `FAIL usage pc-wait-for min 122` while doctor alone was OK (98 ms): its usage rows time
  CLIs. `ALONE = {'doctor'}` runs it after the parallel sections, so the survey takes pool + doctor seconds.
- T741: a `*` on a `--shipped` id is a real double use (T716/T717 MIRASMANT-26, T718 MIRASMANT-5 vs wave 18): run
  `ticket-id check T718`; grep the id column with `T718\*?`. No `$HARNESS_HOME/bin/ticket-id`: no stars, nothing fails.
- With `n/a` in an empty HOME, `untested` and `red check.json` still report 0 (a count, not a failure): 2/12 ok.
- `pc doctor` exits 1 when a row FAILs; the survey accepts rc 0 and 1 there.
- T620: `test-timings.tsv` keeps only the last run (mv-quality showed its 170 s timeout after a fix to 30 s); slow tests
  read the history p50 instead. `test-timings.tsv` stays as the run.sh pool order.
- T620: a CHECK `journalctl ... --since -N | grep -c PAT` stays red for N after a fix. The survey re-runs that query as
  `journalctl ... -o short-iso | grep PAT | tail -n 1` (PATH = `$HARNESS_HOME/bin` first, the test's stub seam); a last
  failure older than the fix (first agent-verify run, `runs[0].started`) tags `window, heals <last + N>`; none left:
  `window, heals now`. Count thresholds (`-le 50`, T473) stay still-red while the count is high.
- T629: a drop belongs to a stack when its `briefs/<T>-*.md` text above `## Common rules` names that stack more often
  than the other (the common rules mention motion-video, so they are cut; ties and non-T drops are skipped). Drops whose
  brief is missing never show.
- T629: wave 1 (T411) has no `wave N` in its header: printed as `wave ?`. Unticketed items in wave 2 are real (6 never
  got a brief), not a parse miss; history lines with a time (`- 2026-10-19 08:25 T429`) count as shipped.
- T637: a timed-out re-run gets SIGTERM to its process group first (run.sh's EXIT trap removes its TMPDIR), SIGKILL
  after 3 s; `subprocess.run(timeout=)` alone leaves the test running and holding the pipe.
- T637: hooks and CLIs are timed serially after the parallel sections (else they time each other); at load 19-23
  pcbench (30-50 s) does not fit the 50 s CI budget and shows `rc timeout`.
- T893 (2026-10-20, `--since 24h`): `3 flaky, 8 dev flips, 20 unsure`: unsure dominates because only current mtimes are known (an edit after the flip hides whether one came between); read unsure as unknown, not flaky.
- T860 verifier: a skill test takes every non-generated file of its skill dir as input, so an unrelated edit in the skill turns a real flake into dev; mv-finish still listed flaky with 5 flips. The fleet-survey.test.sh wall asserts (`--creative --shipped` ≤ 5 s, `--measure` ≤ 15 s) went red once at load ~29 and were green in 10 later runs.
- New CLI in ~/agents/bin: `~/agents/install.sh --links` (done 2026-10-19), else "command not found".

## Links
- Code: ~/agents/bin/fleet-survey; ids: ~/agents/bin/ticket-id (guide `ticket-id`)
- Tests: ~/agents/bin/tests/fleet-survey.test.sh (fixture HOME, stub CLIs; never calls the real ones)
- Design / results: ~/agent-work/research/2026-10-19/T550/BACKLOG.md §4, measurements.txt
