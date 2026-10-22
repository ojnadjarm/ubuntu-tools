# Runaway guard: one ballooning child must not take the orchestrator pane down (OOMPolicy, MemoryMax scopes)

Ticket: T401, T407, T462, T1046, T1052, T1075 · Last verified: 2026-10-21 by T1052 (agents.slice, weight.conf, pinned 30 s probe bench at 100/50/idle); by T1046 (oomd sandbox balloon, `oomctl`, two user reloads); before: 2026-10-20 by T846 audit (oom.conf, run.sh/agent-verify scope flags, ci-window/brief-lint --help, `oomctl`); before: 2026-10-19 (T462 `run-sh.test.sh` 19/19; CI window, `ci-window.test.sh` 13/13); 2026-10-18 by a sandbox balloon (512M scope) on a private tmux socket and `bin/tests/brief-check.test.sh` (12/12)

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
- Guard 7, last resort (T1046): `systemd-oomd` kills a cgroup whose memory pressure stays over its limit.
  Registration: PID1 reports system units over `/run/systemd/io.systemd.ManagedOOM` (oomd subscribes); each user
  manager reports its own units to `/run/systemd/oom/io.systemd.ManagedOOM`. Both reach oomd (a transient probe from
  each manager showed up in `oomctl`). Cause of "0 monitored": the user manager's root `-.slice` *is* the
  `user@<uid>.service` cgroup. On every `systemctl --user daemon-reload` it reports `-.slice` as
  `ManagedOOMMemoryPressure=auto`, and oomd drops that path, so the Ubuntu `kill`/50% default on `user@.service`
  was lost. Measured: a system reload re-added `user@<uid>.service`; one user reload removed it again.
  Fix: `~/.config/systemd/user/-.slice.d/90-oomd.conf` (`[Slice]` `ManagedOOMMemoryPressure=kill`,
  `ManagedOOMMemoryPressureLimit=50%`) through `pc conf put … --daemon-reload --user --apply`. Both managers now
  report the same path as kill/50%. No re-login and no reboot needed. `pc status` row `oomd_monitored` WARNs at 0.
- Guard 8, CPU share (T1052): `tmux-spawn-.scope.d/weight.conf` (`[Scope]` `Slice=agents.slice`, `CPUWeight=50`) and
  `agents.slice.d/weight.conf` (`[Slice]` `CPUWeight=50`). New panes start in `agents.slice`, a sibling of `app.slice`
  and `session.slice` (100 each), so all agent shells together get half the owner's CPU share under contention.
  A pane started before the change keeps its `app.slice` cgroup; only its `Slice=` property reads `agents.slice`.
- Guard 5, the CI window (T407): **rule — heavy browser/test runs, swarms and renders by agents do not start 00:50–01:50.**
  The ailearning nightly (01:00) measures frame budgets; T405's visualcheck held load ~14 on 2026-10-19 and turned it red.
  Gate a heavy start with `ci-window && <cmd>` (exit 1 inside the window). The CI side waits with `ci-window --quiet`.
- Guard 9, keep the voice worker resident (T1075): `MemoryLow=1700M` (voice.js 1,339,496 kB +
  eye-render 27,776 kB RSS + 25 %, read 2026-10-21 after T1062). cgroup2 is mounted `memory_recursiveprot`, so a
  child's protection is capped by its ancestors': all five need it or the leaf is inert:
  `user.slice`, `user-<uid>.slice`, `user@<uid>.service` (system drop-ins), `app.slice`, `dark-eye.service` (user).
  The first four are applied (`90-memlow.conf` via `pc conf put … --daemon-reload [--user] --apply`, 2026-10-21;
  `memory.low` reads 1782579200 on each). `pc conf` refuses `dark-eye.service.d` (fleet unit), so the owner adds
  that one (owner-todo 28). Drop-in bodies: `~/agent-work/research/2026-10-21/T1075/memlow-{Slice,Service}.conf`.

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
- Before T1046, `oomctl` listed 0 cgroups (the `-.slice` clash above). Fix applied 2026-10-21: `user@<uid>.service` is
  monitored at 50% and stays after `systemctl --user daemon-reload`. Undo: `pc undo dmae1gbce0ly`.
- oomd sandbox 2026-10-21: `systemd-run --user --scope -p ManagedOOMMemoryPressure=kill -p
  ManagedOOMMemoryPressureLimit=10% -p ManagedOOMMemoryPressureDurationSec=5s -p MemoryMax=1G -p MemoryHigh=300M
  -p MemorySwapMax=0` balloon (600 MB): oomd killed it after 11 s (rc 137, "49.64% > 10.00% for > 5s with reclaim
  activity"). The sibling unit and the caller stayed alive. Without `MemoryHigh` the kernel cgroup OOM wins first
  because pressure needs reclaim to stall, not a hard cap.
- T1052 bench (4 loops vs 2 ms-sleep probes, pinned to CPUs 2-3, 30 s; `evidence/T1052/wbench2.sh <weight>`):
  probes in `session.slice` + `app.slice`, loops' slice at 100 / 50 / idle → session p95 838 / 835 / 57 µs,
  app p95 945 / 836 / 57 µs. A CPU weight shares bandwidth; it does not shorten wake latency. Only
  `CPUWeight=idle` (SCHED_IDLE, as `fleet.slice`) cuts the p95. With one probe alone, p95 is ~56 µs at any weight. Undo: `pc undo dmae629tah1z`, `pc undo dmae5y1hrxxb`.
- `IOWeight` has no effect here: `user@.service` has `Delegate=pids memory cpu` (no io), and `nvme0n1` uses the
  `none` scheduler without iocost. weight.conf no longer sets it.
- `sudo oomctl` is the only reader. `SubscribeManagedOOMCGroups` returns `SubscriptionTaken`, because oomd holds the
  one subscription.

## Links
- Code: `~/.config/systemd/user/tmux-spawn-.scope.d/oom.conf`, `weight.conf` + `agents.slice.d/weight.conf` (T1052), `~/.config/systemd/user/-.slice.d/90-oomd.conf`, `~/agents/bin/brief-lint`, `~/agents/bin/pc-status` (`oomd_monitored`)
- Tests: `bash ~/agents/bin/tests/brief-check.test.sh` (case 6), `bash ~/agents/bin/tests/ci-window.test.sh` (T407), `bash ~/agents/bin/tests/pc-status.test.sh` (case 12, T1046)
- Design / results: `~/agent-work/research/2026-10-18/night/T399/CAUSE.md`, `~/agent-work/evidence/T1052/sched-p95.txt`
