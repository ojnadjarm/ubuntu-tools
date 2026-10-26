# Machine quirks — read before touching the desktop, docker or the harness

## GNOME 50 / Wayland
- Screenshots: only the xdg-desktop-portal path works (`pc shot`, `bin/portal_shot.py`); every other
  route is dead — why, in `README-pc-control.md` "Findings". (unverified 2026-10-20: needs a live capture; no screenshots)
- Input: ydotool reaches every window (Chrome included) because the mouse accel-profile is `flat`
  (`gsettings get org.gnome.desktop.peripherals.mouse accel-profile`). Do not change it back —
  the acceleration story is in `README-pc-control.md` "Findings". (verified 2026-10-20: gsettings accel-profile reads 'flat')
- Keyboard layout is **latam**, so `ydotool type` mistypes symbols — use `pc type` (mutter
  RemoteDesktop keysyms). Enter/Tab still go through ydotool (`pc key Return`). (verified 2026-10-20: gsettings input-sources reads xkb latam)
- `wmctrl`/`xdotool` see only Xwayland windows: use `pc win list` (Window Calls extension) for the real window list. (verified 2026-10-20: wmctrl -l 0 rows, pc win list 1)
- A newly installed Shell extension cannot be enabled live: only
  `org.gnome.Shell.Extensions.InstallRemoteExtension` over D-Bus loads one without a logout
  (command and dialog: `README-pc-control.md` "Window management"). (unverified 2026-10-20: needs a live extension install)

## Shell scripting
- **`timeout` cost a flat ~100 ms on this box** — Ubuntu ships the Rust coreutils here, and
  `timeout 3 <cmd>` measured 104 ms against 12 ms for the same command run directly (PT15). It is
  the wrapper, not the command. Do not wrap cheap probes in a loop with it: `pc doctor` spent 2 s
  of its 5.6 s on `timeout` alone before the wrapper was dropped from everything that cannot hang.
  rust-coreutils 0.10.0 cut it to ~5 ms (7 ms against 2 ms, 2026-10-20); the loop rule still holds. (verified 2026-10-20: 20-run loop: timeout 7 ms, direct 2 ms)
- **Never hash or walk a tree under `bin/` by reading file contents** — `bin/tests/fixtures/input/proc/2138/fd/21` is a symlink to `/dev/input/event3`, and a 64 KiB read of it blocks until 64 KiB of key events arrive (this hung `pcbench arm status` and the weekly bench from 2026-09-13 to 2026-09-21, TSP-019). Hash symlinks by `os.readlink()` target and skip anything that is not a regular file. (verified 2026-10-20: ls -l fixture symlink to /dev/input/event3)
- **Claude Code's Bash shell shadows `grep` with ugrep and `find` with bfs** (shell functions from its snapshot; only a bare
  `grep`/`find` at command position, not `xargs grep`, `timeout 5 grep`, scripts or `bash -c`). ugrep can reject a bounded
  repeat after another repeat (`'.{0,30}x.{0,30}'`, `'[^"]*x[^"]{0,40}'`: `exceeds complexity limits`, exit 2; GNU grep takes
  them); bfs takes only ISO dates or `@epoch` (`-newermt '-1 day'`: `Invalid timestamp`). Use `command grep`/`command find`
  (or rg, `-newermt $(date -d '-1 day' +%F)`). A command that `cd`s into a dir and then `rm -rf`s it fails the tool's closing
  `pwd` (exit 1, getcwd) even when every step worked: `cd ~ && rm -rf "$d"`. The sleep-loop-block hook hints the first two and
  denies the third (T1082). (verified 2026-10-21: `type grep find` shows the functions; ugrep probe rc 2, `command grep` rc 1 = no match, no error)
- `pkill -f <name>` from a script kills the calling shell too (its cmdline matches). Use `killall`
  (`killall gnome-calculator` works; `killall gnome-calculato` is the one that says "no process found"). (verified 2026-10-20: pkill -f pattern killed its own shell)
- Scripts that touch the desktop must source `~/agents/bin/env.sh` (XDG_RUNTIME_DIR, WAYLAND_DISPLAY,
  DBUS_SESSION_BUS_ADDRESS, YDOTOOL_SOCKET); systemd/cron shells have none of it. (verified 2026-10-20: grep env.sh exports all four variables)
- A child of a script that sourced `env.sh` skips it (`HARNESS_ENV_LOADED`) and sees only exported
  variables, so `env.sh` exports every config.env key; a new key needs no export of its own (T116). (verified 2026-10-20: grep env.sh: set -a, HARNESS_ENV_LOADED)
- `nvm` puts node in `~/.nvm/versions/node/*/bin`, absent from non-login shells. Agent CLIs installed
  as a single binary (`~/.local/bin`, `~/.opencode/bin`) need no node; see
  `~/agents/adapters/<agent>/README.md`. (verified 2026-10-20: env -i bash finds no node)
- `/proc/<pid>/stat`'s comm field is truncated to 15 chars (`xdg-desktop-portal-gnome` reads back
  as `xdg-desktop-por`) — too short to pattern-match or to build a `systemctl` unit name from. Use
  `argv[0]`'s basename from `/proc/<pid>/cmdline` instead (EF03, `sentinel-runaway`). (verified 2026-10-20: /proc comm reads xdg-desktop-por)
