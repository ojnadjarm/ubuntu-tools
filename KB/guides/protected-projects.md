# Protected projects: add a work project every guard refuses to touch, carry the guard to another Claude install

Ticket: T1513 · Last verified: 2026-11-09 by `bash ~/agents/bin/tests/protected.test.sh` plus work-repo-guard, pc-docker, pc-failures, os-survey tests (fixture project acme)

## When to use
A project is not ours to change (Vass, a future institutional one): agents never git-write its repos, never stop/start/
recreate its containers, never reap its files, and its failed units are "protected", not fleet failures.
Adding one is config only, no code. Not for owner data (`~/agent-work/owner`, backups: `PC_DISK_PROTECT`).

## The path we took
Before: "vass" hard-coded in 10 bin files plus `WORK_REPO_ROOTS`. Now one data source, one matcher, consumers ask it:

| Layer | Where | Role |
|---|---|---|
| Data | `config.env` `PROTECTED_PROJECTS` + `PROTECTED_<NAME>_{REPOS,PATHS,CONTAINERS,UNITS,WORDS}` | the only place names live |
| Matcher | `bin/pclib.sh` `protected_match`/`protected_entries`/`protected_ere` | pure bash; `PC_NOT_OURS` = the unit ERE |
| Clients | `bin/protected` CLI, `bin/protectedlib.py` (Python, fails closed) | for hooks, Python and other shells |
| Consumers | work-repo-guard + git-guard/guard.sh + PreToolUse hook (repo), pc docker (container), pc tmp/pc disk/tier-nightly (path, text), pc status/pc failures/pc stale/orchestrator-pulse (unit), os-survey, pc mem (text/container) | each refuses or labels by asking |

Kinds: `repo` (git roots), `path` (repos + PATHS), `container` (globs on container, compose project, env dir), `unit`
(systemd globs), `text` (words in free text, any case; default the name). Fallback: with `PROTECTED_PROJECTS` empty,
legacy `WORK_REPO_ROOTS` is project `work` (repos only).

## Exact commands
```bash
# Add a project (e.g. an institutional one), in ~/.config/pc-harness/config.env:
#   PROTECTED_PROJECTS="vass <name>"
#   PROTECTED_<NAME>_REPOS="~/<repo-root>"   PROTECTED_<NAME>_CONTAINERS="<name>*"   PROTECTED_<NAME>_UNITS="<name>*"
protected list                                  # project, kind, entries
protected match container <name>-db-1           # prints the project; exit 1 when not protected
work-repo-guard install --apply                 # new REPOS roots need the git include once
work-repo-guard status
CLAUDECODE=1 git -C <repo> hook run pre-commit  # safe proof: exit 1, names the project
bash ~/agents/bin/tests/protected.test.sh
```
Carry the guard to another Claude install (do not install from here):
1. Copy `bin/pclib.sh`, `bin/env.sh`, `bin/protected`, `bin/work-repo-guard`, `git-guard/` (hooks are symlinks to `guard.sh`) and
   `hooks/sleep-loop-block.py` + `hooks/sleep-loop-block-impl.py` + `hooks/wait_nudge.py`, keeping the `bin/`, `git-guard/`, `hooks/` siblings.
2. Write the `PROTECTED_*` keys into that machine's `~/.config/pc-harness/config.env` (or point `HARNESS_CONFIG` at a file).
3. Run `work-repo-guard install --apply` there (gitconfig includeIf → core.hooksPath).
4. Register `hooks/sleep-loop-block.py` as a `PreToolUse` hook with matcher `Bash` in that install's `~/.claude/settings.json`.

## Pitfalls (measured)
- A process that inherited `HARNESS_ENV_LOADED=1` from before T1513 skips env.sh and saw nothing protected (pclib gave `^$`); pclib now reads the `PROTECTED_*` lines from config.env whenever `PROTECTED_PROJECTS` is unset.
- Tests that copy `pclib.sh` alone into a mutant dir (pc-doctor, 6 others) broke on a separate `protected.sh` (185 bytes of stderr): the matcher lives inside pclib.sh.
- Tests with a temp HOME have no config.env: they must set a fixture (`PROTECTED_PROJECTS=… PROTECTED_<N>_…`); pc-failures lost its vass rows until it did.
- `protected match` costs ~70 ms (sources pclib + env.sh); the PreToolUse hook calls it only for a git commit/push with a resolvable dir.
- Text words must not be common: legacy `work` has none, or every `agent-work` path would be skipped by pc tmp.
- Docker rows match `container` globs exactly (`4.5` is not `4.55`); text EREs are lowercase, match lowercased values.

## Links
- Code: `~/agents/bin/pclib.sh` (protected projects section), `~/agents/bin/protected`, `~/agents/bin/protectedlib.py`, `~/agents/git-guard/guard.sh`, `~/agents/hooks/sleep-loop-block-impl.py`
- Tests: `bash ~/agents/bin/tests/protected.test.sh`, `work-repo-guard.test.sh`, `pc-docker.test.sh`, `pc-failures.test.sh`, `os-survey.test.sh`
- Guides: `guide work-repo-guard`; decisions `~/agent-work/decisions/vass.md`
