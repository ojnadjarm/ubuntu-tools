# Runaway guard: one ballooning child must not take the orchestrator pane down (OOMPolicy, MemoryMax scopes)

Ticket: T401, T407, T462 · Last verified: 2026-10-20 by T846 audit (oom.conf, run.sh/agent-verify scope flags, ci-window/brief-lint --help, `oomctl`); before: 2026-10-19 (T462 `run-sh.test.sh` 19/19; CI window, `ci-window.test.sh` 13/13); 2026-10-18 by a sandbox balloon (512M scope) on a private tmux socket and `bin/tests/brief-check.test.sh` (12/12)

## When to use
Running a test, benchmark or experiment that can grow without bound (pty readers, `script`, `tmux attach`, renderers,
model loads, fuzzers). Not for CPU or idle runaways: that is `sentinel-runaway.md`.

## The path we took
- Cause (T399 `CAUSE.md`): `script … </dev/zero` grew ~1.2 GB/s to 34 GB in the orchestrator pane's
  `tmux-spawn-*.scope`; systemd's default `OOMPolicy=stop` then stopped the whole scope, `claude` included.
- Guard 1, contain: a user prefix drop-in `~/.config/systemd/user/tmux-spawn-.scope.d/oom.conf` (`[Scope]`
  `OOMPolicy=continue`). It applies to transient tmux scopes, new ones and, after `daemon-reload`, live ones.
- Guard 2, cap: **rule — experiments that can balloon run inside their own scope:**
  `systemd-run --user --scope -q -p MemoryMax=4G -p MemorySwapMax=0 -p OOMPolicy=continue <cmd>`.
  The cgroup OOM killer then kills only `<cmd>` (rc 137) before the machine swaps; the caller keeps running.
- Guard 4, lint: `brief-lint` warns (rc unchanged) on `/dev/zero` fed into `script`/`tmux` in a brief, and
  `brief-lint --tests` scans `~/agents/bin/tests/*.sh`. Hold a client attached with `</dev/null` or `sleep inf |`.
- Guard 6, test runners (T462): `bin/tests/run.sh` runs each test file, and `agent-verify` each CHECK, in its own
  scope (`MemoryMax=${TEST_MEM_MAX:-6G}`, `MemorySwapMax=0`, `OOMPolicy=continue`); plain run when no user bus.
  run.sh reads the scope's `memory.events` and reports `FAIL <file> <s> oom`.

- Guard 5, the CI window (T407): **rule — heavy browser/test runs, swarms and renders by agents do not start 00:50–01:50.**
  The ailearning nightly (01:00) measures frame budgets; T405's visualcheck held load ~14 on 2026-10-19 and turned it red.
  Gate a heavy start with `ci-window && <cmd>` (exit 1 inside the window). The CI side waits with `ci-window --quiet`.

## Exact commands
```bash
systemctl --user show "$(basename "$(cat /proc/$$/cgroup)")" -p OOMPolicy   # this pane: want continue
systemd-run --user --scope -q -p MemoryMax=4G -p MemorySwapMax=0 -p OOMPolicy=continue bash my-experiment.sh; echo rc=$?
brief-lint --tests                       # WARN lines only, exit 0
ci-window && npm run e2e                 # heavy run only outside 00:50–01:50 (CI_WINDOW overrides)
# proof on a throwaway server, never the `claude` one
tmux -L t401 new-session -d -s oom 'sleep 3; python3 balloon.py; echo rc=$? > out; sleep 60'
systemctl --user set-property --runtime <its tmux-spawn scope> MemoryMax=512M MemorySwapMax=0
tmux -L t401 kill-server
```

## Pitfalls (measured)
- `systemctl --user cat tmux-spawn-.scope` prints "No files found": a prefix drop-in is not a unit. Read it from a
  live scope: `systemctl --user cat <tmux-spawn-….scope>` lists `tmux-spawn-.scope.d/oom.conf` and its `DropInPaths`.
- Without `MemorySwapMax=0` a capped job swaps instead of dying; T399 hit 56 kB of 8 GB swap free.
- Sandbox 2026-10-18: balloon in a 512M pane scope → rc 137, pane and sibling alive, scope `active`/`success`.
  Same balloon with `OOMPolicy=stop` → scope stopped, sibling and caller gone (rc 143).
- `systemd-run` expands `$VAR`/`${VAR}` in the command line by default (T462: `${2#dashboard/}` became empty, so
  every dashboard file ran the whole pytest suite). Pass `--expand-environment=no` when wrapping a shell command.
- Only the kernel's cgroup or global OOM kill is contained; `systemd-oomd` runs (since 2026-10-15) but `oomctl` lists no swap- or pressure-monitored cgroups, so it kills nothing (T399: no entries).

## Links
- Code: `~/.config/systemd/user/tmux-spawn-.scope.d/oom.conf`, `~/agents/bin/brief-lint`
- Tests: `bash ~/agents/bin/tests/brief-check.test.sh` (case 6), `bash ~/agents/bin/tests/ci-window.test.sh` (T407)
- Design / results: `~/agent-work/research/2026-10-18/night/T399/CAUSE.md`