- Per-process forks are the cost, not the process listing: `ps -eo ...` is one fork total, but an
  `awk`/`readlink`/`stat` call *inside* a per-pid loop is one fork per process — on ~300 processes
  that alone was 1.8-4.2 s of CPU per sentinel tick (EF04). Read `/proc/<pid>/{stat,cmdline,cgroup}`
  with bash's `$(<file)`/`read`/`mapfile` builtins (no fork), keep one in-memory pass over the
  process list, and only shell out (`readlink`, `find -lname`) for the few processes that already
  matched a cheap in-memory filter. (verified 2026-10-20: sentinel-runaway reads /proc with builtins)

## Docker
- The `docker` group is on the user but a shell only picks it up after re-login. If `docker ps` says
  permission denied: `sudo setfacl -m u:$USER:rw /var/run/docker.sock` (re-apply after a daemon restart). (verified 2026-10-20: docker group active, docker ps lists 11)
- `docker ps --format '{{.Labels}}'` is a plain string here; use `{{.Label "com.docker.compose.project"}}`. (verified 2026-10-20: Labels is a string; Label project works)
- Moodle stacks live in `~/moodle-envs/<ver>`; the shared stack (`~/moodle-envs/shared`) must be up first. (verified 2026-10-20: moodle-shared compose project up)
- **`run.sh` docker shim exit 125 is test policy, not a bug** (T530, T716): under `run.sh` every skill test's `docker` prints `run.sh: skill tests never reach the real docker (docker …)` and exits 125. A skill test with container cases skips them (`SKIP container cases: run.sh docker shim`, as cpp-package does), never unshims; run the file by hand for real docker. (verified 2026-10-20: run.sh:251 shim prints and exits 125)

- **dockerd + containerd at 24 % of a core with five idle containers is netdata, not docker (EF01).**
  netdata's `go.d` docker collector calls `GET /images/json` every cycle, and with Docker 29's
  containerd image store (`Storage Driver: overlayfs / io.containerd.snapshotter.v1`) that call
  re-walks the whole content store: **229 ms of dockerd CPU + 249 ms of containerd CPU per call**
  (20-call average; `/containers/json?all=1` 26+28 ms, `/info` 2.5+0.5 ms). At the 2 s default the
  two daemons burned 12.1 % + 12.5 % with ~3300 wakeups/s each and every Go thread parked in
  `futex_do_wait` — which is why "no clients, no events, no healthchecks" looked like internal churn.
  `sudo ss -xp | grep docker.sock` names the only two clients: both are `go.d.plugin`.
  Fix: `/etc/netdata/go.d/docker.conf` pins the job to `update_every: 60` → 0.57 % + 0.59 %.
  No daemon.json change, no dockerd/containerd restart, no stack stopped. (verified 2026-10-20: docker.conf update_every 60; Docker 29 overlayfs)


## Harness
- `~/agents` is this harness; the agent CLI's own instruction/skill/hook layout is wired by
  `adapters/$HARNESS_AGENT/install` and documented in `adapters/<agent>/README.md`. (verified 2026-10-20: adapters install scripts and READMEs present)
- `~/moodle-harness` is the git source of the **Moodle coding** harness, whose live copy is the
  agent CLI's context dir (`$HARNESS_CONTEXT_DIR`). Edit live, then run `~/moodle-harness/sync.sh`.
  **Never push.** `hooks/machine-status.sh` is machine-specific and stays out of that repo. (verified 2026-10-20: sync.sh present; machine-status.sh untracked)
- Never commit or push in any user repo. Only `/etc` is auto-committed, by etckeeper. (verified 2026-10-20: /etc/.git last etckeeper commit 2026-10-19)
- **`bin/guards/` is on the headless PATH, not the owner's.** `fleet_path` (fleetlib.sh) puts
  `~/agents/bin/guards` first, so anything under `agent-exec`/`agent-run` gets a `git`,
  `reboot`/`shutdown`/`poweroff`/`halt`, `systemctl` and `tailscale` that refuse the FLEET.md §5 orders —
  `git commit|push` (any repo), a power verb outside 04:00-05:00 Europe/Madrid, `tailscale
  down|logout` — with the three-part refusal on stderr, one JSON line in
  `~/agents/log/guards.jsonl`, and **exit 3**. Every other verb is forwarded unchanged, so
  `git status`/`pull --ff-only` and `tailscale status` still work. An interactive shell never
  sources fleetlib, so the owner's own `git commit` is untouched.
  `sudo` used to be a hole: it resets PATH through `secure_path`, so the wrapped command never
  met its own guard symlink. Closed by `bin/guards/sudo` (TSP-001), which strips sudo's options
  and applies the same rules to what sudo would run, plus `systemctl stop|disable|mask` of a
  fleet unit (`tailscaled`, `sshd`, `dark-eye*`, `docker*`, `sentinel*`, `agent@*`).
  `maintenance-run` is unaffected: its `sudo shutdown -r` only fires inside 04:00-05:00, which
  the power rule already allows. One hole remains, by design: a pcbench trial does not get the
  guards — `pcbench` builds its own PATH and relies on `bench/arms/safety/stubs` instead.
  Test: `bash ~/agents/bin/tests/guards.test.sh`. (verified 2026-10-20: ls bin/guards, fleet_path, sudo fleet_unit)

## Power / session
- The laptop never suspends: logind lid switch ignored, sleep targets masked, gsettings sleep `nothing`.
  `pc status` may report `lid=closed` while the machine is fully alive — that is expected. (verified 2026-10-20: sleep targets masked, lid ignore, 'nothing')
- Battery health is ~72 % of design because it is plugged in 24/7. (verified 2026-10-20: energy_full/energy_full_design reads 72 %)

