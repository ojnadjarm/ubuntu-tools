# Phase 5 QA report — 2026-09-05

Independent verification of **T26** (netdata) and a **re-check of the T28 fixes** (defects D10–D19
from `qa/t28.md`) by the QA agent. T25 and T27 were not implemented and are recorded as
not executed. Every T26 Success-check line was re-run and pushed further: binding probed from the
LAN address, the docker bridge and a container, the alarm pipeline driven end to end through
netdata's own `alarm-notify.sh` (exactly one push), a 12.9-minute footprint measurement, and the
systemd drop-in put through `systemd-analyze verify`. Desktop: 1366x768, agent mode, QA the only
agent on the screen. Nothing was rebooted, restarted, logged out or committed; the Moodle stack ran
untouched (5 containers Up 3 h) throughout.

## Verdict

| Ticket | Success check | Goal met | Verdict |
|---|---|---|---|
| T26 netdata | PASS | PASS | **PASS with defects** (D20 MEDIUM, D21 LOW, D22 INFO) |
| T28 re-check (D10–D19) | PASS — 9 of 10 fixed | partly (latency target lost) | **PASS with defects** (D23 HIGH, D24 HIGH) |
| T25 firewall/SSH hardening | — | — | **not executed** (never implemented) |
| T27 tailscale serve HTTPS | — | — | **not executed** (blocked on tailnet admin toggles) |

## Evidence — T26

- **Service.** `systemctl is-active netdata` → `active`, `is-enabled` → `enabled`, `NRestarts=0`,
  up since 21:43:44. `journalctl -p err -u netdata --since "1 hour ago"` → **no entries**; `-p
  warning` likewise empty.
- **Binding — tailnet only.** `sudo ss -ltnp | grep 19999` → exactly two sockets,
  `127.0.0.1:19999` and `100.99.234.53:19999`. Never `0.0.0.0`. The host also holds
  `192.168.1.20` (wlo1), `172.17.0.1` (docker0) and two compose bridges — **none** is bound.
  - `curl --max-time 3 http://192.168.1.20:19999` → **exit 7** (connection refused), as the ticket
    requires. `http://172.17.0.1:19999` → exit 7 too.
  - **From inside a container** (`docker run --rm curlimages/curl … http://100.99.234.53:19999`)
    → `code=000`, no connection. A compromised container cannot reach the dashboard.
  - `http://moodle-lab.tail2ea32e.ts.net:19999/` → **200**; `http://127.0.0.1:19999/` → 200.
  - `/netdata.conf` over the tailnet → **451** (`allow netdata.conf from = localhost` holds).
- **API returns data.** `/api/v1/info` → `v2.11.0`.
  `/api/v1/data?chart=system.cpu&after=-60&points=1` → a real row
  (`[1788637860,0,0,0,0.0094,0,9.00,0.83,0.02,0.12]`). `/api/v1/charts` → **2674 charts**.
- **Per-container cgroup charts.** 179 `cgroup_*` charts covering all five running containers:
  `moodle-shared-mailhog-1`, `moodle-shared-proxy-1`, `moodle-shared-selenium-1`, `moodle52-app-1`,
  `moodle52-db-1`. `cgroups.plugin` is in the live collector list.
- **Cloud and telemetry off.** `/var/lib/netdata/cloud.d/cloud.conf` = `[global] enabled = no`;
  `/etc/netdata/.opt-out-from-anonymous-statistics` present; `[registry] enabled = no` in the
  running config; `agent-claimed=false`, `claimed-id=null`, ACLK `online=false`,
  `reconnect-count=0`, `received-app-layer-msgs=0`. **`sudo ss -tnp | grep netdata` → no outbound
  connection at all** over the whole session, and the journal contains no `aclk`/`cloud`/`claim`
  line. (`/api/v1/info` still reports `cloud-enabled: true` — a build capability, not a live
  connection; see D22.)
- **dbengine caps in config.** `/etc/netdata/netdata.conf` `[db]`: tier 0 `512MiB` / `7d`,
  tier 1 `256MiB`, tier 2 `256MiB`, page cache `32MiB` (≈1 GiB as the ticket asked).
  `multidb-disk-quota: 512`. On disk today: `/var/cache/netdata` = **22 M**
  (dbengine 2.0 M, tier1 1.2 M, tier2 12 K). `[ml] enabled = no`; `ebpf`, `ebpf-go`, `perf`,
  `slabinfo` disabled.
