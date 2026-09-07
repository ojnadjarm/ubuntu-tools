# BASELINE-PCTOOLS — one row per `pc` command, added by each PT ticket

Method: warm = best of 5 consecutive runs (`/usr/bin/time -f %e`), cold = `--fresh` (or a cold
cache), CPU = user+sys of one run, execs = `strace -f -c -e trace=execve` on one warm run.
Budgets (PLAN-PCTOOLS §1 rule 4): ≤ 0.5 s warm for a snapshot, ≤ 0.6 s with a sampling window,
`pc trace` excepted. Measured on this machine, quiet box, owner asleep.

<!-- pc-bench:begin -->
Rewritten by `pc bench --save` on 2026-09-06. Warm = median of 3 runs, cold = `--fresh`
after clearing only `$XDG_RUNTIME_DIR/pc-status`, CPU = user+sys of the median warm run,
execs = successful `execve` from `strace -f -c -e trace=execve`. Wall resolution is 10 ms,
so `--compare` deltas on the sub-0.1 s rows are quantization, not regression.

| date | command | wall warm | wall cold | CPU | execs |
|---|---|---|---|---|---|
| 2026-09-06 | `pc status` | 0.11 s | 0.70 s | 0.09 s | 33 |
| 2026-09-06 | `pc top` | 0.38 s | 0.40 s | 0.08 s | 9 |
| 2026-09-06 | `pc io` | 0.39 s | 0.39 s | 0.11 s | 15 |
| 2026-09-06 | `pc power` | 0.55 s | 0.64 s | 0.07 s | 14 |
| 2026-09-06 | `pc thermal` | 0.19 s | 0.18 s | 0.19 s | 17 |
| 2026-09-06 | `pc kernel` | 0.16 s | 0.17 s | 0.07 s | 19 |
| 2026-09-06 | `pc trace wakeups --seconds 1` | 1.75 s | 1.75 s | 0.27 s | 21 |
| 2026-09-06 | `pc net` | 0.28 s | 0.31 s | 0.24 s | 24 |
| 2026-09-06 | `pc hw all` | 0.09 s | 0.22 s | 0.07 s | 22 |
| 2026-09-06 | `pc dbus list` | 0.03 s | 0.04 s | 0.02 s | 11 |
| 2026-09-06 | `pc mutter` | 0.12 s | 0.11 s | 0.27 s | 77 |
| 2026-09-06 | `pc units list` | 0.04 s | 0.04 s | 0.05 s | 15 |
| 2026-09-06 | `pc journal digest --since 1h` | 0.06 s | 0.06 s | 0.06 s | 13 |
| 2026-09-06 | `pc docker stacks` | 0.05 s | 0.05 s | 0.03 s | 11 |
| 2026-09-06 | `pc audio` | 0.12 s | 0.12 s | 0.14 s | 33 |
| 2026-09-06 | `pc input devices` | 0.12 s | 0.12 s | 0.09 s | 11 |
| 2026-09-06 | `pc undo list` | 0.02 s | 0.02 s | 0.01 s | 11 |
| 2026-09-06 | `pc win list` | 0.07 s | 0.07 s | 0.06 s | 6 |
| 2026-09-06 | `pc mode status` | 0.04 s | 0.18 s | 0.03 s | 13 |
| 2026-09-06 | `pc doctor --quick` | 1.20 s | 1.67 s | 0.89 s | 276 |
<!-- pc-bench:end -->

## Per-ticket notes — what each ticket measured and why

These rows are the tickets' own measurements and their findings; `pc bench --save` never touches
this section, only the table above it.

