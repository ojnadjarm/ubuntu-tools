# Phase 4 QA report — 2026-09-05

Independent verification of T20, T21, T23, T24 (OS tuning and maintenance) by the QA agent.
T22 (backups-restic) was skipped by owner decision and is not covered here. Every Success check
was re-run and pushed further: a real docker log-rotation write test, a live `sysctl --system`
parse, login-shell vs user-manager `ulimit`, `udevadm verify`/`test`, an AC/battery simulation of
`power-profile-auto` against a fake sysfs tree, TZ and env bypass attempts on the reboot window,
gate-by-gate refusal injection, a real `smart-alert` push, and a secret-location sweep.
Desktop tests were skipped (another QA agent is on the screen). Nothing was rebooted, suspended,
restarted (NetworkManager/sshd/tailscale/docker) or stopped. Test artifacts removed (see §Cleanup).

## Verdict

| Ticket | Success check | Goal met | Verdict |
|---|---|---|---|
| T20 sysctl/journald/docker limits | PASS | **partly** | **PASS with defects** (D1 HIGH, D4 MEDIUM) |
| T21 power / battery / WiFi | PASS | PASS | **PASS** (D6 minor) |
| T23 updates and reboot policy | PASS | PASS | **PASS with defects** (D2, D3 MEDIUM; D8, D9 minor) |
| T24 disk health (SMART) | PASS (schema caveat) | PASS | **PASS with defects** (D5 MEDIUM, D7 minor) |

## Evidence

### T20 — kernel limits, journald, docker

- **sysctl, live and in the drop-in, all six match.**
  `fs.inotify.max_user_watches=1048576`, `fs.inotify.max_user_instances=1024`, `vm.swappiness=10`,
  `vm.max_map_count=1048576` (kept at the distro value, higher than the 262144 the ticket asked
  for — documented in the file), `net.core.somaxconn=4096`, `kernel.sysrq=1`.
  `sudo sysctl --system` produces **no error/invalid/failed line**; only drop-in files were added,
  no distributed file edited.
- **File limits.** Fresh login shell (`sudo -iu oscar-nadjar bash -lc 'ulimit -Sn; ulimit -Hn'`) →
  **1048576 / 1048576** (pam_limits, from `/etc/security/limits.d/90-agents.conf`).
  System manager: `DefaultLimitNOFILE=1048576`, `DefaultLimitNOFILESoft=1048576` (re-exec took).
  **But** the *user* manager still reports `DefaultLimitNOFILE=524288` / `Soft=1024`, and
  `agent@maintenance.service` shows `LimitNOFILE=524288 / Soft=1024`
  (`systemd-run --user … ulimit -n` → 1024). Agents and their children — the exact Playwright /
  watcher workload the goal names — do **not** get the new limit (**D4**).
- **journald.** `systemd-analyze cat-config systemd/journald.conf` shows the drop-in winning with
  `Storage=persistent`, `SystemMaxUse=1G`, `MaxRetentionSec=1month`; `/var/log/journal` exists
  (17 M on disk), `journalctl --disk-usage` = 16 M, journald restarted 21:15:39. Effective.