- **Alert pipeline, driven end to end — exactly one push, labelled QA.**
  Both runs were executed **as the `netdata` user**, i.e. through the same privilege path the
  daemon uses.
  - **WARNING is filtered.** `sudo -u netdata alarm-notify.sh sysadmin <host> … WARNING CLEAR …`
    → exit 0, **spool stayed empty**, no push. Matches
    `DEFAULT_RECIPIENT_CUSTOM="owner|critical"`.
  - **CRITICAL goes all the way.** Same call with `CRITICAL WARNING` →
    `msg="[ALERT NOTIFICATION]: sent custom notification to 'owner'"`; the spool file appeared and
    was consumed within 4 s; `netdata-alert-drain.service` ran as root
    (`code=exited, status=0/SUCCESS`, triggered by `netdata-alert-drain.path`); spool back to 0;
    `/var/log/netdata-alert.log` gained
    `ok urgent … is critical: QA critical probe = 99% (system.cpu) — QA phase5 test alert - ignore`.
    **One** ntfy push was sent to the owner.
  - **Live corroboration of the filter:** two genuine alarms sit in **WARNING** right now
    (`app.update-notifier_fds_open_limit` 99.9 %, `app.desktop_fds_open_limit` 100 % — netdata
    independently rediscovering phase-4 **D4**) and have produced **zero** pushes.
  - **Permissions are right by construction:** `/var/spool/netdata-alerts` is `drwx-wx--- root:netdata`
    — the daemon can drop a file but cannot read the queue back; QA's own `ls` as `oscar-nadjar`
    was denied. 217 health alarms are loaded from the stock set (no `/etc/netdata/health.d`
    overrides), statuses `CLEAR / WARNING / UNDEFINED / UNINITIALIZED`, no CRITICAL.
  - `netdata-alert-drain.path` → **active (waiting)**, `enabled`, `Triggers:
    netdata-alert-drain.service`.
- **Tailscale ordering drop-in valid.** `/etc/systemd/system/netdata.service.d/10-tailscale.conf`
  adds `After=/Wants=tailscaled.service`, an `ExecStartPre` that polls up to 60 s for
  `100.99.234.53` on `tailscale0`, and `Restart=always`.
  `systemd-analyze verify netdata.service` → **exit 0, no output**.
- **`pc status --check` → `OK — all checks passed`, exit 0**; the `SERVICES` block lists
  `netdata active [OK]`. `~/agents/KB/machine.md` carries the URL, the API example, the binding and
  the alarm path; `~/agents/KB/quirks.md` documents the repo, the drop-in and the spool design —
  all four claims verified against reality.
- **etckeeper tree clean:** `sudo git -C /etc status --porcelain` → **0 lines**; HEAD is
  `d1b6988 T26: netdata bound to the tailnet IP, cloud off, critical alarms to notify-owner`.
- **Footprint, 12.9 minutes of steady running (idle desktop, 5 containers up):**
  **5.03 % of one core** sustained (`CPUUsageNSec` delta over 775 s), `MemoryCurrent` **181 MiB**
  (peak 185 MiB), main process RSS 96 MiB, **319 MiB summed RSS** across the 14 netdata processes
  (0.8 % of 38 GiB). See **D20**.

## Evidence — T28 re-check (D10–D19)

