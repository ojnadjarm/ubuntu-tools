# pc-cli.md — every `pc` command, generated

Regenerate: `pc help --md > ~/agents/KB/pc-cli.md`. Never hand-edit.

## Desktop — screen, pointer, keyboard, windows (the original layer)

| command | description | usage | bench (warm) |
|---|---|---|---|
| `pc a11y-click` | find a UI element by name and click it (or do its action). | `pc a11y-click "name" [--role R] [--app SUB]` | — |
| `pc click` | move to X Y and click. | `pc click X Y [left\|right\|middle] [--double]` | — |
| `pc click-text` | OCR-find text and click it. | `pc click-text "text" [--index N] [--region X,Y,W,H] [left\|right\|middle] [--double]` | — |
| `pc clip` | read or write the Wayland clipboard. | `pc clip get \| pc clip set "text"` | — |
| `pc drag` | press at the first point, move, release at the second. | `pc drag X1 Y1 X2 Y2` | — |
| `pc find` | OCR the screen and print the centre X Y of the text. | `pc find "text" [--all] [--region X,Y,W,H] [--json] [--shot FILE]` | — |
| `pc key` | key chords via ydotool keycodes, e.g. Return, ctrl+l, shift+Print. | `pc key [--force] KEY [KEY...]   e.g. Return  ctrl+l  shift+Print` | — |
| `pc mode` | switch the desktop profile between agent-first and stock GNOME. | `pc mode [agent\|human\|status]` | 0.04 s |
| `pc move` | absolute pointer move. | `pc move X Y` | — |
| `pc notify` | desktop notification on this screen. | `pc notify "msg" [title]` | — |
| `pc open` | launch in the desktop session and return immediately. | `pc open <url\|file\|app>` | — |
| `pc scroll` | wheel scroll, optionally after moving the pointer. | `pc scroll up\|down [N] [--at X Y]` | — |
| `pc see` | text digest of the screen: focus, windows, UI tree, notifications, clipboard. | `pc see [SEL] [--json] [--max-bytes N] (soft cap: the fixed sections are a floor)` | — |
| `pc selftest` | drives gnome-calculator with type/key/clip and a screenshot; prints PASS or FAIL. | `pc selftest` | — |
| `pc shot` | screenshot the screen or a region; --diff reports what changed since the previous shot. | `pc shot [out.png] [--scale F] [--region X,Y,W,H] [--diff [PREV]] [--ignore X,Y,W,H] [--changed-only] [--quiet]` | — |
| `pc spotify` | drive the Spotify desktop app over MPRIS; no screenshots, ever. | `pc spotify <command> [args]` | — |
| `pc status` | live health snapshot of this machine (text, --json, --check, --brief, --facts, --fresh). | `pc status [--json\|--check\|--brief\|--facts] [--fresh]` | 0.11 s |
| `pc tree` | AT-SPI UI tree. | `pc tree [app-substring] [--depth N] [--json] [--max N] [--interactive] [--find "name"] [--role R]` | — |
| `pc type` | type text via mutter RemoteDesktop keysyms ("\n" = Enter, "\t" = Tab). | `pc type [--force] "text"` | — |
| `pc wait` | sleep S seconds, then take a screenshot; prints its path. | `pc wait SECONDS [shot args]` | — |
| `pc wait-for` | block until one UI condition holds, polling cheap text every 250 ms. | `pc wait-for (--window SUB \| --focus SUB \| --text NAME [--app SUB] \| --gone SUB) [--timeout S] [--see]` | — |
| `pc win` | list/focus/move/resize/close/minimize/maximize windows via the Window Calls extension. | `pc win <command> [args]` | 0.07 s |

## Kernel & hardware — CPU/wake, IO, power, thermal, tracing, net, hw

| command | description | usage | bench (warm) |
|---|---|---|---|
| `pc hw` | PCI/USB/DMI/sensors/block/memory, cached where it never changes. | `pc hw [summary] [--json]` | 0.09 s |
| `pc io` | disk throughput/latency, top IO procs, SMART (default: disks + top 5 procs) | `pc io [disks\|procs\|smart] [--seconds 0.3] [-n 5] [--json]` | 0.39 s |
| `pc kernel` | ring buffer with a severity digest, modules, ledgered sysctl, cgroup cost and PSI. | `pc kernel [--json]                                   overview: release, boot, taint, lockdown, dmesg digest` | 0.16 s |
| `pc net` | interfaces, listeners, port owners, tailscale, firewall (read-only), wifi, DNS. | `pc net [ifaces\|listeners\|tailscale] [--json]        default: ifaces + listeners + tailscale one-liners` | 0.28 s |
| `pc power` | watts, GPU, battery and the power profiles; mutations ledgered. | `pc power [status] [--seconds 0.3] [--deep] [--json]` | 0.55 s |
| `pc thermal` | every thermal zone, hwmon chip, the ASUS fan (read-only) and the throttle reasons. | `pc thermal [zones\|hwmon\|fan\|throttle] [--json]` | 0.19 s |
| `pc top` | per-process CPU/wake/RSS/PSS/IO/unit snapshot over one sampling window | `pc top [--seconds 0.3] [--sort cpu\|wake\|io\|rss] [-n 15] [--unit SUBSTR] [--all-users] [--json]` | 0.38 s |
| `pc trace` | eBPF/perf one-liners as verbs: who wakes the CPU, who writes the disk, what a pid waits on. | `pc trace <verb> [pid\|comm] [--seconds N] [-n N] [--by comm\|pid\|unit] [--json]` | 1.75 s |