| date | command | wall warm | wall cold | CPU | execs | note |
|---|---|---|---|---|---|---|
| 2026-09-06 | `pc status` | 0.11 s | 0.75 s | 0.08 s | 35 | PT01: after `cached()` moved to `pclib.sh`; warm unchanged (0.10–0.13 s before and after), text/JSON/facts/check/brief output identical apart from live values |
| 2026-09-06 | `pc undo list` | 0.01 s | 0.01 s | 0.01 s | 3 | PT01: empty ledger; one `jq -s` pass when it is not |
| 2026-09-06 | `pc units` (default: failed+fleet+top5) | 0.30 s | 0.32 s | 0.10 s | 104 | PT13: fleet uses one batched `systemctl show` per scope (explicit unit names, not a glob — a glob `show` with ActiveState+SubState silently drops some inactive units on this systemd); top5 is user-scope only (a system-wide glob `show` alone costs ~0.13 s) |
| 2026-09-06 | `pc journal` (default: digest 1h+size) | 0.06 s | 0.08 s | 0.02 s | 18 | PT13: one `journalctl -o json` pass reduced with `jq`; digest masks digits/hex before grouping |
| 2026-09-06 | `pc kernel` | 0.20 s | 0.20 s | 0.14 s | 40 | PT05: overview (taint + lockdown + module count + 1 h dmesg digest); no cache, cold = warm; `dmesg -J` needs `sudo -n` (`kernel.dmesg_restrict=1`) and costs 0.10 s of it |
| 2026-09-06 | `pc kernel dmesg --digest` | 0.18 s | 0.18 s | 0.13 s | 33 | PT05: 1265 buffered lines → 180 err+warn in the last hour → 3 digest rows (170 of them one masked `[UFW BLOCK]` SSDP row from 192.168.1.11) |
| 2026-09-06 | `pc kernel modules` | 0.03 s | 0.03 s | 0.02 s | 25 | PT05: 244 modules from `/proc/modules` in one `jq -R -s`; `modules <name>` adds `modinfo -F description`, `/sys/module/<m>/parameters` (one `sudo -n` pass when they are root-only) and `holders` |
| 2026-09-06 | `pc kernel cgroups <unit>` | 0.04 s | 0.04 s | 0.05 s | 28 | PT05: `systemctl --user show` + the unit's `{cpu,memory,io}.pressure`; unaccounted IO is `null`/`n/a`. Unitless overview walks 91 cgroups at depth 3 in 0.09 s |
| 2026-09-06 | `pc power` | 0.55 s | 0.68 s | 0.08 s | 42 | PT03: 0.30 s RAPL/RC6 sampling window is intrinsic (budget 0.6 s); cold = the uncached `powerprofilesctl get` (60 s TTL, same cache `pc status` uses) |
| 2026-09-06 | `pc power --deep` | 1.17 s | 1.27 s | 0.12 s | 54 | PT03: adds one `turbostat --interval 0.5 --num_iterations 1` (0.6 s of its own) on top of the RAPL window — opt-in, outside the snapshot budget |
| 2026-09-06 | `pc thermal` | 0.21 s | 0.23 s | 0.23 s | 31 | PT03: all four sections (13 zones + trip points, 6 hwmon chips from `sensors -j`, fan, throttle); no cache, no sampling window |
| 2026-09-06 | `pc top` | 0.41 s | 0.44 s | 0.06+0.05 s | 1 (9 real execs; the `strace \| grep -c execve` idiom always returns 1, the calls column is 21/12 errors) | PT02: raw `/proc` two-sample window (no psutil — its API cannot pin a fixture read to tick 0 vs tick 1, needed for deterministic tests), one python3 process, no forks; 0.3 s window intrinsic |
| 2026-09-06 | `pc io` | 0.46 s | 0.46 s | 0.13+0.07 s | 1 (27 real execs: 2 parallel samplers + jq) | PT02: `disks`+`procs` run as two backgrounded samplers sharing one 0.3 s window instead of serially, to stay inside the 0.6 s budget; `smart` cached 1 h under its own key `io_smart` (not `smart` — that key is `pc status`'s, a collision was caught and fixed during this ticket) |
| 2026-09-06 | `pc net` | 0.32 s | 0.37 s | 0.11+0.19 s | 12 (`ss`+`ip`+`tailscale`×2+`jq`×several) | PT06: default = ifaces + listeners + tailscale one-liners; listener join (pid→systemd unit via `/proc/<pid>/cgroup`, or →docker container via a single cached `docker ps` pass) built with one `jq -R -s` over an in-loop TSV instead of one `jq -n`/`grep` per row — a first pass forked jq once per listening socket (95 live sockets → 1.25 s, over budget) and was rewritten to the batched form; `ss -Hltnup` needs `sudo -n` for other users' pids, tried first with an unprivileged fallback |
| 2026-09-06 | `pc net fw` | 0.15 s | 0.15 s | 0.05 s | 8 | PT06: exposure summary joins `ufw status verbose` (LAN CIDR rows + the "Anywhere on tailscale0" wildcard fanned across every port) with the `DOCKER-USER` nft chain for docker-published ports that bypass ufw's INPUT chain; `--raw` dumps `nft -j list ruleset` unfiltered; read-only, no nft/ufw write verb exists |
| 2026-09-06 | `pc dbus list --json` | 0.02 s | 0.02 s | 0.01 s | 13 | PT08: `busctl list --acquired --json=short`, 90 well-known names on the session bus |
| 2026-09-06 | `pc dbus introspect org.gnome.Shell /org/gnome/Shell --json` | 0.02 s | 0.02 s | 0.01 s | 14 | PT08: `busctl introspect` table → awk → jq; no python, no cache (budget 0.3 s) |
| 2026-09-06 | `pc dbus get … ShellVersion --json` | 0.03 s | 0.03 s | 0.03 s | 18 | PT08: one introspect to resolve the interface + `busctl get-property --json=short` |
| 2026-09-06 | `pc dbus call … Extensions/Windows List --json` | 0.03 s | 0.03 s | 0.02 s | 18 | PT08: same resolution then `busctl call --json=short`; empty window list at night |
| 2026-09-06 | `pc dbus find Idletime` | 0.04 s | 0.66 s | 0.04 s | 14 | PT08: cold = `pc_dbus.py index` walking the whole session bus (4 712 rows, 600 KB) into `cached()` 900 s; `--all` cold 1.87 s (both buses) |
| 2026-09-06 | `pc dbus owner org.gnome.Shell --json` | 0.03 s | 0.03 s | 0.04 s | 25 | PT08: `busctl status` + `GetNameOwner` |
| 2026-09-06 | `pc docker stacks` | 0.04 s | 0.04 s | 0.03 s | 13 (7 successful: script+bash shebang resolution, `readlink`, `dirname`, `jq`×2, `docker`; 6 ENOENT are the shebang's own PATH search on this box's long PATH) | PT14: one uncached `docker ps -a --format` call (EF01: never `/images/json` outside `disk`) feeds `stacks`/`ps`/`health`; the project→dir map is built with a pure-bash `while read` loop (no `dirname`/`sed`/`jq` fork per compose file) and the ps→group-by-project step is one `jq` filter; `disk` is `cached docker_disk 300`; `restart\|stop\|start` ledgered via `pc_apply`, `stop shared` refused (exit 3) while another env is up unless `--force` |
| 2026-09-06 | `pc hw` (summary) | 0.10 s | 0.33 s | 0.11 s | 42 | PT07: `dmi`/`cpu`/`pci` cached 24 h (`hw_*` keys, one `sudo -n dmidecode` block parsed for both dmi and mem's DIMMs); `usb`/`block`/`sensors` stay live; `firmware` (`fwupdmgr get-devices`, cached 24 h) is its own verb and only joins `all` behind `--firmware` since a cold fwupd call runs ~1 s; the ticket's own `all --json` success-check jq line has a precedence bug (`.pci\|length>5 and (...)` pipes `.pci`'s array into the whole and-expression) — parenthesised (`(.pci\|length>5) and (...)`) it passes against this output |
| 2026-09-06 | `pc trace` | 1.64–1.75 s (`--seconds 1`) | — | 0.25 s | 12 | PT04: bpftrace verbs `wakeups`/`sleep`/`syscalls` attach in 707 ms (3/5/4 probes), `disk`/`opens`/`execs` in 607 ms (2 probes) — the §0 table's 0.41 s `BEGIN{exit()}` floor still holds (0.52 s through `pc trace raw`); `offcpu` 2.97 s, `sched` 2.95 s and `cpu` 3.35 s at `--seconds 1` (bcc LLVM compile / `perf record`+`report`). Declared exception to the 0.5 s budget (§1 rule 4); every run is `sudo -n timeout $((seconds+10))` (+25 for bcc/perf), verified by the hung-probe test: 11 s and no `bpftrace` left |
| 2026-09-06 | `pc mutter` | 0.11 s | 0.11 s | 0.15+0.11 s | 73 | PT09: the whole model (outputs, screen consistency, workspaces, windows, idle, shell, extensions) — 8 read probes started in parallel, so the wall is one round trip, not their sum; no cache, cold = warm |
| 2026-09-06 | `pc mutter outputs --json` | 0.05 s | 0.05 s | 0.03 s | 21 | PT09: one `DisplayConfig.GetCurrentState` through `pc dbus call` → jq; tonight HDMI-1 1366x768@59.79 +0+0 primary, eDP-1 off (not the mirrored 1920x1080 of the same day), xrandr agrees |
| 2026-09-06 | `pc mutter idle --json` | 0.04 s | 0.04 s | 0.02 s | 19 | PT09: `IdleMonitor.GetIdletime` |
| 2026-09-06 | `pc mutter extensions --json` | 0.05 s | 0.05 s | 0.04 s | 29 | PT09: `ListExtensions` + the `UserExtensionsEnabled` property off the same introspect the `shell` verb uses; 8 extensions, 7 active |
| 2026-09-06 | `pc mutter windows` | 0.15 s | 0.15 s | 0.09 s | 10 | PT09: straight `pc win list --json` (window-calls), empty at night — the eye is not drawing |
| 2026-09-06 | `pc audio` | 0.12 s | 0.11 s | 0.12 s | 35 | PT11: one `pw-dump` + `pw-top -b -n1` (its `ERR` column is a running total, not a sampled window, so one batch is enough); volumes read back through `wpctl`'s cubic curve (`pow(linear;1/3)*100`) to match `vol`/`mute`; mutations (`default`, `move`, `vol`, `mute`, `loglevel`) ledgered by name via `wpctl`/`pactl`/`pw-metadata`, round-tripped tonight on a `module-null-sink` this ticket loaded and unloaded itself — never the default sink |
| 2026-09-06 | `pc input devices` | 0.12 s | 0.12 s | 0.06+0.04 s | 29 (18 fail: the `sudo -n env` exec probe) | PT10: `/proc/bus/input/devices` + one `/proc/*/fd` walk in a single python under `sudo -n` (the input group is on the user but not in shells older than it); no cache, cold = warm. `grabs` and `caps <dev>` measure the same 0.12 s |
| 2026-09-06 | `pc input watch <dev> --seconds 1` | 1.12 s | 1.12 s | 0.06 s | 29 | PT10: the window is the command; `select()` with a hard deadline, `PC_ROOT_TIMEOUT` = seconds+5, 0 events at night is a valid 0 exit |
| 2026-09-06 | `pc input inject key … --apply --device-only` | 0.46 s | 0.46 s | 0.21+0.09 s | 46 | PT10: one plan run + UInput create + a `sudo -n` reader that EVIOCGRABs the node + read-back + destroy. python-evdev's own node lookup was costing 1.9 s of the 2.3 s (19 × 0.1 s retries on a node the user cannot open) — skipped in favour of `UI_GET_SYSNAME` |
| 2026-09-06 | `pc bt status` | 0.09 s | 0.09 s | 0.09 s | 52 (18 errors) | PT12: one `pc dbus --system` GetManagedObjects round trip (0.02 s) + `systemctl --user is-active dark-eye-ptt` + the last `bluetoothd` error line (`journalctl -o json`, `cached` 60 s under key `bt-error`); cold = warm, the cache only saves the journal read |
| 2026-09-06 | `pc bt devices --json` | 0.04 s | 0.04 s | 0.10 s | 30 (12 errors) | PT12: the same single tree call, one `jq` model; every device property comes from `GetManagedObjects`, nothing is polled per device |
| 2026-09-06 | `pc bt connect buds` (dry) | 0.08 s | 0.08 s | 0.21 s | 52 (18 errors) | PT12: tree + sidecar check + the `would:` line; `--apply` was never run on the live adapter tonight (buds in their case, owner asleep) — the round trip is deferred to daylight |
| 2026-09-06 | `pc bt scan --seconds 1` | 1.19 s | 1.19 s | 0.12 s | 33 (12 errors) | PT12: the 1 s window is intrinsic. BlueZ ties discovery to the calling D-Bus client, so two one-shot `busctl` calls cannot hold it (StopDiscovery answers "No discovery started"); `bluetoothctl --timeout N scan on` keeps one connection for the window and drops discovery on exit |
