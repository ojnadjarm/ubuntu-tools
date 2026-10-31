# Daily integration branch: every open PR of a repo merged into one branch for a single review

Ticket: T1435 · Last verified: 2026-10-31 by `bin/tests/pr-daily-branch.test.sh` (14 checks) and a live run on Tiny Epic Narrator (PRs #11 + #12 → `liaison/diaria-2026-10-31`, PR #13)

## When to use
A maintainer leaves PRs unmerged for days and asks for "una rama diaria con todo lo acumulado": one branch per day with
every open dev PR merged in, reviewed and merged as one PR. Not for stacking a PR on another (branch from that PR), nor
for bringing one PR up to date (merge `origin/main` into its own branch).

## The path we took
- Survey: GitHub merge queue (needs org settings and branch protection we do not own), `git octopus` merges (one
  commit hides which PR brought what, stops on the first conflict with nothing to resume), hand-made branches
  (T1414 jobs did this by hand). Chosen: a small CLI over `git` + `gh`, one `--no-ff` merge per PR, resumable.
- `bin/pr-daily-branch <clone>`: `gh pr list` (open PRs into `--base` with heads under `--prefix`, the daily branches
  `<prefix>diaria-*` left out, oldest first) → detached worktree `<clone>-wt-<branch>` from `origin/<branch>` if it
  exists, else `origin/<base>` → `git merge --no-ff -m "Rama diaria: une #N (<head>)"` per PR, heads already in skipped
  → `--test` in the worktree → plain `git push origin HEAD:<branch>` (never forced) → worktree removed.
- Conflict: exit 3, the worktree stays with the merge open; resolve, `git commit --no-edit`, re-run the same command.
- The clone's own checkout is never touched (other jobs keep their worktrees and branches).

## Exact commands
```bash
pr-daily-branch ~/projects/collab/<repo>                       # would: liaison/diaria-<date> = origin/main + #11 …, #12 …
pr-daily-branch ~/projects/collab/<repo> --test 'npm test' --apply
# exit 3 → cd ~/projects/collab/<repo>-wt-liaison-diaria-<date>; fix the files; git add …; git commit --no-edit; re-run
gh pr create -R <owner>/<repo> --base main --head liaison/diaria-<date> --title "Rama diaria <date>: #11 + #12" --body "…"
```
Options: `--repo OWNER/NAME` (else parsed from origin), `--base main`, `--prefix liaison/`, `--name <branch>`.
Exit 0 done or nothing to do, 2 usage, 3 conflict, 4 `--test` failed (worktree kept, nothing pushed), 5 push refused.
Registry: `discord-liaison/projects.json` rule `daily` tells liaison workers when to run it for a project.

## Pitfalls (measured)
- Every PR bumps the same service-worker cache constant: #11 `ten-v7` and #12 `ten-v8` were the one conflict on
  2026-10-31. Keep the higher name and the union of the asset lists; say so in the daily PR.
- The agents' git guard (`bin/guards/git`, on PATH under `agent-exec`) refuses commits in repos outside
  ~/agents, the personal repos and ~/projects/collab: the first fixture run had 9 FAILs from refused commits in /tmp. The test
  drops the guards dir from the fixture's PATH (the fixture is the sandbox, FLEET.md §5.6) and proves with a selftest that origin is a
  local bare repo and `gh` is a fake.
- Adding a PR to the day's branch later: re-run the same command (live 2026-10-31: #14 added, `in:` ×3, `merged:` ×1,
  fast-forward push). Then retitle the daily PR with `gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -f title=… -f body=…`:
  `gh pr edit` failed on this repo with the "Projects (classic) is being deprecated" GraphQL error.
- Merging the daily PR makes GitHub mark the PRs it contains as merged; merging those PRs one by one leaves the daily PR
  empty: close it.
- New CLI in ~/agents/bin: run `~/agents/install.sh --links` or live sessions get "command not found".

## Links
- Code: `~/agents/bin/pr-daily-branch`
- Tests: `~/agents/bin/tests/pr-daily-branch.test.sh` (fixture: local bare origin, fake `gh`; `bin/tests/run.sh --only 'bin/tests/pr-daily-branch*'`)
- First use: RunarStudio/Tiny_Epic_Narrator PR #13; guide `discord-liaison`