- **docker.** `docker info --format '{{.LoggingDriver}} live-restore={{.LiveRestoreEnabled}}'` →
  `json-file live-restore=true`. All **5 containers Up 3 h** (nothing restarted), Moodle answers
  **303** on `http://moodle-lab.tail2ea32e.ts.net:8052/`.
  **The log caps are not in effect (D1).** `systemctl reload docker` (SIGHUP) reloads only a
  subset of `daemon.json`; the journal line `msg="Reloaded configuration" config={…}` at 21:16:08
  contains `"log-driver":"json-file"` and **no `log-opts` at all**. Live proof: a throwaway
  container writing 25 MB produced a **26,772,191-byte un-rotated `*-json.log`** with
  `max-size 20m, max-file 3` configured. The ticket's caveat (running containers keep their old
  log opts) is real, but the actual scope is wider: **no** container gets the cap until dockerd is
  restarted. `~/agents/KB/machine.md:47` documents the wrong remedy ("recreate the 5 existing
  ones") — a newly created container was tested and is equally uncapped.

### T21 — power, battery, WiFi

- `cat /sys/class/power_supply/BAT0/charge_control_end_threshold` → **80**.
- **udev rules valid**: `sudo udevadm verify` → `Success: 2, Fail: 0`.
  `udevadm test --action=add /sys/class/power_supply/BAT0` →
  `99-agents-battery-threshold.rules:2 ATTR{charge_control_end_threshold}="80"` and
  `Written sysfs attributes: charge_control_end_threshold : 80` (test mode, not written).
  `udevadm test --action=change /sys/class/power_supply/AC0` →
  `RUN{program} : /usr/bin/systemctl --no-block start power-profile-auto.service`.
- **WiFi power save off.** `iw dev wlo1 get power_save` → `Power save: off`.
  `NetworkManager --print-config` lists `zz-agents-wifi-powersave-off.conf` **last** among the
  `/etc/NetworkManager/conf.d/` files and resolves `[connection] wifi.powersave=2`, so it beats
  Ubuntu's `default-wifi-powersave-on.conf`. The active profile's own
  `802-11-wireless.powersave` is `default`, i.e. it inherits the global 2. Correct by construction.
- **power-profile-auto.** Unit `enabled` (`WantedBy=multi-user.target`), last run
  `online=1 profile=performance (was balanced)`, exit 0. Script read: `performance` when
  `A[CD]*/online` = 1, `balanced` otherwise. Simulated both branches by running a copy against a
  fake sysfs tree — `online=0 → balanced` (confirmed by `powerprofilesctl get`) and
  `online=1 → performance`; the real service was then started to restore `performance`.
  **Nothing was unplugged.** `powerprofilesctl get` = `performance`, `AC0/online` = 1.
- **No auto-revert leftovers.** `systemctl list-timers --all | grep -iE 'run-|revert'` → empty;
  0 transient `run-r*` units. Only docker/snapd `run-*.mount` units, unrelated.
- **Tailscale intact.** `tailscale status` lists `moodle-lab` and peer `oscar`;
  `tailscale ping oscar` → `pong from oscar (100.68.188.71) via 192.168.1.14:41641 in 7 ms`.
- Runbook `travel.md` matches reality (rule paths, `sudo iw … set power_save off` live fix,
  `systemctl start power-profile-auto.service` as the manual force, rollback steps).
- Gap: ticket step 2's `connection.autoconnect-priority 10` was never applied (**D6**).

### T23 — updates and the reboot policy

- **apt policy effective.** `apt-config dump` resolves `Unattended-Upgrade::Allowed-Origins` to
  exactly the three security pockets (`-security`, ESMApps, ESM) — the `#clear` in
  `52-agents-unattended` removed the `-updates` origin. `Automatic-Reboot "false"`,
  `Automatic-Reboot-WithUsers "false"`, `Remove-Unused-Dependencies "true"`, `Mail ""`.
- `sudo unattended-upgrades --dry-run` → **exit 0, no output**; with `--debug` it shows it
  *adjusting candidates away from* `resolute-updates` back to the allowed origin and ends
  `No packages found that can be upgraded unattended and no pending auto-removals`. Security-only
  is genuinely enforced, not just declared.
- `needrestart` is list-only: `/etc/needrestart/conf.d/50-agents.conf` → `$nrconf{restart}='l'`,
  `kernelhints=0`. Snap `refresh.timer` = `04:00-05:00`.
- **GRUB.** `GRUB_TIMEOUT_STYLE=hidden`, `GRUB_TIMEOUT=2`, `GRUB_RECORDFAIL_TIMEOUT=5`.
  `sudo grub-mkconfig -o /dev/null` exits 0 (only the usual os-prober warning). Nothing written.
- **maintenance-run.**
  - `--dry-run` → exit **0** (`reboot required: no`), every mutating step printed as `would run:`.
  - `--dry-run --assume-reboot` → `REBOOT REFUSED: time-window(now 21h, allowed 4-5h
    Europe/Madrid)`, exit **3**. No push is sent in dry-run (line 78 is guarded).
  - **TZ cannot bypass the window**: `TZ=Pacific/Auckland maintenance-run --dry-run
    --assume-reboot` still refuses with `now 21h` — the script uses an inline
    `TZ=Europe/Madrid date +%-H`, which overrides the inherited TZ. `faketime` is not installed.
  - **Env can bypass it (D2)**: `MAINT_WINDOW_START=0 MAINT_WINDOW_END=24 … --assume-reboot`
    → `REBOOT ALLOWED: all gates passed`, exit **4**.
  - **Health gates refuse correctly.** With the window forced open and the three remaining gate
    commands replaced by failures in a copy of the script:
    `REBOOT REFUSED: pc-status-check; boot-check; agents-active(agent@qa-fake.service)`, exit 3 —
    the gates compose and every reason is named. Live, all four gates currently pass.
  - **Never reboots in dry-run**: `sudo shutdown -r` appears once, at line 89, after the
    `[ "$dry" = 1 ] && … exit 4` at lines 83–86. Verified by reading; no shutdown was ever
    scheduled (`systemctl list-jobs` / no `shutdown` scheduled during any QA run).
  - Exit codes match `reboot.md`: 0 ok, 3 refused, 4 scheduled, 1 error, 2 bad option.
- **Timer and roster.** `agent@maintenance.timer` **enabled**, drop-in
  `OnCalendar=Sun *-*-* 04:00`, next `Sun 2026-09-06 04:00 CEST`. `agents-status` shows
  `maintenance enabled Sun *-*-* 04:00`. `~/CLAUDE.md` has exactly one `maintenance` row
  (Sun 04:00, "push before a reboot, or when one is refused"); **no roster row is duplicated**
  (`sentinel-check`, `sentinel-digest`, `moodle-keeper`, `moodle-keep-weekly`, `maintenance`,
  `hello` — 1 each).
- `~/agents/maintenance/BRIEF.md` forbids the agent from rebooting by hand and matches the exit
  codes the script produces.

### T24 — SMART and battery health

- `systemctl is-active smartd` → **active**. `/etc/smartd.conf` is a single line
  `DEVICESCAN -H -l error -l selftest -m root -M exec /usr/local/sbin/smart-alert`.
- `sudo smartctl -H /dev/nvme0` → `PASSED`; `-A` → Available Spare 100 % (threshold 10 %),
  Percentage Used 5 %, Media and Data Integrity Errors 0.
- **`smart-alert`.** Runs as root, mode 0755 root:root. Real end-to-end test:
  `sudo env SMARTD_FAILTYPE=QA-TEST SMARTD_DEVICE=/dev/nvme0 SMARTD_MESSAGE="…" smart-alert`
  → exit 0, one `ok urgent` row in `/var/log/smart-alert.log`, push delivered.
  **The topic never appears in its output or its log** (checked by grepping the output for the
  literal topic value: 0 matches). Without a readable env file `notify-owner` prints
  `cannot read <path>` and **exits 1**, and `smart-alert`'s last command is that call, so the
  non-zero status propagates. (`NTFY_ENV_FILE` cannot be injected into `smart-alert` — it sets
  the variable itself on the `notify-owner` invocation, which is the safer design.)
- `/etc/agents/ntfy.env` is **0600 root:root**; `~/agents/secrets/ntfy.env` is **0600
  oscar-nadjar**; both hold the same 40-char topic. Neither was read or printed.
- **`pc status`.** `--check` → `OK — all checks passed`, exit 0. Text output shows
  `battery_health 72% of design, 167 cycles`, `battery_limit 80%`, `profile performance`, and a
  `DISK` section. `--json` carries `sections.disk.smart = PASSED/OK`,
  `sections.disk.percent_used = 5%`, `sections.disk.available_spare = 100%`,
  `sections.disk.media_errors = 0`, `sections.power.battery_health = 72% of design, 167 cycles`,
  `sections.power.battery_limit = 80%`. Cross-checked against sysfs
  (`energy_full 50585000 / design 70032000 = 72 %`, `cycle_count 167`) and against
  `smartctl -H -A` — every value matches. The ticket's literal snippet `d['disk']['smart']`
  raises `KeyError` because T05's schema nests everything under `sections` (**D7**, docs only).
- **Threshold logic** (read at `pc-status:97` and `:179-184`): FAIL when SMART != PASSED, when
  percent used > 90, or when spare < 20 — as specified. It also FAILs when the values are
  unavailable (`-1` / `n/a`), which is the wrong default (**D5**).
- **sentinel green path still 0-cost.** `sentinel-check` → exit 0 in **1.52 s**, `state/last-ok`
  refreshed, `sentinel/logs/index.tsv` unchanged at 3 lines (**no `claude -p` run, $0**).
  `sudo -n smartctl` works from inside a user-manager unit (tested with `systemd-run --user`), so
  the sentinel's own runs get real SMART data. `pc status --brief` steady-state 0.36–0.50 s
  (a 5.1 s first call was a cold sudo timestamp, not a regression; `smartctl` itself is 28 ms).

### Cross-cutting

- **etckeeper clean**: `etckeeper vcs status --short` → empty. Commits `10b2ec5` (T20),
  `074bf2e` (T21), `7bd132a` (T23), `f1e3052` (T24) plus the automatic pre/post-apt commits.
  All 14 new or changed `/etc` files are tracked: the four T20 drop-ins, `docker/daemon.json`,
  both udev rules, the NM drop-in, `power-profile-auto.service`, `52-agents-unattended`,
  `needrestart/conf.d/50-agents.conf`, `smartd.conf`, `default/grub`, `agents/ntfy.env`.
- **No failed units**: `systemctl --failed` and `systemctl --user --failed` both report
  `0 loaded units listed`.
- `systemd-analyze verify /etc/systemd/system/power-profile-auto.service` → clean, rc 0.
  `systemd-analyze --user verify agent@.service` → clean (only a pre-existing warning about
  Ubuntu's `spice-vdagent.service`).
- **`journalctl -p err -b --since "2 hours ago"`**: no error attributable to T20/T21/T23/T24.
  The only recurring line is the pre-existing
  `agent@sentinel.timer: Timer unit lacks value setting. Refusing.` from Phase 3 (**D11**), plus
  one `sshd-session: send_error: write: Broken pipe`.
- **ntfy topic locations**: two plaintext files, both 0600 (above). A third, compressed copy
  exists as a git blob inside `/etc/.git` (0700 root) because etckeeper tracks
  `agents/ntfy.env`; `/etc/.etckeeper` records `maybe chmod 0600 'agents/ntfy.env'`, so a restore
  keeps the mode. Same trust boundary as `/etc/shadow`, which etckeeper also tracks
  (**D10**, informational).
- Moodle stack untouched throughout: 5 containers up before and after, site returns 303.

## Defects

| # | Sev | Ticket | Defect |
|---|---|---|---|
| D1 | **HIGH** | T20 | Docker log caps are not in effect |
| D2 | MEDIUM | T23 | Reboot window bypassable through the environment |
| D3 | MEDIUM | T23 | Docker packages stay held if `maintenance-run` is killed |
| D4 | MEDIUM | T20 | User-manager services (all agents) still get `nofile` 1024/524288 |
| D5 | MEDIUM | T24 | `pc status --check` FAILs when SMART data is merely unavailable |
| D6 | LOW | T21 | `connection.autoconnect-priority` never set on the home WiFi |
| D7 | LOW | T24 | Ticket Success-check snippet does not match the `pc status --json` schema |
| D8 | LOW | T23 | Dry-run's "pending upgrades" count ignores the docker hold |
| D9 | LOW | T23 | `--assume-reboot` without `--dry-run` can trigger a real reboot |
| D10 | INFO | T24 | The ntfy topic exists in three places, not two |
| D11 | LOW | T15/T17 | Pre-existing `agent@sentinel.timer` error every few minutes |

**D1 — HIGH — T20 — docker log caps not in effect.**
*Repro:* `docker run -d --name x nginx:alpine sh -c 'i=0; while [ $i -lt 25000 ]; do head -c 1000
/dev/zero | tr "\0" x; echo; i=$((i+1)); done'` then
`sudo ls -l /var/lib/docker/containers/$(docker inspect -f '{{.Id}}' x)/*-json.log` → a single
26.7 MB file, no `.1` rotation, with `max-size 20m / max-file 3` in `daemon.json`. The journal's
`Reloaded configuration` line from 21:16:08 lists no `log-opts`: `systemctl reload docker` (SIGHUP)
does not apply `log-driver`/`log-opts`, only `live-restore` and friends. The ticket's Success
check passes because `docker info` reports the *default* driver, which was already `json-file`.
*Impact:* the "logs can never fill the disk" half of the goal is unmet for every container,
old and new — the disk-full risk in PLAN §6 is still open.
*Fix:* `sudo systemctl restart docker` in the next maintenance window — safe now that
`live-restore=true` is live, so the 5 containers keep running — then re-run the repro and confirm
a `.1` file appears. Correct `~/agents/KB/machine.md:47`, which claims the caps apply to
containers created after the change; they do not.

**D2 — MEDIUM — T23 — reboot window bypassable through the environment.**
*Repro:* `MAINT_WINDOW_START=0 MAINT_WINDOW_END=24 ~/agents/bin/maintenance-run --dry-run
--assume-reboot` → `REBOOT ALLOWED: all gates passed`, exit 4. Without `--dry-run`, inside a
passing health state, that reboots the machine at any hour. `TZ=` is correctly immune.
*Impact:* the owner's PLAN §7 Q4 answer ("04:00–05:00 only") is enforced by an env var any agent
in the fleet can set — a surprise daytime reboot is one variable away.
*Fix:* hardcode `WINDOW_START=4 / WINDOW_END=5` (lines 8–9), or accept the overrides only when a
root-owned `/etc/agents/maintenance-window` says so. Owning ticket: T23.

**D3 — MEDIUM — T23 — docker packages stay held if the run is killed.**
*Repro:* read `maintenance-run` lines 35–49: `sudo apt-mark hold $held` at line 37, the matching
`unhold` at line 49, no `trap`. `agent-run` enforces `TIMEOUT` with `timeout`, which kills the
script; a `dpkg` lock wait or a manual Ctrl-C does the same.
*Impact:* `docker.io docker-buildx docker-compose-v2 containerd` stay held indefinitely and
silently stop receiving security updates — the opposite of the ticket's goal. Nothing in the
fleet checks `apt-mark showhold` (currently empty, verified).
*Fix:* `trap '[ -n "${held:-}" ] && sudo apt-mark unhold $held >/dev/null 2>&1' EXIT INT TERM`
right after the hold. Owning ticket: T23.

**D4 — MEDIUM — T20 — user-manager services still get nofile 1024/524288.**
*Repro:* `systemctl --user show -p DefaultLimitNOFILE -p DefaultLimitNOFILESoft` → `524288` /
`1024`; `systemctl --user show agent@maintenance.service -p LimitNOFILE -p LimitNOFILESoft` →
same; `systemd-run --user --pty bash -c 'ulimit -Sn'` → 1024. Login shells are fine (1048576).
*Impact:* `/etc/systemd/system.conf.d/limits.conf` governs the system manager only. Every agent
(`agent@*`, sentinel) and everything they spawn — Playwright, grunt watchers, node — runs with
the old limits, which is precisely the workload the goal names. `/etc/systemd/user.conf.d/` does
not exist.
*Fix:* create `/etc/systemd/user.conf.d/limits.conf` with `[Manager]
DefaultLimitNOFILE=1048576`, then `systemctl --user daemon-reexec` (the running user manager
keeps its old defaults otherwise). A `LimitNOFILE=1048576` in `agent@.service` is the narrower
alternative. Owning ticket: T20.

**D5 — MEDIUM — T24 — `pc status --check` FAILs on missing SMART data.**
*Repro:* `pc-status:38` runs `timeout 5 sudo -n smartctl …`; on timeout or a missing binary
`s_health` defaults to `n/a`, and `pc-status:179` sets `st=FAIL` for anything that is not
`PASSED`. `disk.smart FAIL` makes `pc status --check` non-zero.
*Impact:* a 5 s `smartctl` timeout, a `sudo` hiccup or `apt remove smartmontools` turns the whole
health check red. The sentinel then escalates to a paid `claude -p` repair run, and
`maintenance-run`'s `pc status --check` gate refuses an otherwise valid reboot. A monitoring
gap must not read as a hardware failure.
*Fix:* distinguish the two: `st=FAIL` only when `s_health` is a real non-`PASSED` verdict; use
state `-` (or a `WARN` that does not fail `--check`) when the value is `n/a` / `-1`. Same for
`percent_used` and `available_spare`, which already FAIL on `-1`. Owning ticket: T24.

**D6 — LOW — T21 — autoconnect priority not set.**
*Repro:* `nmcli -g connection.autoconnect-priority con show "Livebox6-47FF 3"` → `0`; the same for
the three other duplicate `Livebox6-47FF*` profiles. Ticket step 2 asked for `10`.
*Impact:* four profiles exist for one SSID; after a network change NetworkManager may activate a
different one. The powersave setting is global so it survives either way, but any per-profile
option would not.
*Fix:* `nmcli con mod "Livebox6-47FF 3" connection.autoconnect-priority 10` (and consider deleting
the three stale duplicates). Owning ticket: T21.

**D7 — LOW — T24 — ticket Success-check snippet does not match the JSON schema.**
*Repro:* `pc status --json | python3 -c "…print(d['disk']['smart'])"` → `KeyError: 'disk'`; the
real paths are `sections.disk.smart.value` and `sections.power.battery_health.value`.
*Impact:* documentation only — all values are present and correct.
*Fix:* update the snippet in `tickets/T24-disk-health-smart.md` to the `sections.*` paths.

**D8 — LOW — T23 — dry-run upgrade count ignores the hold.**
*Repro:* `maintenance-run --dry-run` prints `would run: sudo apt-mark hold …` (the hold is only
simulated) and then computes `pending upgrades: 3` from an unheld `apt-get -s full-upgrade`.
*Impact:* the dry-run number can exceed what the real run installs. Cosmetic.
*Fix:* pass `-o` exclusions, or subtract the held packages from the count.

**D9 — LOW — T23 — `--assume-reboot` is a real-reboot footgun.**
*Repro:* `maintenance-run --assume-reboot` (no `--dry-run`) inside the window with green gates
would push and run `sudo shutdown -r +5` on a fabricated reason (`reason: simulated`).
*Impact:* a test-only flag can reboot the machine. It is documented as "test only" in a comment.
*Fix:* make `--assume-reboot` imply `dry=1`, or refuse to combine it with a real run.

**D10 — INFO — T24 — the ntfy topic lives in three places, not two.**
`/etc/agents/ntfy.env` (0600 root), `~/agents/secrets/ntfy.env` (0600 oscar) and a git blob in
`/etc/.git` (0700 root, `git show HEAD:agents/ntfy.env` returns it). This is etckeeper's normal
model — it tracks `/etc/shadow` the same way — and `/etc/.etckeeper` records `maybe chmod 0600`
so a restore preserves the mode. No action required; only stop describing it as "exactly two".

**D11 — LOW — T15/T17 (pre-existing) — `agent@sentinel.timer` error spam.**
`journalctl -p err -b` carries `agent@sentinel.timer: Timer unit lacks value setting. Refusing.`
every few minutes (the `agent@sentinel` template has no schedule drop-in; `agents-status` shows
it disabled). Not caused by Phase 4, but it pollutes the error journal that the maintenance agent
and the daily digest read. Fix: give `agent@sentinel` an `OnCalendar=` drop-in or mask the timer.

## Not testable here

- **The real reboot.** T23's whole point — that the machine comes back with docker, the desktop
  session, linger and the tmux `claude` session intact — can only be proved by an actual reboot,
  which the QA brief forbids. `maintenance-run` was verified up to and including the
  `REBOOT ALLOWED` decision and the exact commands it would run; `grub-mkconfig -o /dev/null`
  proves the GRUB config still generates. Status: **reboot test pending owner**.
- **The udev rules firing on a real AC transition.** `udevadm verify` and `udevadm test` prove the
  rules match and what they would do, and the profile switch was exercised against a fake sysfs
  tree, but nothing was unplugged. The 80 % cap surviving a reboot likewise depends on the
  untested reboot.
- **The 80 % charge cap actually stopping a charge** — the battery sits at 100 % from before the
  cap was applied; the cap only takes effect on the next discharge/charge cycle.
- **`smartd` raising a real alert.** The `-M exec` handler was invoked directly and delivered, but
  no genuine SMART failure can be provoked on a healthy drive. `smartd -q onecheck` was not run,
  to avoid a second push.
- **WiFi power save surviving a reconnect.** Verified by configuration resolution
  (`NetworkManager --print-config`) rather than by dropping the link, which the brief forbids.
- **Desktop-side effects** of any of these tickets (another QA agent held the screen).

## Cleanup

- Removed: the two throwaway containers `qa-t20-logtest` and `qa-t20-rot` (and their log files
  with them), the fake sysfs tree and patched `power-profile-auto` copy, the patched
  `maintenance-run` gate-test copy, and the two QA rows from `/var/log/smart-alert.log`.
- Restored: `powerprofilesctl` back to `performance` via the real
  `power-profile-auto.service`.
- Left in place deliberately: `~/agents/maintenance/state/last-summary.txt` now holds a QA
  dry-run instead of a real run (the script truncates it every run, so Sunday overwrites it), and
  the empty `state/.lock` flock file. `apt-mark showhold` is empty — no hold leaked.
- One **urgent ntfy push** was sent to the owner during the `smart-alert` test
  (`QA-TEST on /dev/nvme0: QA phase4 test alert - ignore`).
- Nothing was committed or pushed; nothing was rebooted, suspended or restarted; the Moodle stack
  ran untouched (5 containers up, 303 on the site) for the whole session.
