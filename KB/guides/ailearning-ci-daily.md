# Daily ailearning full suite on a timer

Ticket: T140 · Last verified: 2026-09-29 by a hand run (`systemctl --user start ailearning-ci-daily.service`): rc 0, 423 s

## When to use
Reading, changing or re-running the once-a-day `npm run ci` of ailearning. Agents run `npm run test:changed`, never the full suite.

## The path we took
Copied from `pcbench-weekly` (bash `.service` + `.timer`, log in `~/agents/log/`). `bin/ailearning-ci-daily` copies the repo with `cp -a`
(the build and e2e write `dist/` and `out/`; `git worktree` would be a git write) to `/var/tmp/ailearning-ci.*`, adds `--mute-audio` to
the copy's `tests/lib/browser.mjs`, loads node from nvm, runs `npm run ci`, appends one row to `ailearning-ci.jsonl`, pushes once on a
failure (EXIT trap, also on a timeout TERM) and deletes the copy.

## Exact commands
```bash
systemctl --user start ailearning-ci-daily.service     # run it now (~7 min)
tail -1 ~/agents/log/ailearning-ci.jsonl                # last result
less ~/agents/log/ailearning-ci.log                     # last full output
```

## Pitfalls (measured)
- node is not on PATH in `bash -lc`: nvm loads only in interactive shells, so the runner sources `~/.nvm/nvm.sh`.
- The suite's browser is headless but had no `--mute-audio`; the runner patches only the throwaway copy.
- `hygiene` runs `git ls-files`, so the copy keeps `.git` (12 MB); total copy ~364 MB.

## Links
- Code: `~/agents/bin/ailearning-ci-daily`, `~/.config/systemd/user/ailearning-ci-daily.{service,timer}`
- Roster: `~/agents/KB/orchestrator.md`