## Session bus — D-Bus, the compositor, evdev, PipeWire, bluez

| command | description | usage | bench (warm) |
|---|---|---|---|
| `pc audio` | the PipeWire graph as JSON; mutations ledgered. | `pc audio [graph] [--json]` | 0.12 s |
| `pc bt` | bluez adapter, devices, battery and the sidecar-guarded mutations. | `pc bt [status] [--json]` | — |
| `pc dbus` | the session, system and a11y buses as JSON. | `pc dbus list [--user\|--system\|--a11y] [--activatable] [--json]` | 0.03 s |
| `pc input` | the evdev layer: nodes, capabilities, live events, who holds them, uinput injection. | `pc input devices [--json]` | 0.12 s |
| `pc mutter` | the compositor's state as JSON: monitors, workspaces, windows, idle, shell, extensions. Read-only. | `pc mutter [summary] [--json]      one line per section (default)` | 0.12 s |

## Services — systemd units, journal, docker

| command | description | usage | bench (warm) |
|---|---|---|---|
| `pc docker` | compose stacks, health, stats, logs, events, disk use; ledgered restarts. | `pc docker [stacks] [--json]                    compose project -> services (state/health/ports/uptime)` | 0.05 s |
| `pc journal` | structured journalctl queries: errors, per-unit digest, unit tail, grep, boots, size. | `pc journal [errors\|digest\|unit\|grep\|boots\|size] [args]` | 0.06 s |
| `pc units` | systemd units/timers (user+system), per-unit cost, journal tail, guarded restart. | `pc units [list\|timers\|fleet\|show\|cost\|log\|deps\|start\|stop\|restart] [args]` | 0.04 s |

## Safety net — the change ledger, docs, benchmarks, health

| command | description | usage | bench (warm) |
|---|---|---|---|
| `pc bench` | wall, CPU and exec count for every read-only pc subcommand, warm and cold. | `pc bench [--cold] [--runs 3] [--save] [--compare] [--only <sub>…] [--json]` | — |
| `pc doctor` | PASS/FAIL for the whole pc family without opening a window, making a sound or touching the TV. | `pc doctor [--quick] [--json]` | 1.20 s |
| `pc explain` | ranked KB lookup: heading > bold lead > exact quoted token > partial quote/backtick > word > substring. | `pc explain <thing…> [-n 3] [--json] [--files]` | — |
| `pc undo` | the change ledger and its rollbacks. | `pc undo list [-n N] [--json]` | 0.02 s |

## Mutations, the ledger and `pc undo`

Every mutating verb is read-only by default: without `--apply` it prints `would: <before> →
<after>` and exits 0. With `--apply` the change is recorded before and after in
`~/agents/log/changes.jsonl`, and the last line printed is `rollback: pc undo <id>`. `pc undo
list [-n N]` / `pc undo show <id>` read the ledger back; `pc undo <id>|--last [--apply]`
replays the inverse. Budgets (PLAN-PCTOOLS §1 rule 4): <= 0.5 s wall warm for a snapshot
command, <= 0.6 s when a sampling window is intrinsic (`top`, `power`, `io`, `thermal`); `pc
trace` is the declared exception (bpftrace floor 0.4 s + the window, always under `timeout`).

## Guard list (`pclib.sh`, FLEET §5)

A guarded verb exits 3 with the FLEET §5 line, `--apply` or not: `DisplayConfig.Apply*` /
`SetBacklight` (monitor config); `login1` Reboot/PowerOff/Suspend/Hibernate/HybridSleep (power
state); a `systemctl`/D-Bus stop or restart on `ssh*`/`ufw`/`tailscaled` (a second access
path); `org.gnome.Shell.Eval` (arbitrary code in the shell); `SessionManager`
Logout/Reboot/Shutdown; `ScreenSaver.SetActive true` (locking the screen); edits under
`/etc/sudoers*`/`/etc/ssh`/`/etc/ufw`; `tmux kill-*` on the session `claude`;
`dark-eye.service` restart unless `PC_ORCHESTRATOR=1`; fan `pwm1_enable`.
