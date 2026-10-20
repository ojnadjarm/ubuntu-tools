# Run a render, build or encode without taking the owner's CPU

Ticket: T775, T989 · Last verified: 2026-10-20 (T989) by `bin/tests/heavy.test.sh` (39/39), a live `heavy at` smoke (ran in a scope, units self-removed) and the T787/T788/T856 move

## When to use
Any heavy run an agent starts by hand: renders (Blender, Remotion, motion-video), encodes, C++/Godot builds, a full test file or suite, or "the owner needs the CPU". Nightly units get the same through `Slice=fleet-heavy.slice`. Not a time gate: inside the CI window still use `ci-window && heavy run -- …`. A run at a set time (tonight 02:45): `heavy at`, never a hand-typed `systemd-run --on-calendar`.

## The path we took
- Exists: `nice` only reorders inside one cgroup; agents and the owner's apps sit in sibling cgroups, so a niced render still took its cgroup's full share. systemd 259 has `CPUWeight=idle` (cgroup `cpu.idle=1`: runs on cycles nobody else wants). `at`/`batch` are not installed.
- Chosen: `systemd-run --user --scope` into `fleet-heavy.slice`; a scope keeps the caller's cwd, env and exit code (systemd-run execs the command).
- Slices: a dash means hierarchy, so `fleet-heavy.slice` lives under `fleet.slice`. Both ship `CPUWeight=idle` in `~/agents/units/`; idle on the child alone only ranks it against its (empty) siblings.

| piece | does |
|---|---|
| `bin/heavy run [--ticket T<n>] -- <cmd>` | scope in fleet-heavy.slice, `-p CPUWeight=idle -p IOWeight=10 --nice=19`; no user bus: `nice -n 19 ionice -c3`, said on stderr |
| last stderr line | `heavy: <s> wall, <s> cpu (scope\|nice), ticket T<n>` (cpu = the command's user+sys) |
| `bin/heavy at <OnCalendar> --ticket T<n> [--desc T] [--apply] -- <cmd>` | heavy-T<n>.{timer,service} in `~/.config/systemd/user`: `Persistent=true`, ExecStart `heavy run --ticket T<n> -- <cmd>`, ExecStopPost `heavy at --cancel T<n>` (both files gone after the run); dry run prints `would:`; last line `rollback: heavy at --cancel T<n>` |
| `heavy at --list` / `--cancel T<n>` | ticket, next elapse, persistent\|transient, cmd / stop+disable, remove files, daemon-reload |
| `log/heavy.jsonl` | one row a run: ts, ticket, mode, cwd, cmd, rc, wall_s, cpu_s (`HEAVY_LOG` overrides) |
| `units/fleet.slice`, `units/fleet-heavy.slice` | `CPUWeight=idle` |
| `fleet-ci-daily.service`, `gamedev-perf.service` | `Slice=fleet-heavy.slice` |

## Exact commands
```bash
heavy run --ticket T123 -- blender -b scene.blend -a           # rc is blender's
heavy run --ticket T123 -- cmake --build build -j8
ci-window && heavy run -- bash ~/agents/bin/tests/run.sh --only bin/tests/x.test.sh
# install changed units the install.sh step-4 way, then read back
~/agents/install.sh                                            # or cp the changed units/ files + systemctl --user daemon-reload
systemctl --user show -p Slice fleet-ci-daily.service gamedev-perf.service
systemctl --user show -p CPUWeight fleet.slice fleet-heavy.slice
cat /sys/fs/cgroup/user.slice/user-$UID.slice/user@$UID.service/fleet.slice/cpu.idle   # 1 while a heavy scope runs
heavy at '2026-10-21 02:45' --ticket T123 --desc 'T123 night render' --apply -- /bin/bash -lc 'ci-window --quiet; exec ~/x/make.sh'
heavy at --list                                                # T123   10-21 02:45 persistent "/bin/bash" ...
heavy at --cancel T123
nice -n 19 bash ~/agents/bin/tests/heavy.test.sh
```

## Pitfalls (measured)
- `--slice=fleet-heavy.slice` lands in `fleet.slice/fleet-heavy.slice` (T775 probe, `/proc/self/cgroup`); without `units/fleet.slice` the parent ran at weight 100, equal to app.slice.
- The user manager delegates only `cpu memory pids` (`cgroup.subtree_control`), so `IOWeight=10` is a no-op; nice 19 still drops best-effort I/O to priority 7.
- The scope is gone when the command exits, so `CPUUsageNSec` cannot be read afterwards; heavy takes cutime+cstime from `/proc/$$/stat` (a 0.3 s loop reads 0.28 s). `times` inside `$(…)` reads 0: the subshell has no children.
- The bus probe (`systemd-run --user --scope -q true`) costs ~40 ms a run.
- `systemd-run --on-calendar` timers are transient: files in `/run/user/$UID/systemd/transient`, gone on reboot (auto reboots are on) even with `Persistent=true`; T787/T788/T856 were moved to `heavy at` on 2026-10-20 (T989).
- `heavy at --apply` refuses when a transient `heavy-T<n>` exists (the /run copy outranks ~/.config): `systemctl --user stop heavy-T<n>.timer` first (no `pc` verb stops a user timer).
- `Persistent=true` with a one-shot date: a run missed while off or asleep fires once on boot/wake; the ExecStopPost cancel then removes the units, so it never repeats. `daemon-reload` from ExecStopPost works (live smoke 2026-10-20).
- The scope's stdout is logged under the scope unit, not `heavy-T<n>.service`: identifier `heavy`: `journalctl --user -t heavy -g <text>` (2026-10-20: `smoke-ran` under `run-p….scope`); rc and times in `log/heavy.jsonl`.
- New CLI: `~/agents/install.sh --links` (done 2026-10-20) or live sessions get "command not found".

## Links
- Code: `~/agents/bin/heavy`, `~/agents/units/fleet.slice`, `~/agents/units/fleet-heavy.slice`
- Tests: `nice -n 19 bash ~/agents/bin/tests/heavy.test.sh` (stub systemd-run and systemctl on PATH, mktemp XDG dirs: argv, rc, fallback, at/list/cancel)
- Design: `~/agent-work/research/2026-10-20/T773/BACKLOG.md` §2, `~/agent-work/research/2026-10-20/T985/BACKLOG.md` §4 (T989)