## AT-SPI / accessibility (T10)
- The three that bite: GTK4 (and Chrome) report `0,0` for `CoordType.SCREEN`, `GetFrameBounds` throws
  `get_frame_bounds is not a function`, and the Windows interface has no signals. How `pc tree`/`pc wait-for`
  work around each: `README-pc-control.md` "Accessibility tree (T10)". (unverified 2026-10-20: needs a live GTK4 or Chrome window)
- Chrome needs `--force-renderer-accessibility` to expose its tree (`ACCESSIBILITY_ENABLED=1` no longer
  works — see "Chrome accessibility tree" below); small perf cost. (verified 2026-10-20: Chrome desktop override: flag in 3 Exec)

## `pc win list` cosmetics (known, not fixed)
- Popup and tooltip surfaces appear as their own `None  None` rows with real geometry, so a loose selector
  substring can resolve to a transient row instead of the app window. (unverified 2026-10-20: no popup open today, one window)
- A minimised window keeps printing its geometry as if visible; only `--json` carries `"minimized": true`. (unverified 2026-10-20: no minimised window today)
- `--json` sometimes reports `in_current_workspace: false` for a window on the current workspace. (unverified 2026-10-20: one window today, flag read true)

## Playwright MCP (T12)
- Registered as `~/agents/bin/playwright-mcp --config $HARNESS_CONTEXT_DIR/playwright-mcp.json` (user scope).
  The wrapper sources nvm (`@playwright/mcp` 0.0.83, >= 0.0.81 for the idle timeout, node v24.20.0) so systemd/cron shells work;
  MCP config changes only reach **new** agent sessions. (verified 2026-10-20: package.json 0.0.83; ~/.claude.json playwright entry)
- Headless by default; `PW_HEADED=1` drops `--headless` and the window shows on the physical desktop.
  `PW_PROFILE=<name>` switches to `~/agents/browser/profile-<name>` (`clean` = a second, persistent profile
  that nobody has logged in on). Names must match `[A-Za-z0-9_-]+` — the wrapper exits 2 otherwise, because
  the name is interpolated into an `rm -rf` path. The wrapper always passes `--user-data-dir`, so it picks the
  right profile even when launched without `--config`. (verified 2026-10-20: wrapper: PW_HEADED, PW_PROFILE check exits 2)
- **Session cookies:** a persistent `--user-data-dir` alone does NOT keep them — Chromium drops non-persistent
  cookies at startup, so a Moodle login was lost every run. `--restore-last-session` (in the config's
  `browser.launchOptions.args`) makes Chromium reload them; that is what keeps logins alive. (verified 2026-10-20: playwright-mcp.json carries --restore-last-session)
- Side effect: that switch also restores the previous tabs, which pile up run after run. The wrapper deletes
  `<profile>/Default/Sessions` before launch — cookies still restore, tabs do not. (verified 2026-10-20: wrapper removes Default/Sessions before launch)
- Outputs (screenshots, downloads, traces) go to `~/agents/browser/out`; viewport 1280x720. Every session
  writes a console log and a page dump there, so the wrapper deletes files older than 7 days at start. (verified 2026-10-20: config outputDir, 1280x720; wrapper find -mtime +7)
- One session per profile: a second
  Chrome on a profile another Chrome holds exits 21 at once ("Failed to create a ProcessSingleton"), so the session
  that launches second fails its first browser_* call. The wrapper sees a live `SingletonLock` (host-pid) or another
  playwright-mcp on the profile (it launches lazily) and runs on `$XDG_RUNTIME_DIR/pw-<pid>` seeded with Cookies,
  Login Data, Preferences, Local State: logins kept, nothing written back, deleted on exit. (verified 2026-10-21: playwright-mcp.test.sh, rc 21; cookie present on the copy)
- **Full chromium hangs on `--headless --dump-dom`; use chrome-headless-shell** (T1119): `chromium-1243 --headless --dump-dom about:blank` hung > 120 s here (wave 27-28), while `~/.cache/ms-playwright/chromium_headless_shell-1247/chrome-headless-shell-linux64/chrome-headless-shell --headless --no-sandbox --mute-audio --dump-dom about:blank` prints the DOM at once. Without `--no-sandbox` the shell dies on SIGTRAP in 0.02 s. For one-shot DOM dumps call the headless shell, never full chromium. (verified 2026-10-21: headless-shell-1247 0.10 s, 96 MB max RSS)

## Agent-first desktop profile (T28c)
- **The TV in standby still looks connected — nothing in the machine sees it go off** (EF10,
  2026-09-06). The 2011 Samsung keeps HPD up: with the set switched off at its remote,
  `/sys/class/drm/card1-HDMI-A-1` reads `connected/On/enabled`, RandR still lists HDMI-1, the
  EDID is still 256 bytes, `/proc/asound/card0/eld#2.4` (the live pin 0x6) still says
  `monitor_present 1 eld_valid 1 SAMSUNG`, `HDMI/DP,pcm=3 Jack` is `on`, and DDC/CI answers
  `ERR` on **and** off. The other 35 `eld#2.*` nodes are unused pins reading 0 — reading the
  first one makes ELD look like a signal it is not. So there is no automatic TV-off detection
  and there cannot be one: the Eye is told, `eye tv off` / `eye tv on` / `eye tv auto` (or out
  loud, "tv off" / "apaga la tele"). `eye health` carries the mode. Details:
  `~/the-dark-eye/RUNBOOK.md` "TV off". (unverified 2026-10-20: TV absent today, HDMI-A-1 reads disconnected)
