# ci-fix — one fix attempt for a red ailearning nightly CI run (launched by ci-autofix, T402)
The CI failed. Failure note (cluster line + log tail): ~/agents/state/ci-fix/2026-10-19.md · full log: ~/agents/log/ailearning-ci.log
Cluster: ailearning-ci-daily · exit 1 · ✖ ci failed at ci (rc 1): e2e: 17 jobs in 528 s, 1 failed: sheet-change

1. Read the note and the log; `guide <words of the error>`; read `$AGENT_WORK/decisions/<project>.md` if it exists. Declare files in `~/agents/FILE-CLAIMS.md` (`claims add`) before editing; release them when done.
2. Find the cause in ~/projects/personal/ailearning. Work only inside ~/projects/personal/ailearning: no edits anywhere else, never `git commit`/`git push`/`reset`/`checkout`/`stash`; leave the change unstaged for the owner.
3. Fix it with the smallest change: a real bug gets a fix; a flaky test gets a deterministic wait or a fix of the race, never a skip, a retry loop or a longer timeout alone. Owner decisions in the ledger win over the test.
4. Verify only the failing test or step (e.g. `npm run test:changed`, the one e2e job, `npm run declutter -- <slug> --size 1366x768`); never the full `npm run ci` and never the CI runner itself; ci-autofix re-runs the CI after you exit.
5. No `notify-owner` (ci-autofix pushes if the CI is still red), no sound, browsers headless with `--mute-audio`.
6. Overwrite `REPORT.md` with at most 5 lines: cause, files changed, the check you ran and its result; or why no safe fix exists.
