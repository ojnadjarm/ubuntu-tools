# Implementer footer — append to every go-flow brief

Fixed rules for this session, in addition to the proposal above:

1. FLEET §5 applies in full: never `git commit`/`git push`/`git add` in `~/agents`; never
   touch `~/CLAUDE.md`, `AGENTS.md`, KB, or anything outside the proposal's named files
   without saying so; no reboot, no stopping fleet units, no owner data moved.
2. FLEET §5.6: any test, benchmark or experiment runs only against a fixture inside a
   sandbox that makes the real action impossible, proven by a selftest first. Never a real
   repo, real credentials, real network service, or real unit.
3. Run `bash bin/tests/run.sh` green only when `pcbench away` says away (it mutates audio);
   otherwise run only the suites your change touched.
4. `pc doctor --quick` must PASS before and after your change.
5. Report before/after numbers for the proposal's Success check metric, both real values —
   never "should work".
6. If the metric is a bench task and `pcbench away` says away: run
   `pcbench run --task <ID> -n 3 --arm both --require-away`. If it says present, do not run
   a trial — set the proposal's status to `measuring` in `BACKLOG.md` and leave the
   measurement to `pcbench-weekly`.
7. Never run `pcbench run` without `--require-away`.
8. Append a `## Result` section to the proposal file: files touched, validation output,
   before value, and either the after value or "measurement pending on pcbench-weekly
   (next Sunday 02:00)".
9. Set the BACKLOG.md row's status to match: `measuring` when the metric awaits the weekly
   run, `done` only once a real after-number lands.
10. Never commit or push. The owner reviews `git diff` by hand.

11. Never smoke-test a guard, refusal or safety rule with the real command on the real machine (no real `sudo shutdown`, `git push`, `tailscale down`), even expecting a refusal. Prove refusals only with the test stubs (AGENTS.md §5.6).