- **Never change monitor settings without the owner.** The live layout is whatever `gdctl show` says —
  `KB/toolbox.md` §1 carries it, and it is the only copy. `gdctl` is the GNOME 50 tool
  (`gnome-monitor-config` is not installed); a layout is set with
  `gdctl set -P --logical-monitor --primary --monitor HDMI-1 --mode <mode>` and persisted to
  `~/.config/monitors.xml` a few seconds after the apply, not synchronously, so it survives logout,
  reboot and lid open/close. (verified 2026-10-20: gdctl present, gnome-monitor-config absent, monitors.xml)
- No animations means windows appear at once — `pc wait-for` on a condition, never a sleep. The profile
  itself (`pc mode`, its gsettings table, the overview and the plaintext keyring) is in
  `README-pc-control.md` "Agent-first desktop profile (T28c)". (verified 2026-10-20: enable-animations false; README section present)

## Chrome accessibility tree (T28b)
- `ACCESSIBILITY_ENABLED=1` no longer works in current Chrome: set live
  (`systemctl --user set-environment` + `dbus-update-activation-environment --systemd`, or persisted in an
  `environment.d` file), a cold-started Chrome still exposes only its frame, no renderer
  tree — verified both through `pc open` (xdg-open → `gio open`, which launches the app in a systemd scope and
  does **not** pass the launcher's env anyway) and by exporting it in front of `google-chrome` directly. (unverified 2026-10-20: needs a cold Chrome start)
- What works: `--force-renderer-accessibility`, applied for every launch route through a user override
  `~/.local/share/applications/google-chrome.desktop` (a copy of the system file with the flag in all three
  `Exec=` lines). After it, `pc open https://example.com` + `pc wait-for --window … --see` shows
  `heading "Example Domain"`. Rollback: `rm ~/.local/share/applications/google-chrome.desktop`. (verified 2026-10-20: google-chrome.desktop override: flag in 3 Exec)
- Chrome scrubs `/proc/<pid>/environ` (process-title rewriting), so never test Chrome env inheritance there —
  test the behaviour (`pc tree "Google Chrome"`) instead. (unverified 2026-10-20: needs a live Chrome; none running)
- The dead `~/.config/environment.d/50-agents-a11y.conf` was deleted and `pc-open` no longer exports
  `ACCESSIBILITY_ENABLED`; the desktop-file override is the only mechanism (QA D16). (verified 2026-10-20: 50-agents-a11y.conf absent; pc-open has no export)
- One AT-SPI registrant that stays on the bus but stops answering (`xdg-desktop-portal-gtk` does) used to
  cost the full dbind timeout on **every** query — `pc see` was 4-7 s. `a11y_tree.py` now probes each
  desktop child once under a 60 ms timeout, caches the survivors for the process, drops the rest and prints
  `warn: <name> not answering AT-SPI`. `pc a11y-click`/`pc tree --find` search the focused application
  before falling back to every application, which is what made them walk gnome-shell's whole tree (QA D23). (verified 2026-10-20: a11y_tree.py PROBE_TIMEOUT 60 and warn line)
- A GTK4 **in-window modal** ("Save Changes?") is not a window, so `pc win list --all` never shows it.
  `pc see` finds it by AT-SPI role (`alert`/`dialog`, or the `MODAL` state), prints a `modal:` line with its
  buttons and restricts `ui:` to the dialog's own subtree; `pc type`/`pc key` exit 2 while one is up unless
  `--force`. Answer it with `pc a11y-click "Discard"` (QA D24). (verified 2026-10-20: a11y_tree.py find_modal; pc type --force guard)

## Netdata (T26)
- Not in the Ubuntu 26.04 archive; it comes from the official flat repo
  `deb https://repo.netdata.cloud/repos/stable/ubuntu/ resolute/` (`/etc/apt/sources.list.d/netdata.list`). (verified 2026-10-20: netdata.list points at resolute flat repo)
- It binds `0.0.0.0:19999` + `[::]:19999` (T31) so localhost over IPv6 (`::1`, what Firefox resolves first),
  the Tailscale IP and the LAN IP all work; ufw is what restricts :19999 to `tailscale0` + `192.168.1.0/24`.
  `/etc/systemd/system/netdata.service.d/10-tailscale.conf` still orders it after `tailscaled` and waits up
  to 60 s for the Tailscale address, but now exits 0 on timeout so a LAN-only boot still serves. (verified 2026-10-20: ss 0.0.0.0 and [::]:19999; drop-in exits 0)
- `allow connections from` / `allow dashboard from` must list the sources too:
  `localhost 127.0.0.1 ::1 100.* 192.168.1.*` — netdata refuses at the app layer otherwise. (verified 2026-10-20: netdata.conf allow lines match)
- The daemon **drops to the `netdata` user**, so `alarm-notify.sh` runs as `netdata` and can neither read
  `/etc/agents/ntfy.env` (root-only) nor traverse the user's home (0750). CRITICAL alarms therefore go
  through a spool: `custom_sender` → `/usr/local/sbin/netdata-alert` (writes `/var/spool/netdata-alerts/*`)
  → `netdata-alert-drain.path` → `netdata-alert-drain.service` (root) → `notify-owner`. WARNING is filtered
  out by `DEFAULT_RECIPIENT_CUSTOM="owner|critical"`; the CLEAR of a critical alarm still notifies. (verified 2026-10-20: netdata user; spool, drain.path, owner|critical)
- `/etc/netdata/health_alarm_notify.conf` is a small override file — the stock one in
  `/usr/lib/netdata/conf.d/` is sourced first, so only changed keys belong in `/etc`. (verified 2026-10-20: override 16 lines against stock 1362)
- A push that fails is **not** dropped: `netdata-alert-drain` deletes a spooled alarm only after
  `notify-owner` exits 0, otherwise it moves it to `/var/spool/netdata-alerts-retry/` (a sibling, so the
  `DirectoryNotEmpty` path unit does not spin) and `netdata-alert-drain.timer` retries every 5 min (QA D21). (verified 2026-10-20: retry dir; timer OnUnitInactiveSec=5min)
- `/api/v1/info` reports `cloud-enabled: true` — that is the compiled-in capability, not a live connection;
  the switch is `[cloud] enabled = no` in `/var/lib/netdata/cloud.d/cloud.conf`, which is netdata's own
  location and outside etckeeper, so a reinstall would not restore it (QA D22). (verified 2026-10-20: cloud.conf enabled = no; info cloud-enabled true)
- Footprint knobs live in `[plugins]` (`otel`, `network-viewer`, `nfacct`, `python.d`, `ebpf`, `perf`,
  `slabinfo`, `debugfs`, `systemd-units`, `tc`, `scripts.d` all `no`; `systemd-journal` reads `yes`
  on 2026-10-20 and its plugin runs, so the Logs tab is back) and
  `[db] update every = 5`, `[plugin:apps] update every = 10` (+ `command options = without-users
  without-groups`, keep files on), `[plugin:cgroups] update every = 5` — `[global] update every`
  is the v1 spelling (QA D20, EF08). `systemd-journal = no` cost the dashboard's Logs tab; it was
  once disabled because the daemon's own base cost (not any plugin) still left the total over the 1.5 %
  target after every other knob (BASELINE.md `## EF08`). (verified 2026-10-20: netdata.conf sections; journal plugin process running)
- **`mem.oom_kill` counts memcg test kills, not host OOM** (T1119): the chart sums every kernel `oom-kill`, including `MemoryMax=` caps on `systemd-run` scopes that tests set on purpose; a non-zero value is not host memory pressure. Check `journalctl -k | grep oom-kill:` for `constraint=CONSTRAINT_NONE` (host) against `CONSTRAINT_MEMCG` (a capped cgroup) before calling it a memory problem. (verified 2026-10-21: 10 oom-kill lines/24 h, all CONSTRAINT_MEMCG, task python3 in app.slice/run-*.scope)

## PipeWire / WirePlumber stream memory (E23)
- WirePlumber's `restore-stream` (`/usr/share/wireplumber/scripts/node/state-stream.lua`) keys a stream's
  remembered **volume and sink** on the first of `media.role`, `application.id`, `application.name`,
  `media.name`, `node.name` — and `pw-cat` sets `media.role=music`, so every `pw-cat` playback on the box
  shares one entry, `Output/Audio:media.role:Music`, in `~/.local/state/wireplumber/stream-properties`
  (that file, not a `restore-stream` file — 0.5.13 keeps props and target together). One
  `pactl move-sink-input` on any test stream therefore pins **all** later ones to that sink, over the
  default sink, and a volume set once follows the same way. (verified 2026-10-20: state-stream.lua key list; wireplumber 0.5.13)
- Two ways out, both honoured by the restore *and* the store hooks: an explicit target in the node props
  (`pw-cat --target <sink-name>`) makes the restore skip, and `-P '{ state.restore-target = false,
  state.restore-props = false }'` opts the stream out of the memory in both directions. The Dark Eye's
  `body/src/audio.js` uses both. (verified 2026-10-20: audio.js NO_RESTORE and --target by name)
- Target sinks **by name, never by index**: the bluez sink is a brand-new node with a new index after every
  A2DP↔HFP switch (measured: 327726 → 328696 → 329831 within one session). (unverified 2026-10-20: needs a buds A2DP/HFP switch)

## HDMI audio to the TV: the host is not the suspect (A01, 2026-09-07)
- Symptom (2026-09-06 ~23:30): Spotify Playing on `alsa_output.pci-0000_00_1f.3.hdmi-stereo`,
  sink RUNNING, 100 %, stream 50 %, unmuted, TV on and showing the app — **no sound at all**. (unverified 2026-10-20: TV absent today, no HDMI sink)
- The whole host chain was audited and is clean. Nothing in EF01-EF10 touches audio:
  `sudo git -C /etc log -- '*pipewire*' '*wireplumber*' '*alsa*' '*pulse*'` returns only
  `Initial commit`; there are **no** `~/.config/pipewire`, `~/.config/wireplumber`,
  `/etc/pipewire` or `/etc/wireplumber` files at all (only the distro
  `/usr/share/wireplumber/wireplumber.conf.d/alsa-vm.conf`, untouched since install).
  `/etc/security/limits.d/90-agents.conf` is nofile only, `/etc/sysctl.d/90-agents.conf` is
  inotify/swappiness/map_count/somaxconn/sysrq. `sentinel-check`'s only audio line resets
  `pw-metadata … log.level` to 2 — a log knob, no routing or volume effect. PipeWire's
  `data-loop.0` is still `SCHED_RR`. (verified 2026-10-20: no pipewire config files; limits, sysctl keys match)
- **The silent proof (repeatable, makes no sound):** play a zero-amplitude wav to the sink and
  watch the kernel PCM, not PipeWire:
  `python3 -c "import wave;w=wave.open('/tmp/s.wav','wb');w.setnchannels(2);w.setsampwidth(2);w.setframerate(48000);w.writeframes(b'\0'*(48000*2*2*6));w.close()"`
  then `pw-play --target alsa_output.pci-0000_00_1f.3.hdmi-stereo -P '{ state.restore-target = false, state.restore-props = false }' /tmp/s.wav`
  while reading `/proc/asound/card0/pcm3p/sub0/{hw_params,status}`.
  2026-09-07 result: `S32_LE 2ch 48000 period 1024 buffer 32768`, `state: RUNNING` for the whole
  6 s, `pw-top` 0 ERR / 0 xruns. HDA DMA to the TV pin is provably working. (unverified 2026-10-20: plays to the TV sink; TV absent)
- The routing is unambiguous and worth writing down once: sink → `api.alsa.path=hdmi:0` →
  `hw:0,3` (`HDMI 0`) → codec 2 pin **0x06** (`Pin-ctls: 0x40 OUT`, `Connection: 0x03*`) →
  the only ELD with a monitor, `/proc/asound/card0/eld#2.4` (`SAMSUNG`, `codec_cvt_nid 0x3`,
  `speakers FL/FR`, LPCM only). `HDMI/DP,pcm=3 Jack` = `on`, all four `IEC958 Playback Switch`
  = `on`, `default-routes` has `hdmi-output-0` unmuted at 1.0. The other 35 `eld#2.*` are unused
  pins reading 0 — same trap as EF10. (unverified 2026-10-20: TV absent; eld#2.4 monitor_present 0)
- **Therefore: with everything above green, silence is the TV's, and only an ear can tell them
  apart.** This 2011 Samsung is the classic case — an HDMI input labelled `PC`/`DVI PC` is
  treated as DVI and the set mutes HDMI audio while showing perfect video; "Sound Output" left
  on an external/optical device does the same. Neither is visible from the host: DDC/CI answers
  `ERR` here (EF10) and nothing in sysfs, RandR, EDID or ELD moves. (unverified 2026-10-20: needs an ear on the TV)
- **The discriminating test, by ear, in this order** (there is no `pc audio test` verb):
  1. TV: `pw-play --target alsa_output.pci-0000_00_1f.3.hdmi-stereo -P '{ state.restore-target = false, state.restore-props = false }' /usr/share/sounds/alsa/Front_Center.wav`
  2. If silent, the laptop speakers — this needs a profile change, so restore it:
     `pactl set-card-profile alsa_card.pci-0000_00_1f.3 output:analog-stereo+input:analog-stereo`,
     `pw-play --target alsa_output.pci-0000_00_1f.3.analog-stereo -P '{ state.restore-target = false, state.restore-props = false }' /usr/share/sounds/alsa/Front_Center.wav`,
     then `pactl set-card-profile alsa_card.pci-0000_00_1f.3 output:hdmi-stereo+input:analog-stereo`.
  Speakers audible + TV silent = the TV. Both silent = re-open host-side (and only then). (verified 2026-10-20: pactl lists both card profile names)
- `snd_hda_intel power_save=1` (kernel default, no fleet drop-in) powers the codec down 1 s after
  idle and can clip the **start** of a clip on this codec. It cannot explain a whole silent track;
  do not chase it first, and do not raise it without the ear test above. (verified 2026-10-20: power_save 1, no modprobe.d drop-in)
- Never flap the card profile to "test" this (`analog ↔ off ↔ hdmi`, as happened on 2026-09-06):
  it proves nothing the ELD and `pcm3p/status` do not already say. (verified 2026-10-20: rule only; profile analog-stereo active today)

## Screen captures while the owner is present
Every `pc shot` / gnome-screenshot is visible to the owner on the TV (he counted 20 during a parity check and asked why). The rule that follows from it is `KB/toolbox.md` §6 practice 2; renderer comparisons dump frames offscreen (cairo `write_to_png`, `glReadPixels`/FBO) from a seeded scene instead.

- **Hand-run eye-render hijacks the live eye** unless the socket is private (the bridge `sock` option alone is not enough; `net.createServer` accepts any number of clients). 2026-09-06 15:46: E29 made the production eye flap and vanish 3 s. **Do not type the recipe — run `body-sandbox`** (EF06); its subcommands, the mandatory `--x-offset -1400` and the scene names are in `KB/toolbox.md` §3. Sandbox processes carry `DARK_EYE_SANDBOX=<name>` and live under the sandbox dir, so `sentinel-runaway` rule 3 tells them from a hijack and still reaps one older than 2 h — `body-sandbox down` is the normal exit. Since TSP-016 (2026-09-21) rule 3 matches the body by argv[0] (Node >= 23 sets comm to `MainThread`) and, when `/proc/<pid>/environ` carries `DARK_EYE_SANDBOX=<name>`, runs `body-sandbox down --name <name>` once per name instead of killing one pid; processes inside `dark-eye.service`'s cgroup are never touched. (verified 2026-10-20: body-sandbox guards; sentinel-runaway down --name)

- **dark-eye runs straight from the working tree**: any `systemctl --user restart dark-eye` while another agent is mid-edit ships a half-applied build (16:30 2026-09-06: empty transcripts). Before restarting, check no other agent is editing body/src (ask the orchestrator) and that `npm test` passes on the tree as it is. (verified 2026-10-20: dark-eye unit runs ~/the-dark-eye/body directly)

- **PipeWire `log.level` — never raise it globally**: `pw-metadata -n settings 0 log.level 4` (E30, 2026-09-06) plus three wireplumber restarts while it was raised (E23) wrote 33 054 pipewire lines in 2 s and 13 711 wireplumber lines at 01:31 — 14 + 6 MB of that day's journal, doubled into `/var/log/syslog` by rsyslog (EF09). Level is back to 2. (verified 2026-10-20: pw-metadata settings log.level reads 2)
- Debug one client instead: `PIPEWIRE_DEBUG="spa.bluez5*:4"` on that process's env, never the global `log.level`. (verified 2026-10-20: man pipewire documents PIPEWIRE_DEBUG)
- If `log.level` must go up host-wide for a moment, wrap it in a `trap` that resets it to 2 within 10 s — a level left raised across a restart is what turned one burst into three. EF09's sentinel resets any level it finds above 2; this rule is for the human/agent side, not a substitute for it.
  `agent-preflight` reads the live level back with five other Dark-Eye facts in one screen
  (`KB/toolbox.md` §3) — run it first in any Dark-Eye session. (verified 2026-10-20: sentinel-check:154, agent-preflight read log.level)

## PT01-PT16 (`pc` tools)
- **`/tmp` is tmpfs on this box**: a disk-IO test that writes there measures RAM, not disk. `pc io`'s and any other test's scratch files go under `$HOME` (or `$XDG_RUNTIME_DIR`, also tmpfs but the accepted one for sockets/caches) instead. (verified 2026-10-20: findmnt /tmp reads tmpfs)
- **`busctl --json` cannot dump bluez `ManufacturerData`**: the property is `a{qv}` with a variant value that `busctl`'s JSON encoder does not serialise; `pc bt`/`pc dbus` read it with `get-property` on the specific key, never a blanket `GetManagedObjects --json` dump when that field is wanted. (unverified 2026-10-20: needs a bluez device with ManufacturerData)
- **BlueZ discovery is per-client**: `StartDiscovery`/`StopDiscovery` are scoped to the calling D-Bus connection, so two one-shot `busctl` calls cannot hold a scan window open (the second call's `StopDiscovery` answers "No discovery started"). `pc bt scan --seconds N` keeps one `bluetoothctl --timeout N scan on` connection alive for the whole window instead. (unverified 2026-10-20: needs a live Bluetooth scan)
- **`systemctl show --value` ignores the property order given on the command line**: `systemctl show -p A,B --value unit` prints values in systemd's own property order, not `A,B`'s — never zip the two lists positionally; ask for one property per call, or use the (ordered) non-`--value` form and pick fields out by name. (verified 2026-10-20: -p MainPID,Id prints Id first)
- **`dmesg -J` ignores `--time-format`**: JSON output always carries raw monotonic/realtime microsecond fields regardless of `--time-format`; convert them in `jq`/python, don't pass `--time-format iso` expecting it to touch the JSON path. (verified 2026-10-20: dmesg -J --time-format iso: float time)
- **python-evdev's `UInput` node lookup costs 1.9 s of a 2.3 s `pc input inject`**: it retries `/dev/input/event*` 19 times at 0.1 s on a node the calling user cannot open, before falling back. `UI_GET_SYSNAME` on the freshly created uinput fd gets the node name directly and skips the retry loop (PT10). (unverified 2026-10-20: needs a live uinput device)
- **jq operator precedence in `a|b and c`**: `|` binds looser than expected next to `and`/`or`, so `.pci|length>5 and (...)` pipes `.pci` into the *entire* `and` expression, not just `length>5`. Parenthesise the piped side: `(.pci|length>5) and (...)` (found in `pc hw`'s own success-check line, PT07). (verified 2026-10-20: jq piped form errors; parenthesised returns true)
- **Parallel sandboxes collide on the default name.** 2026-09-14: a second ticket's `body-sandbox up` found `s1` already up, left `DARK_EYE_CONFIG` empty and its `eye speak` reached the live body; its unnamed `down` then killed the sibling's sandbox. When more than one agent may be running, always `body-sandbox up --name <ticket>` and `down --name <ticket>`. Guarded since M02b (2026-09-14): `down` refuses without `--name`/`--all`, an unnamed `up` is `sb-<pid>`, and `up` on a name already up prints `export DARK_EYE_CONFIG=/nonexistent; false` so the eval'd session cannot reach the live body. (verified 2026-10-20: body-sandbox help: sb-<pid>, /nonexistent, --all)
- **Claude Code shells take PATH from the claude process (or settings `env.PATH`), never from `~/.bashrc`** (T287, 2026-10-07): the snapshot sources `.bashrc` non-interactively (guard returns) and then writes `export PATH=<process PATH>`; the orchestrator unit sets only `~/.local/bin:/usr/local/bin:/usr/bin:/bin`, so a new `bin/` command or nvm node is found only once `install.sh` §3 links it into `~/.local/bin` — rerun `install.sh` after adding a command. (verified 2026-10-20: orchestrator unit PATH; install.sh links ~/.local/bin)
- **`systemd-run` by hand: always `--collect`** (TSP-044, 2026-10-19): a failed `run-*` scope without it stays in `--failed` until reset. `pc status` lists such transient units apart (`host.failed_transient`, WARN, no FAIL) and `sentinel-check` resets one older than 10 min with `pc units reset-failed <u> --user --apply`. (verified 2026-10-20: pc-status failed_transient; sentinel-check reset-failed)
- **localsearch-3 indexes all of `$HOME` and SEGV-loops on agent output** (T450, 2026-10-19): ~/agent-work held 228k of its rows, the unit used 99 s CPU/h steady and ~2,700 s/h re-crawling after each of its core dumps (7 on 10-16, 3 on 10-19). Hidden dirs (~/.claude) are never indexed. `pc search-index status` shows cost, 24 h CPU and SEGV count from the journal (CPU since start hides a crash loop) and busiest dirs; `pc search-index exclude <dir> --apply` writes a ledgered `.trackerignore` (never ~/moodle-envs). T732 (2026-10-20): ~/moodle-envs data churn (40k rows, 11.7k changed/24 h) is filtered by name instead, `exclude --name moodledata|behatdata|phpunitdata --apply` (gsettings `org.freedesktop.Tracker3.Miner.Files ignored-directories`, basename match anywhere, nothing written inside ~/moodle-envs); ~/opt excluded by `.trackerignore`. (verified 2026-10-20: pc search-index status: 4 crashes/24 h, excludes)
- **localsearch-3 SEGVs are hidden from apport, not fixed** (T571, 2026-10-19): an upstream use-after-free in its directory-monitor GList (`g_file_equal` on a freed GFile, T471 `evidence/T471/diagnosis.txt`; localsearch 3.11.0-1ubuntu1.1, upstream https://gitlab.gnome.org/GNOME/localsearch/-/issues) made every dump a `/var/crash` report that whoopsie never marks `.uploaded`, so `apport-autoreport.service` failed (exit 2) each time. `~/.apport-ignore.xml` (apport's own per-user denylist, written by `Report.mark_ignore()`) lists `/usr/libexec/localsearch-3` with the binary's mtime: apport drops the crash before writing a report, and a package upgrade (newer mtime) re-enables reporting. No systemd-coredump here (core_pattern pipes to apport), so the trace left is the kernel `traps: localsearch-3[pid]` line; `pc crashes` shows it as an `ignored-by-apport` row with its 24 h count. (verified 2026-10-20: .apport-ignore.xml lists localsearch-3; pc crashes)

## Firmware, PATH, Wi-Fi, boot log (T1119)
- **fwupdmgr 2.1.1 `get-remotes --json` is not pure JSON**: a text tree follows the JSON object, so `json.load`/`jq` on stdout fails ("Extra data"). Parse up to the first closing `}` at column 0 (or `json.JSONDecoder().raw_decode`), or read the remotes over D-Bus. (verified 2026-10-21: 106 stdout lines, JSON ends at line 63, json.load: Extra data line 64)
- **Agent PATH has no `/usr/sbin`**: Claude Code shells get `~/.local/bin:/usr/local/bin:/usr/bin:/bin` (see PT section), so `iw`, `ethtool`-style admin tools answer `command not found` (51 not-found in 7 d, T1087). Call them by absolute path (`/usr/sbin/iw`). (verified 2026-10-21: 0 sbin entries in PATH; `command -v iw` empty, /usr/sbin/iw exists)
- **mt76 (mt7921e) misreports `txpower 3.00 dBm`**: `iw dev` shows 3.00 dBm while the link runs at about -40 dBm signal and ~1 Gb/s; the figure is a driver report bug, not a weak radio. Judge the link by `iw dev wlo1 link` signal and bitrate. (verified 2026-10-21: txpower 3.00 dBm, signal -40 dBm, tx bitrate 960.7 MBit/s HE-MCS 9)
- **ACPI `_PSV/_HOT/_CRT AE_NOT_FOUND` and `[Firmware Bug]: CPUn: Topology domain` are harmless boot noise**: the ASUS BIOS references missing EC thermal symbols (`\_SB.PC00.LPCB.EC0.SEN1._PSV`) and the hybrid CPU reports mismatched topology shifts; thermals and scheduling work. Do not treat them as a hardware or kernel fault. (verified 2026-10-21: boot 0: 48 _PSV/_HOT/_CRT lines, 48 Topology domain lines; temp 62C, smart PASSED)
- **journald write_bytes is page-dirtying of its mmapped journal files, not fsync; no gain from either lever**: strace 45 s shows 0 fsync/msync, only ftruncate; each entry re-dirties ~40 scattered pages (~150 KB/entry) once the file is full of objects (user-1000 file: 34K-entry burst 17:40, then 2,493 KB/min at 25.9M used). `vm.dirty_expire_centisecs` 3000 → 6000: no gain (2,493 → 2,509 KB/min, undone). `SystemMaxFileSize=32M`: no gain, undone: 236 KB/min with it and 240 KB/min without it on the same freshly rotated files, so the drop from 2,493 is the `journalctl --rotate` transient, and a 32M cap still allows the 25.9M baseline state. Real lever: fewer entries (sudo = 60 % of user-1000 entries, T1147). Re-measure: `~/agent-work/evidence/T1150/sample.sh`. (verified 2026-10-21: 3 × 60 s per state, T1150)
- **A dir-only ignore (`.research/`) does not match a symlink, and git treats ignored files as expendable**: a worktree symlink to the main tree's ignored dir gets staged by `git add -A` (mode 120000); `git merge --squash` of that branch then deletes the ignored real directory to check out the tracked symlink, with no warning. Ignore with `name` (no slash) and copy, never symlink, ignored dirs into worktrees. (verified 2026-10-26: git 2.53 throwaway repro, T1393 lost mooblox/.research, T1395)
