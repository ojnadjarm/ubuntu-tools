# Netdata CPU cost: which collectors to trim and how to measure it

Ticket: T1041 · Last verified: 2026-10-21 by 50 s CPUUsageNSec windows of netdata.service + systemd-logind

## When to use
netdata (or logind, polled by it) shows up in `pc top` / cgroup CPU sums, or a collector is added and the cost must be checked.
Not for alarm routing (that is netdata-alert-drain) or Docker collector cost (EF01, /etc/netdata/go.d/docker.conf).

## The path we took
Stock netdata with the T26 config; every change through `pc conf put … --reload netdata --apply` (T1040), one undo id each.
| Knob | File | Before → after | Why |
|---|---|---|---|
| go.d `intelgpu` | /etc/netdata/go.d.conf | on → off | spawns `intel_gpu_top -J -s 2500`: 33 CPU s/h; `pc power` reads RC6/freq on demand |
| go.d `logind` | go.d.conf | on → off | GetAll/ListSessions/ListUsers ~1/s: 31 s/h inside systemd-logind |
| go.d `systemdunits` | go.d.conf | on → off | 207 charts + a PID1 D-Bus poll; `pc status`/`pc doctor` already report failed units |
| `[db] update every` | /etc/netdata/netdata.conf | 5 → 10 | global cadence (proc, go.d, journal plugin follow it) |
| `[plugin:apps] update every` | netdata.conf | 10 → 30 | 1,074 charts |
| `[plugin:cgroups] update every` | netdata.conf | 5 → 30 | 550 charts (11 containers + systemd) |
| `[web] web server threads` | netdata.conf | 16 (= CPUs) → 2 | each idle thread costs ~30 ms per 50 s; one owner, tailnet dashboard |
| `[plugin:cgroups] check for new cgroups every` | netdata.conf | 30 → 60 | discovery + `cgroup-name` lookups; a new container shows up within 60 s |
| `[statsd] enabled` | netdata.conf | yes → no | nothing sends to :8125; STATSD_IN cost ~40 ms per 50 s |
| `[plugins] idlejitter` | netdata.conf | on → off | 90 ms per 30 s of a 20 ms sleep loop |

Result: netdata + logind per 50 s 2,191 ms → 431–627 ms (5 windows, load 0.55–1.31, ≥ 3 min after restart).
The step before statsd/threads/discovery measured 651–908 ms (810 and 858 ms at load 0.5): above the 800 ms CHECK.

## Rollback (newest first)
The three netdata.conf ids chain: each undo restores the bytes before it, so undo newest first, one at a time.
```bash
pc undo dmaeq22z7rs7 --apply   # netdata.conf: web threads 2, cgroups discovery 60, statsd off
pc undo dmaehiyoyser --apply   # netdata.conf: db 10 s, web threads 4, idlejitter off
pc undo dmaebxd2w10v --apply   # go.d.conf: systemdunits off
pc undo dmae5w0vppse --apply   # netdata.conf: first trim
pc undo dmae23pc9mma --apply   # netdata.conf: T26 original
pc undo dmae218vpvtw --apply   # go.d.conf: intelgpu + logind off (removes the file)
```
Out of order, `pc undo` refuses ("is now sha:…, not the ledger's … use --force"); `--force` on an older id also drops every later netdata.conf change.

## Exact commands
```bash
u(){ echo $(( $(systemctl show netdata -p CPUUsageNSec --value) + $(systemctl show systemd-logind -p CPUUsageNSec --value) )); }
a=$(u); timeout 50 tail -f /dev/null; b=$(u); echo $(( (b-a)/1000000 )) ms/50s
pc conf get /etc/netdata/netdata.conf            # last ledger id
pc conf put /etc/netdata/go.d.conf --from <file> --reload netdata          # dry run diff
sudo timeout 15 dbus-monitor --system destination=org.freedesktop.login1   # who polls logind
curl -s 127.0.0.1:19999/api/v1/charts | python3 -c 'import json,sys,collections as c; d=json.load(sys.stdin)["charts"]; print(c.Counter(v.get("plugin") for v in d.values()))'
```

## Pitfalls (measured)
- `pc conf … --reload netdata` prints `reload failed`, yet netdata restarts fine: the restart takes ~8 s and `pc_root`'s `PC_ROOT_TIMEOUT` kills the waiting `systemctl` first. Check `systemctl show netdata -p ActiveEnterTimestamp`.
- `pc conf` writes with `sudo install -m <mode>` and drops the group: netdata.conf is root:root 0640 (was root:netdata). netdata reads it as root before dropping privileges, so it works; `pc undo` keeps root:root too. Open: pc-conf must keep owner/group (`install -o -g`), held by T1048; until then `sudo chgrp netdata /etc/netdata/netdata.conf` restores it by hand.
- CPU time per window grows at idle (low clocks): the previous config measured 650 ms at load 4 and 900 ms at load 0.3. Compare at similar load, and never in the first ~3 min after a restart (one window at +1 min measured 5,448 ms).
- `wait-for … --until` returns at once on `curl …/info` during a restart: the old process still answers while it stops (~17 s). Wait for a new `ActiveEnterTimestamp`.
- `/etc/netdata/go.d.conf` replaces the stock one wholesale: keep `enabled`, `default_run`, `max_procs`, with `default_run: no` list only the modules you turn on.
- go.d auto-detection (`default_run: yes`) polled the Vass mongo/redis containers every 10 s; T1084 set `default_run: no` with only `docker: yes`. Never re-enable mongodb/redis jobs: Vass is never touched.

## Links
- Code: /etc/netdata/netdata.conf, /etc/netdata/go.d.conf (backups: ~/agents/backups/conf/)
- Tests: the T1041 CHECK in ~/agent-work/research/2026-10-21/T1037/BACKLOG.md
- Design / results: ~/agent-work/research/2026-10-21/T1037/measurements.txt
