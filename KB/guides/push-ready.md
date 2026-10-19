# Can I push this repo? `push-ready <repo>` (one verdict line)

Ticket: T394 · Last verified: 2026-10-18 by `bash ~/agents/bin/tests/push-ready.test.sh` and three real-repo runs

## When to use
The owner asks "can I push?" or a ticket ends in a repo he pushes. Read-only: it never runs a git write
command and never pushes; the push stays his. Not for ~/agents tests (use `no-machine-values.test.sh`).

## The path we took
Survey: no secrets scanner on the machine (gitleaks, trufflehog, detect-secrets absent; toolbox.md lists none);
`bin/tests/no-machine-values.test.sh <repo>` already scans every pushable file for machine values. Chosen: one
bash CLI that reuses that test for machine values and adds four small checks; installing gitleaks is a later
upgrade if regexes miss.

| Part | What it does |
|---|---|
| file set | `git ls-files --cached --others --exclude-standard` = what `git add -A && git push` would ship |
| `machine` | runs `no-machine-values.test.sh <repo>`, one issue per file with hits; plus `/run/user/<uid>` literals |
| `secret` | token regexes (private key, AWS, GitHub, Slack, OpenAI/Anthropic `sk-`, Google, Discord) + literal values read from `~/agents/secrets/` at run time; prints `file:line` only, never the value |
| `junk` | tracked or untracked-not-ignored paths under `node_modules`, `dist`, `mock(s)`, `mockup(s)`, `qa`, `review(s)`, `.env*`, caches, logs; plus a missing `.gitignore` |
| `large` | pushable file over `PUSH_READY_MAX_KB` (default 5120) |
| allowlist | `~/.config/pc-harness/push-ready.allow`: `<repo-basename> <ERE on the issue line>` per line |

Single responsibility per check function, each prints `kind<TAB>where<TAB>detail`; the main loop only filters by
the allowlist and counts. A new check is one new function plus one call (open/closed).

## Exact commands
```bash
push-ready ~/projects/personal/portfolio      # READY (25 files) | NOT READY: 2 issues + list; exit 0 / 1, 2 = usage
PUSH_READY_MAX_KB=20000 push-ready ~/moodle-harness
echo 'ailearning ^large	public/bundles/' >> ~/.config/pc-harness/push-ready.allow   # accept a known issue
bash ~/agents/bin/tests/push-ready.test.sh   # throwaway fixture repos + a git shim that fails on any write verb
```

## Pitfalls (measured)
- `no-machine-values.test.sh` skips `^bench/` for ~/agents; push-ready passes `NO_MACHINE_VALUES_SKIP='^$'` so
  other repos get every file scanned. Set the variable yourself to keep the ~/agents exemption.
- Its selftest runs `git init` in its own mktemp dir; the push-ready test proves no write verb touches the
  target repo (shim log + `.git/index` and HEAD hashes before = after).
- Worktree content is scanned, not the staged blob: a fix you have not re-staged still reads clean.
- Secret values containing `://` (server URLs) or shorter than 12 characters are not used as literals.

## Links
- Code: `~/agents/bin/push-ready`
- Tests: `bash ~/agents/bin/tests/push-ready.test.sh`
- Design / results: `~/agent-work/research/2026-10-18/night/T392/FRICTION.md` row 6