| Defect | Status | Evidence |
|---|---|---|
| **D10** popover crashes `pc see <SEL>` | **FIXED** | With the Text Editor Main Menu popover open (`pc win list --all` shows `1570913437 None 219x522+720+240`), `pc see`, `pc see TextEditor` and `pc see gnome-text-editor` all **exit 0**, no traceback. `--json` reports the popup in a dedicated `popup` key with `wm_class: null, title: null` — the null case is now modelled, not crashed on. Same for the calculator `Basic` popover. |
| **D11** Chrome coordinates off by the frame origin | **FIXED** | `pc see` → `link "Learn more" (326,325 83x20)` → centre **367,335**; `pc find "Learn more"` (OCR) → **368 334**. Delta ≤ 1 px (was +68,+31). `pc a11y-click "Learn more" --app "Google Chrome"` → exit 0 and the window title changed `Example Domain` → **`Example Domains - Google Chrome`**, verified with `pc see`, not a screenshot. Chrome closed afterwards (`killall chrome`). |
| **D12** `text ""` — Text interface never read | **FIXED** | Scratch file opened in Text Editor, `pc click` into the view, `pc type "QA phase five alpha"` → `pc see` → `text "placeholderQA phase five alpha" (466,286 500x314)`. Real document text, exactly what the skill advertises. |
| **D13** popup makes `pc see` say "no accessible tree" | **FIXED** (cause a) | With the popover open, `pc see` reports `focus:` = the **real** Text Editor window and `ui: gnome-text-editor 32 nodes`, and the popover's own controls appear inline (`radio button "Follow system style"`, `"Light style"`, `"Dark style"`, `button "Zoom out" / "100%" / "Zoom in"`). The bogus message is gone; `pc win list` filters the transient row, `--all` shows it. Cause (b) survives as a toolkit limit: `pc tree` still prints ten `menu item ""` rows with empty names. |
| **D14** `--json` ignores `--max-bytes`, 3x the text | **FIXED** | Window dicts are now projected to `{id, wm_class, title, x, y, width, height, focus, minimized}` and `--max-bytes` applies to JSON (`ui_more` key added). Two windows open: text 1550 B, json 3994 B (was ~3x for 15 keys/window). `pc see --json --max-bytes 800` → **951 B**, still valid JSON. Under 900 B once titles are normal length: the same call selecting one window → **851 B**. The 951 B here is the documented floor, inflated by an 85-character scratchpad path repeated in three fields. |
| **D15** bogus full-screen change after a `--changed-only` crop | **FIXED** | The crop now goes to a separate `<out>.crop.png` and `<out>` stays full-frame. Sequence on a static screen: baseline → `unchanged` → `unchanged` → `pc win move` → `changed bbox=184,34,733,734 crop=…h.png.crop.png` → **`unchanged`** → **`unchanged`**. Exactly the pattern the brief asked for. |
| **D16** dead `ACCESSIBILITY_ENABLED` config | **FIXED** | `~/.config/environment.d/50-agents-a11y.conf` **no longer exists**; `grep ACCESSIBILITY_ENABLED ~/agents/bin/pc-open` → no hits. The mechanism that works is in place: `~/.local/share/applications/google-chrome.desktop` runs `--force-renderer-accessibility` in all three `Exec` lines. |
| **D17** `pc click 0 0` and `pc scroll --at` unvalidated | **FIXED** | `pc click 0 0` → `pc: 0,0 is the overview hot corner, use 1,1`, **exit 2** (overview not opened). `pc scroll up 1 --at 5000 5000` → outside-the-screen error, **exit 2**; `--at 0 0` → hot-corner error, exit 2; `--at abc def` → integer error, exit 2. `pc click 5000 5000` → exit 2. The shared `pc_xy` helper in `env.sh` is now used by click, move, drag and scroll alike. |
| **D18 / D19** INFO notes | n/a | Documentation-only; not re-tested. |
| **`pc selftest`** | **PASS** | 11 OK lines including `see: ui: lists button "7"`, `tree --find: real screen coordinates for "7" (456 602)`, `click by coordinates + a11y-click: 7+8 = 15`, `find: OCR located "7" at 442 588`. But `real 1m01.7s` against the ticket's 25 s budget — same root cause as **D23**. |
| **`pc see` latency** | **FAIL** | 5 runs, **empty** desktop: 3.93 / 3.97 / 3.95 / 3.90 / 3.95 s. 5 runs with two windows open: 7.35 / 7.39 / 6.54 / 7.42 / 6.61 s. Target is < 1 s; the last QA measured 0.62–0.81 s. Root-caused below (**D23**). |

## Defects

**D20 — MEDIUM — T26 — netdata costs 5 % of a core and 320 MiB, continuously, on a laptop.**
*Repro:* `systemctl show netdata -p CPUUsageNSec` sampled 775 s apart on an idle desktop →
**5.03 % of one core**; `ps -eo rss,args | grep netdata` → **319 MiB** across 14 processes
(`go.d.plugin` 108 MiB, the daemon 96 MiB, `scripts.d.plugin` 20 MiB, three `otel-plugin`
processes 34 MiB, plus `apps.plugin`, `systemd-journal.plugin`, `network-viewer.plugin`,
`nfacct.plugin`, `debugfs.plugin`, `tc-qos-helper.sh`).
*Impact:* the ticket is a "nice" and the machine is a battery-powered laptop with a T21 power
policy; a permanent 5 % core draw is a real cost for a dashboard the owner looks at occasionally,
and it partly defeats the `power-profile-auto` work. RAM is not the problem (0.8 % of 38 GiB).
*Fix:* the config already turns off `ml`, `ebpf`, `perf` and `slabinfo`; go further —
`[plugins] otel = no`, `network-viewer = no`, `nfacct = no`, `slabinfo = no`, `charts.d = no`,
`python.d = no`, and raise `[global] update every = 2` (or 5). Then re-measure the same way.
Owning ticket: T26.

