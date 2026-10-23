# Block agent git commit/push in work repos (work-repo-guard)

Ticket: T1251 · Last verified: 2026-10-23 by `bash ~/agents/bin/tests/work-repo-guard.test.sh` (38 ok) and `git hook run` on the real repos

## When to use
An agent must never commit, push, merge or rebase in the owner's work repos (roots in `WORK_REPO_ROOTS`, config.env),
while the owner at his own terminal keeps full git. Personal repos (~/agents, ~/the-dark-eye, …) are not covered.
Adding a root: edit `WORK_REPO_ROOTS`, then `work-repo-guard install --apply`.

## The path we took
Two layers, no file written inside a work repo:

| Layer | Where | Catches | Misses |
|---|---|---|---|
| 1 git hooks | `~/.gitconfig` `includeIf "gitdir:<root>/".path` → `~/.config/pc-harness/work-repo-guard.gitconfig` → `core.hooksPath = ~/agents/git-guard/hooks` | any process with an agent marker: pre-commit, pre-merge-commit, pre-push, pre-rebase, and reference-transaction (refs/heads/* or HEAD to a new oid) so `commit --no-verify`, cherry-pick, reset, `checkout -b` fail too | `push --no-verify`, `-c core.hooksPath=…`, `GIT_CONFIG_GLOBAL=/dev/null`, repo-local core.hooksPath (husky), libgit2/IDE git, raw .git writes |
| 2 PreToolUse | `~/agents/hooks/sleep-loop-block-impl.py` (`work_repo_git`), already registered for Bash | Claude Bash `git commit/push` whose dir (cwd, `cd`, `x=dir`, `-C`, `--git-dir`, `GIT_DIR=`, `bash -c "…"`) resolves under a root, any flags | dirs built at run time (`$(…)`, scripts), other agent CLIs |

Markers (`git-guard/guard.sh`): CLAUDECODE, HARNESS_AGENT (env.sh exports it to every fleet script), OPENCODE,
GEMINI_CLI, CODEX_SANDBOX, CODEX_THREAD_ID. Codex and Gemini markers are unverified (CLIs not installed).
Every standard hook name in `git-guard/hooks/` is a symlink to `guard.sh`, which then execs the repo's own
`.git/hooks/<name>` (stdin passed on), so the owner's hooks keep running.

## Exact commands
```bash
work-repo-guard status              # include line per root, hooksPath origin per repo; exit 1 on a gap
work-repo-guard install             # would: lines only
work-repo-guard install --apply     # backs up ~/.gitconfig once to ~/agents/backups/gitconfig.T1251.bak
work-repo-guard uninstall --apply
git -C <work-repo> config --show-origin core.hooksPath
CLAUDECODE=1 git -C <work-repo> hook run pre-commit   # safe proof: exit 1, writes nothing
bash ~/agents/bin/tests/work-repo-guard.test.sh
```

## Pitfalls (measured)
- `git commit --no-verify` skips pre-commit, not reference-transaction: the fixture refusal is exit 128 "ref updates aborted by hook".
- `git push --no-verify` passes layer 1 (fixture exit 0); only layer 2 stops it, and only in Claude Bash.
- core.hooksPath replaces `.git/hooks` for every hook name, so a missing symlink silently drops the owner's hook of that name; 27 names linked.
- A repo-local core.hooksPath (husky `prepare`) overrides the include: `status` prints `BAD … file:.git/config`. None of the 3 work repos had one on 2026-10-23.
- `git commit --dry-run` runs no hook, so it proves nothing; use `git hook run <name>`.
- Layer 2 replay over 217 logged git commit/push commands: 1 deny, a quoted test string naming a work-repo commit (p50 22 ms, p95 27 ms). The first draft denied any unresolved `cd $T` when a root path appeared anywhere: dropped, unresolved dirs are layer 1's job.
- The owner typing `!git commit` inside a Claude session carries CLAUDECODE and is refused; his own terminal is not.

## Links
- Code: `~/agents/git-guard/guard.sh`, `~/agents/git-guard/hooks/`, `~/agents/bin/work-repo-guard`, `~/agents/hooks/sleep-loop-block-impl.py`
- Tests: `bash ~/agents/bin/tests/work-repo-guard.test.sh` (mktemp HOME, fixture GIT_CONFIG_GLOBAL; selftest checks the real gitconfig sha and work-repo .git mtimes)
- Decisions: `~/agent-work/decisions/vass.md`
