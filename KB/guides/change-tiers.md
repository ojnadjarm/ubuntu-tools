# Test at the change's tier: change-class, mci auto, the nightly safety net

Ticket: T1399 (proposal T1398) · Last verified: 2026-10-26 by `bin/tests/change-class.test.sh`, `tier-nightly.test.sh`, `brief-check.test.sh`, `agent-verify.test.sh`, moodle-ci `mci.test.sh` + `moodle-stop-reminder.test.sh`, and `mci auto` on an mfixture plugin in 5.2

## When to use
Choosing which tests a change needs before calling it done (Moodle plugin, Mooblox, fleet tooling). Owner 2026-10-26: a button label
does not rerun everything; the full pipeline runs nightly and before a release; agents keep the time the work needs.
Not for releases: `mci full`, `npm run test:all`, a full `run.sh` stay the release gate.

## The path we took
Survey (T1398): Bazel/Nx affected, Vitest `related`/`--changed`, pytest-testmon; Google TAP adds a scheduled full run as the net.
Chosen: a deterministic path classifier plus a nightly full run; no model, reuses `mtest --changed`, `vitest related`, `run.sh --only`.
- `change-class [--base REF] [--repo DIR] [--at-least CLASS]`: DIR's diff vs REF (default HEAD, an unborn HEAD = the empty tree) plus
  untracked files → `class:`, `checks:`, `decided by:`, `files:`. Classes low→high: none docs ui content logic schema engine security full;
  the highest file wins; a file no rule matches is `full`. Rules: DIR's `.change-classes`, else the built-in Moodle default when DIR is a
  plugin, else a parent's `.change-classes` up to the repo top, else docs-only. Rule lines `<glob> <class>` (first match wins, `*` crosses
  `/`, a glob without `/` also matches the basename), `diff:<regex> <class>` (added/removed lines), `checks <class> <text>`.
- Rule files: `~/agents/.change-classes` (fleet), `~/projects/personal/mooblox/.change-classes` (engine paths from T1398 §3).
- `mci` (moodle-ci): `auto` is the default in git. docs/content → codechecker, phpcs-delta, lang; ui → + mustache; logic → quick with
  `mtest phpunit --changed`; schema → quick with the whole suite + savepoints + privacy; engine/security/full/no change-class → full.
  `quick` passes `--changed` on a dirty plugin tree. Each mci log gets `<log>.plugin` (the plugin dir).
- Stop hook `moodle-stop-reminder.sh`: PHP under `lang/` or `templates/` never demands a run; the reason asks for `mci auto`.
- `agent-verify` records `class` (change-class on the cwd, raised by the brief's `Class:`) and `class_declared` in check.json.
  `brief-lint` WARNs when a CHECK runs `test:perf`, `test:all` or `run.sh` without `--only` and the brief has no `Class: engine|full`.
- Safety net: `fleet-ci-daily` (02:10, the fleet suite) and `tier-nightly` (03:30 user timer, `ci-window --quiet` first): Mooblox HEAD as a
  `git archive` in a temp dir, `npm ci`, `npm test`, the perf gate under `flock /tmp/mooblox-perf.lock timeout 1500` (T1407: 1000 s measured); then `mci full` on
  every plugin with an mci log since the last pass (never under `~/moodle-envs/vass` or `~/moodle-envs/4.5`). A red row exits 1: the
  failed unit shows in `pc status` FAIL and the 08:00 digest; no push of its own.

## Exact commands
```bash
change-class --repo ~/projects/personal/mooblox             # class + checks for the working tree vs HEAD
change-class --repo <plugin-dir> --base HEAD~1              # a committed change
~/.claude/skills/moodle-ci/scripts/mci <plugin-dir>          # auto in git; first line: "mci: auto: class docs -> codechecker phpcs-delta lang"
cd ~/projects/personal/mooblox/client && npx vitest related <files> --run && npm run test:changed
bash ~/agents/bin/tests/run.sh --only 'bin/tests/<changed>.test.sh'
tier-nightly --help; systemctl --user start tier-nightly.service; tail -8 ~/agents/log/tier-nightly/$(date +%F).txt
```

## Pitfalls (measured)
- Before/after on 3 sample diffs (2026-10-26): Moodle lang string `mci quick` 100.7 s (PHPUnit 100 s, incl. a stale init) vs `mci auto` 0.6 s (class docs: codechecker, phpcs-delta, lang; mfixture, 5.2); a PHP logic change under `mci auto` ran `mtest --changed` (calc_test, 1 test) in 2.9 s;
  Mooblox prop tweak: before = full vitest 35.8 s + perf gate 756 s (T1398), after = tsc 1.3 s + `vitest related` 2.0 s (3 of 110 files)
  + `npm test` once 35.8 s; fleet bin script: before = full `run.sh` 493 s (nightly 10-26), after = `run.sh --only` one file 2.3 s.
- `vitest related` and the tsc check fail in a copy without `moodle/local/mooblox` (the client imports `character.json` from it):
  archive the whole repo, not only `client/`.
- A copy without the repo's `.gitignore` classifies `node_modules/` as 7,189 unknown files → `full`.
- `version.php` is docs (orchestrator, 2026-10-26): every Mooblox deploy bumps it, and as schema it put most tickets back on full PHPUnit; the db/ files of the same diff (install.xml, upgrade.php, tasks.php, …) carry schema, access.php/services.php security.
- `package.json` is class `deps`: engine only when dependencies/devDependencies/peerDependencies/optionalDependencies/overrides/engines differ from the base (or the JSON does not parse); a scripts-only edit is docs.
- The phpcs stub in `mci.test.sh` must not read stdin: phpcs-delta runs phpcs on a path without input, and a stub `cat` hung the test.
- `tier-nightly` covers only plugins run through `mci` (the `.plugin` side file); a plugin tested with `mtest` alone waits for the next mci run.
- New CLIs need `~/agents/install.sh --links` (change-class, tier-nightly: "command not found" until linked).

## Links
- Code: `~/agents/bin/change-class`, `~/agents/bin/tier-nightly`, `~/agents/units/tier-nightly.{service,timer}`, `~/.claude/skills/moodle-ci/scripts/mci`, `~/.claude/hooks/moodle-stop-reminder.sh`, `~/agents/bin/agent-verify`, `~/agents/bin/brief-lint`
- Tests: `bash ~/agents/bin/tests/run.sh --only 'bin/tests/change-class.test.sh'` (and tier-nightly, brief-check, agent-verify); `--only 'skills/moodle-ci/tests/mci.test.sh'`
- Design / results: `~/agent-work/research/2026-10-26/T1398/PROPOSAL.md`; Mooblox rules in `~/agent-work/briefs/T1276-mooblox-common.md`