**D21 — LOW — T26 — the drain deletes a spooled alarm even when the push fails.**
*Repro:* read `/usr/local/sbin/netdata-alert-drain` — `notify-owner … ; rm -f "$f"`. The `rm` is
unconditional and `notify-owner`'s exit status is never inspected.
*Impact:* if ntfy is unreachable (no WiFi, service down — exactly when a CRITICAL matters most),
the alarm is silently destroyed. There is no retry and nothing in the journal marks the loss.
Two smaller edges on the same path: `/usr/local/sbin/netdata-alert` has no `mkdir -p`, so if
`/var/spool/netdata-alerts` ever disappears the alarm is lost with a shell error the daemon
ignores; and the spool filename `$(date +%s)-$$` collides if the same PID spools twice in one
second (unlikely — netdata forks per notification).
*Fix:* `if notify-owner …; then rm -f "$f"; else mv "$f" "$f.retry"; fi` (or leave it in place —
the `.path` unit re-triggers while the directory is non-empty) and log the failure. Owning
ticket: T26.

**D22 — INFO — T26 — `/api/v1/info` still advertises `cloud-enabled: true`.**
The cloud *connection* is off and stays off — `agent-claimed=false`, ACLK `online=false`,
`reconnect-count=0`, no outbound socket in 25 minutes of watching, no journal line — but the flag
in `/api/v1/info` reports the compiled-in capability, not the state, and reads alarmingly.
`[cloud] enabled = no` also lives in `/var/lib/netdata/cloud.d/cloud.conf` rather than in
`/etc/netdata/netdata.conf` where the ticket put it; that is netdata's real location, so it works,
but `/var/lib` is outside etckeeper — a reinstall would not restore it. Worth one line in
`quirks.md` and, optionally, a copy of the setting under `/etc`. No action otherwise.

**D23 — HIGH — T28a — one unresponsive AT-SPI application stalls every `pc see` by ~3 s per
enumeration; `pc see` is now 4–7 s and `pc selftest` 62 s.**
*Repro (deterministic today):*
```
pc see            # 3.9 s with no windows, 6.5-7.4 s with two
python3 -c "…Atspi.get_desktop(0); time each get_child_at_index(i)…"
  gnome-shell 0.02s | update-notifier 0.00s | evolution-alarm-notify 0.00s
  ibus-extension-gtk3 0.00s | xdg-desktop-portal-gtk 2.97s  <-- here | gjs 0.00s
```
The stalling entry is **`xdg-desktop-portal-gtk` (PID 3293)**: it is registered on the a11y bus,
alive, and does not answer — `get_role_name()` raises `atspi_error: timeout from dbind`. Every
`Atspi.get_desktop(0)` walk pays the full `Atspi.set_timeout(800, 3000)` budget on it, and
`pc see` walks the desktop more than once per run (`windows()`/`app_for_window()` and again in
`notifications()`, whose `apps("gnome-shell")` builds the *whole* child list before breaking on
the first match).
*Impact:* T28a's headline number — "one text command, under a second" — is gone; the whole "text
before pixels" economics in PLAN §97 assumed 0.6 s. `pc selftest` blew its own 25 s budget
(**61.7 s**). And the failure mode is generic: any app that stops answering AT-SPI, at any time,
silently multiplies every agent's perception cost. Nothing in the tooling reports it.
*Fix:* (a) in `apps()`, return as soon as `sub` matches so the dead entry after the match is never
queried, and cache the desktop child list for the life of the process; (b) remember the desktop
index of an app whose query timed out and skip it for the rest of the run; (c) drop
`Atspi.set_timeout` to something like `(300, 1500)` so a stall costs 0.3 s, not 3 s; (d) have
`pc see` print a one-line `warn: <name> not answering AT-SPI` so the cost is visible instead of
mysterious. Owning ticket: T28a.

**D24 — HIGH — T28a — a modal dialog is invisible to `pc see` and `pc win list --all`, and `pc see`
serves stale text while it is up; every keyboard and pointer command silently no-ops.**
*Repro (hit accidentally, then confirmed against a screenshot):* with a modified document open in
Text Editor, `pc key ctrl+w` raises GTK's **"Save Changes?"** modal. From then on:
```
pc key ctrl+s      -> exit 0, nothing happens
pc key ctrl+z x3   -> exit 0, nothing happens
pc type "ZZ"       -> exit 0, nothing happens
pc win list --all  -> one row, the Text Editor. No dialog.
pc see             -> focus: the Text Editor; ui: gnome-text-editor 34 nodes;
                      text "placeholderQA phase five alpha"   <-- the pre-dialog buffer
pc shot            -> a full-screen "Save Changes?" dialog with Cancel / Discard / Save
```
The dialog is a GTK4 in-window modal, so it is neither a separate window (nothing for
`window-calls` to report, even with `--all`) nor part of the branch `pc see` walks — and the text
it does report is the buffer *behind* the dialog.
*Impact:* worse than D10, which at least crashed loudly. Here an agent is told the screen is
normal, issues input that is swallowed, reads back an unchanged digest, and has no signal
whatsoever except a screenshot — the exact pixel round trip T28 exists to avoid. Any GTK
save/overwrite/confirm prompt puts an agent into this state. QA lost three commands to it before
taking a screenshot.
*Fix:* in `a11y_tree.py`, walk the focused app for a node with role `dialog`/`alert` (or the
`MODAL` state) and, when one is found, make it the `ui:` subtree and print a `modal:` line naming
it and its buttons — a modal has exactly the interactive rows an agent needs. Add the same check
to `pc key`/`pc type`'s focus guard so input into a blocked window fails loudly instead of
exiting 0. Owning ticket: T28a.

## Not executed

- **T25 firewall-ssh-hardening** — never implemented. `sudo ufw status` → **`Status: inactive`**;
  no default-deny, no tailnet/LAN allow rules, and SSH password authentication was not touched.
  Note that T26's Success check offered "`bind to = *` + ufw if T25 is done" as a fallback — the
  implementation correctly took the bind-to-tailnet-IP path instead, so nothing in T26 depends on
  T25. Phase 5 leaves the LAN-facing posture exactly as phase 0 left it.
- **T27 tailscale-serve-https** — blocked on tailnet admin toggles (HTTPS certificates / MagicDNS)
  that the agent cannot flip. Not started, nothing to verify. The Moodle env still answers plain
  HTTP on `http://moodle-lab.tail2ea32e.ts.net:8052/`.

## Not testable here

- **A real netdata CRITICAL from a real condition.** No genuine critical exists on a healthy
  machine; the pipeline was driven through netdata's own `alarm-notify.sh` with the daemon's
  privileges, which exercises `health_alarm_notify.conf`, `custom_sender`, the spool, the `.path`
  unit, the root drain and `notify-owner` — everything except the health engine's decision to
  call it. `alarm-notify.sh test` was deliberately **not** used: it fires WARNING + CRITICAL +
  CLEAR and would have sent more than the one push the brief allows.
- **Reaching the dashboard from the owner's phone.** Verified from the machine over the Tailscale
  name (200) and proved unreachable from LAN, docker0 and a container; the phone itself is not
  under QA's control.
- **The 60 s `ExecStartPre` wait for the tailnet address actually firing** — that needs a boot or a
  `tailscaled` restart, both forbidden. `systemd-analyze verify` passes and the loop was read.
- **`pc see` latency after the stalled portal process recovers.** D23's measurements are what an
  agent gets on this machine today; the tooling change is what makes them stable.

## Cleanup

- Desktop left empty: `pc win list --all` → no rows, `pc mode` → `agent`, `pc status --check` →
  `OK — all checks passed` (exit 0).
- Chrome closed with `killall chrome` (never `pkill -f`). The Text Editor closed through its own
  **Discard** button after `ctrl+w` raised the save prompt; only QA's scratch file was listed as
  modified, and the owner's four session tabs (`authorized_keys`, `docker-compose.yml`,
  `install-5.2.log`, `scratch.txt`) were unmodified and are unchanged on disk — Text Editor
  restores that session on next launch. QA's `pc selftest` run had moved the editor window to
  100,100; it was moved back to 466,200 before closing.
- Removed: the `curlimages/curl` image pulled for the container-reachability test, all scratch
  PNGs and text files under the session scratchpad, `/tmp/qa-p5.txt`, and the QA row from
  `/var/log/netdata-alert.log`. Spool `/var/spool/netdata-alerts` back to 0 files.
- **One urgent ntfy push** was sent to the owner during the alert-pipeline test
  (`… is critical: QA critical probe = 99% (system.cpu) — QA phase5 test alert - ignore`).
- Nothing committed or pushed; `/etc` tree clean (0 porcelain lines). Nothing rebooted, restarted
  or stopped; no display or tmux change; the 5 Moodle containers ran untouched throughout.
