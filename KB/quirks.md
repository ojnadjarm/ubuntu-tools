# Machine quirks — read before touching the desktop, docker or the harness

## GNOME 50 / Wayland
- Screenshots: only the xdg-desktop-portal path works (`pc shot`, `bin/portal_shot.py`); every other
  route is dead — why, in `README-pc-control.md` "Findings".
- Input: ydotool reaches every window (Chrome included) because the mouse accel-profile is `flat`
  (`gsettings get org.gnome.desktop.peripherals.mouse accel-profile`). Do not change it back —
  the acceleration story is in `README-pc-control.md` "Findings".
- Keyboard layout is **latam**, so `ydotool type` mistypes symbols — use `pc type` (mutter
  RemoteDesktop keysyms). Enter/Tab still go through ydotool (`pc key Return`).
- `wmctrl`/`xdotool` see only Xwayland windows: use `pc win list` (Window Calls extension) for the real window list.
- A newly installed Shell extension cannot be enabled live: only
  `org.gnome.Shell.Extensions.InstallRemoteExtension` over D-Bus loads one without a logout
  (command and dialog: `README-pc-control.md` "Window management").

## Shell scripting
- **`timeout` costs a flat ~100 ms on this box** — Ubuntu ships the Rust coreutils here, and
  `timeout 3 <cmd>` measures 104 ms against 12 ms for the same command run directly (PT15). It is
  the wrapper, not the command. Do not wrap cheap probes in a loop with it: `pc doctor` spent 2 s
  of its 5.6 s on `timeout` alone before the wrapper was dropped from everything that cannot hang.
- **Never hash or walk a tree under `bin/` by reading file contents** — `bin/tests/fixtures/input/proc/2138/fd/21` is a symlink to `/dev/input/event3`, and a 64 KiB read of it blocks until 64 KiB of key events arrive (this hung `pcbench arm status` and the weekly bench from 2026-09-13 to 2026-09-21, TSP-019). Hash symlinks by `os.readlink()` target and skip anything that is not a regular file.
- `pkill -f <name>` from a script kills the calling shell too (its cmdline matches). Use `killall`
  (`killall gnome-calculator` works; `killall gnome-calculato` is the one that says "no process found").
- Scripts that touch the desktop must source `~/agents/bin/env.sh` (XDG_RUNTIME_DIR, WAYLAND_DISPLAY,
  DBUS_SESSION_BUS_ADDRESS, YDOTOOL_SOCKET); systemd/cron shells have none of it.
- `nvm` puts node in `~/.nvm/versions/node/*/bin`, absent from non-login shells. Agent CLIs installed
  as a single binary (`~/.local/bin`, `~/.opencode/bin`) need no node; see
  `~/agents/adapters/<agent>/README.md`.
- `/proc/<pid>/stat`'s comm field is truncated to 15 chars (`xdg-desktop-portal-gnome` reads back
  as `xdg-desktop-por`) — too short to pattern-match or to build a `systemctl` unit name from. Use
  `argv[0]`'s basename from `/proc/<pid>/cmdline` instead (EF03, `sentinel-runaway`).
- Per-process forks are the cost, not the process listing: `ps -eo ...` is one fork total, but an
  `awk`/`readlink`/`stat` call *inside* a per-pid loop is one fork per process — on ~300 processes
  that alone was 1.8-4.2 s of CPU per sentinel tick (EF04). Read `/proc/<pid>/{stat,cmdline,cgroup}`
  with bash's `$(<file)`/`read`/`mapfile` builtins (no fork), keep one in-memory pass over the
  process list, and only shell out (`readlink`, `find -lname`) for the few processes that already
  matched a cheap in-memory filter.

## Docker
- The `docker` group is on the user but a shell only picks it up after re-login. If `docker ps` says
  permission denied: `sudo setfacl -m u:$USER:rw /var/run/docker.sock` (re-apply after a daemon restart).
- `docker ps --format '{{.Labels}}'` is a plain string here; use `{{.Label "com.docker.compose.project"}}`.
- Moodle stacks live in `~/moodle-envs/<ver>`; the shared stack (`~/moodle-envs/shared`) must be up first.

- **dockerd + containerd at 24 % of a core with five idle containers is netdata, not docker (EF01).**
  netdata's `go.d` docker collector calls `GET /images/json` every cycle, and with Docker 29's
  containerd image store (`Storage Driver: overlayfs / io.containerd.snapshotter.v1`) that call
  re-walks the whole content store: **229 ms of dockerd CPU + 249 ms of containerd CPU per call**
  (20-call average; `/containers/json?all=1` 26+28 ms, `/info` 2.5+0.5 ms). At the 2 s default the
  two daemons burned 12.1 % + 12.5 % with ~3300 wakeups/s each and every Go thread parked in
  `futex_do_wait` — which is why "no clients, no events, no healthchecks" looked like internal churn.
  `sudo ss -xp | grep docker.sock` names the only two clients: both are `go.d.plugin`.
  Fix: `/etc/netdata/go.d/docker.conf` pins the job to `update_every: 60` → 0.57 % + 0.59 %.
  No daemon.json change, no dockerd/containerd restart, no stack stopped.


## Harness
- `~/agents` is this harness; the agent CLI's own instruction/skill/hook layout is wired by
  `adapters/$HARNESS_AGENT/install` and documented in `adapters/<agent>/README.md`.
- `~/moodle-harness` is the git source of the **Moodle coding** harness, whose live copy is the
  agent CLI's context dir (`$HARNESS_CONTEXT_DIR`). Edit live, then run `~/moodle-harness/sync.sh`.
  **Never push.** `hooks/machine-status.sh` is machine-specific and stays out of that repo.
- Never commit or push in any user repo. Only `/etc` is auto-committed, by etckeeper.
- **`bin/guards/` is on the headless PATH, not the owner's.** `fleet_path` (fleetlib.sh) puts
  `~/agents/bin/guards` first, so anything under `agent-exec`/`agent-run` gets a `git`,
  `reboot`/`shutdown`/`poweroff`/`halt` and `tailscale` that refuse the FLEET.md §5 orders —
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
  Test: `bash ~/agents/bin/tests/guards.test.sh`.

## Power / session
- The laptop never suspends: logind lid switch ignored, sleep targets masked, gsettings sleep `nothing`.
  `pc status` may report `lid=closed` while the machine is fully alive — that is expected.
- Battery health is ~72 % of design because it is plugged in 24/7.

## AT-SPI / accessibility (T10)
- The three that bite: GTK4 (and Chrome) report `0,0` for `CoordType.SCREEN`, `GetFrameBounds` throws
  `get_frame_bounds is not a function`, and the Windows interface has no signals. How `pc tree`/`pc wait-for`
  work around each: `README-pc-control.md` "Accessibility tree (T10)".
- Chrome needs `--force-renderer-accessibility` to expose its tree (`ACCESSIBILITY_ENABLED=1` no longer
  works — see "Chrome accessibility tree" below); small perf cost.

## `pc win list` cosmetics (known, not fixed)
- Popup and tooltip surfaces appear as their own `None  None` rows with real geometry, so a loose selector
  substring can resolve to a transient row instead of the app window.
- A minimised window keeps printing its geometry as if visible; only `--json` carries `"minimized": true`.
- `--json` sometimes reports `in_current_workspace: false` for a window on the current workspace.

## Playwright MCP (T12)
- Registered as `~/agents/bin/playwright-mcp --config $HARNESS_CONTEXT_DIR/playwright-mcp.json` (user scope).
  The wrapper sources nvm (pinned `@playwright/mcp` 0.0.80, node v24.20.0) so systemd/cron shells work;
  MCP config changes only reach **new** agent sessions.
- Headless by default; `PW_HEADED=1` drops `--headless` and the window shows on the physical desktop.
  `PW_PROFILE=<name>` switches to `~/agents/browser/profile-<name>` (`clean` = a second, persistent profile
  that nobody has logged in on). Names must match `[A-Za-z0-9_-]+` — the wrapper exits 2 otherwise, because
  the name is interpolated into an `rm -rf` path. The wrapper always passes `--user-data-dir`, so it picks the
  right profile even when launched without `--config`.
- **Session cookies:** a persistent `--user-data-dir` alone does NOT keep them — Chromium drops non-persistent
  cookies at startup, so a Moodle login was lost every run. `--restore-last-session` (in the config's
  `browser.launchOptions.args`) makes Chromium reload them; that is what keeps logins alive.
- Side effect: that switch also restores the previous tabs, which pile up run after run. The wrapper deletes
  `<profile>/Default/Sessions` before launch — cookies still restore, tabs do not.
- Outputs (screenshots, downloads, traces) go to `~/agents/browser/out`; viewport 1280x720. Every session
  writes a console log and a page dump there, so the wrapper deletes files older than 7 days at start.
- One session per profile: concurrent runs collide on the Chromium profile lock.

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
  `~/the-dark-eye/RUNBOOK.md` "TV off".
- **Never change monitor settings without the owner.** The live layout is whatever `gdctl show` says —
  `KB/toolbox.md` §1 carries it, and it is the only copy. `gdctl` is the GNOME 50 tool
  (`gnome-monitor-config` is not installed); a layout is set with
  `gdctl set -P --logical-monitor --primary --monitor HDMI-1 --mode <mode>` and persisted to
  `~/.config/monitors.xml` a few seconds after the apply, not synchronously, so it survives logout,
  reboot and lid open/close.
- No animations means windows appear at once — `pc wait-for` on a condition, never a sleep. The profile
  itself (`pc mode`, its gsettings table, the overview and the plaintext keyring) is in
  `README-pc-control.md` "Agent-first desktop profile (T28c)".

## Chrome accessibility tree (T28b)
- `ACCESSIBILITY_ENABLED=1` no longer works in current Chrome: set live
  (`systemctl --user set-environment` + `dbus-update-activation-environment --systemd`, or persisted in an
  `environment.d` file), a cold-started Chrome still exposes only its frame, no renderer
  tree — verified both through `pc open` (xdg-open → `gio open`, which launches the app in a systemd scope and
  does **not** pass the launcher's env anyway) and by exporting it in front of `google-chrome` directly.
- What works: `--force-renderer-accessibility`, applied for every launch route through a user override
  `~/.local/share/applications/google-chrome.desktop` (a copy of the system file with the flag in all three
  `Exec=` lines). After it, `pc open https://example.com` + `pc wait-for --window … --see` shows
  `heading "Example Domain"`. Rollback: `rm ~/.local/share/applications/google-chrome.desktop`.
- Chrome scrubs `/proc/<pid>/environ` (process-title rewriting), so never test Chrome env inheritance there —
  test the behaviour (`pc tree "Google Chrome"`) instead.
- The dead `~/.config/environment.d/50-agents-a11y.conf` was deleted and `pc-open` no longer exports
  `ACCESSIBILITY_ENABLED`; the desktop-file override is the only mechanism (QA D16).
- One AT-SPI registrant that stays on the bus but stops answering (`xdg-desktop-portal-gtk` does) used to
  cost the full dbind timeout on **every** query — `pc see` was 4-7 s. `a11y_tree.py` now probes each
  desktop child once under a 60 ms timeout, caches the survivors for the process, drops the rest and prints
  `warn: <name> not answering AT-SPI`. `pc a11y-click`/`pc tree --find` search the focused application
  before falling back to every application, which is what made them walk gnome-shell's whole tree (QA D23).
- A GTK4 **in-window modal** ("Save Changes?") is not a window, so `pc win list --all` never shows it.
  `pc see` finds it by AT-SPI role (`alert`/`dialog`, or the `MODAL` state), prints a `modal:` line with its
  buttons and restricts `ui:` to the dialog's own subtree; `pc type`/`pc key` exit 2 while one is up unless
  `--force`. Answer it with `pc a11y-click "Discard"` (QA D24).

## Netdata (T26)
- Not in the Ubuntu 26.04 archive; it comes from the official flat repo
  `deb https://repo.netdata.cloud/repos/stable/ubuntu/ resolute/` (`/etc/apt/sources.list.d/netdata.list`).
- It binds `0.0.0.0:19999` + `[::]:19999` (T31) so localhost over IPv6 (`::1`, what Firefox resolves first),
  the Tailscale IP and the LAN IP all work; ufw is what restricts :19999 to `tailscale0` + `192.168.1.0/24`.
  `/etc/systemd/system/netdata.service.d/10-tailscale.conf` still orders it after `tailscaled` and waits up
  to 60 s for the Tailscale address, but now exits 0 on timeout so a LAN-only boot still serves.
- `allow connections from` / `allow dashboard from` must list the sources too:
  `localhost 127.0.0.1 ::1 100.* 192.168.1.*` — netdata refuses at the app layer otherwise.
- The daemon **drops to the `netdata` user**, so `alarm-notify.sh` runs as `netdata` and can neither read
  `/etc/agents/ntfy.env` (root-only) nor traverse the user's home (0750). CRITICAL alarms therefore go
  through a spool: `custom_sender` → `/usr/local/sbin/netdata-alert` (writes `/var/spool/netdata-alerts/*`)
  → `netdata-alert-drain.path` → `netdata-alert-drain.service` (root) → `notify-owner`. WARNING is filtered
  out by `DEFAULT_RECIPIENT_CUSTOM="owner|critical"`; the CLEAR of a critical alarm still notifies.
- `/etc/netdata/health_alarm_notify.conf` is a small override file — the stock one in
  `/usr/lib/netdata/conf.d/` is sourced first, so only changed keys belong in `/etc`.
- A push that fails is **not** dropped: `netdata-alert-drain` deletes a spooled alarm only after
  `notify-owner` exits 0, otherwise it moves it to `/var/spool/netdata-alerts-retry/` (a sibling, so the
  `DirectoryNotEmpty` path unit does not spin) and `netdata-alert-drain.timer` retries every 5 min (QA D21).
- `/api/v1/info` reports `cloud-enabled: true` — that is the compiled-in capability, not a live connection;
  the switch is `[cloud] enabled = no` in `/var/lib/netdata/cloud.d/cloud.conf`, which is netdata's own
  location and outside etckeeper, so a reinstall would not restore it (QA D22).
- Footprint knobs live in `[plugins]` (`otel`, `network-viewer`, `nfacct`, `python.d`, `ebpf`, `perf`,
  `slabinfo`, `debugfs`, `systemd-units`, `tc`, `scripts.d`, `systemd-journal` all `no`) and
  `[db] update every = 5`, `[plugin:apps] update every = 10` (+ `command options = without-users
  without-groups`, keep files on), `[plugin:cgroups] update every = 5` — `[global] update every`
  is the v1 spelling (QA D20, EF08). `systemd-journal = no` costs the dashboard's Logs tab; it was
  disabled because the daemon's own base cost (not any plugin) still left the total over the 1.5 %
  target after every other knob (BASELINE.md `## EF08`).

## PipeWire / WirePlumber stream memory (E23)
- WirePlumber's `restore-stream` (`/usr/share/wireplumber/scripts/node/state-stream.lua`) keys a stream's
  remembered **volume and sink** on the first of `media.role`, `application.id`, `application.name`,
  `media.name`, `node.name` — and `pw-cat` sets `media.role=music`, so every `pw-cat` playback on the box
  shares one entry, `Output/Audio:media.role:Music`, in `~/.local/state/wireplumber/stream-properties`
  (that file, not a `restore-stream` file — 0.5.13 keeps props and target together). One
  `pactl move-sink-input` on any test stream therefore pins **all** later ones to that sink, over the
  default sink, and a volume set once follows the same way.
- Two ways out, both honoured by the restore *and* the store hooks: an explicit target in the node props
  (`pw-cat --target <sink-name>`) makes the restore skip, and `-P '{ state.restore-target = false,
  state.restore-props = false }'` opts the stream out of the memory in both directions. The Dark Eye's
  `body/src/audio.js` uses both.
- Target sinks **by name, never by index**: the bluez sink is a brand-new node with a new index after every
  A2DP↔HFP switch (measured: 327726 → 328696 → 329831 within one session).

## HDMI audio to the TV: the host is not the suspect (A01, 2026-09-07)
- Symptom (2026-09-06 ~23:30): Spotify Playing on `alsa_output.pci-0000_00_1f.3.hdmi-stereo`,
  sink RUNNING, 100 %, stream 50 %, unmuted, TV on and showing the app — **no sound at all**.
- The whole host chain was audited and is clean. Nothing in EF01-EF10 touches audio:
  `sudo git -C /etc log -- '*pipewire*' '*wireplumber*' '*alsa*' '*pulse*'` returns only
  `Initial commit`; there are **no** `~/.config/pipewire`, `~/.config/wireplumber`,
  `/etc/pipewire` or `/etc/wireplumber` files at all (only the distro
  `/usr/share/wireplumber/wireplumber.conf.d/alsa-vm.conf`, untouched since install).
  `/etc/security/limits.d/90-agents.conf` is nofile only, `/etc/sysctl.d/90-agents.conf` is
  inotify/swappiness/map_count/somaxconn/sysrq. `sentinel-check`'s only audio line resets
  `pw-metadata … log.level` to 2 — a log knob, no routing or volume effect. PipeWire's
  `data-loop.0` is still `SCHED_RR`.
- **The silent proof (repeatable, makes no sound):** play a zero-amplitude wav to the sink and
  watch the kernel PCM, not PipeWire:
  `python3 -c "import wave;w=wave.open('/tmp/s.wav','wb');w.setnchannels(2);w.setsampwidth(2);w.setframerate(48000);w.writeframes(b'\0'*(48000*2*2*6));w.close()"`
  then `pw-play --target alsa_output.pci-0000_00_1f.3.hdmi-stereo -P '{ state.restore-target = false, state.restore-props = false }' /tmp/s.wav`
  while reading `/proc/asound/card0/pcm3p/sub0/{hw_params,status}`.
  2026-09-07 result: `S32_LE 2ch 48000 period 1024 buffer 32768`, `state: RUNNING` for the whole
  6 s, `pw-top` 0 ERR / 0 xruns. HDA DMA to the TV pin is provably working.
- The routing is unambiguous and worth writing down once: sink → `api.alsa.path=hdmi:0` →
  `hw:0,3` (`HDMI 0`) → codec 2 pin **0x06** (`Pin-ctls: 0x40 OUT`, `Connection: 0x03*`) →
  the only ELD with a monitor, `/proc/asound/card0/eld#2.4` (`SAMSUNG`, `codec_cvt_nid 0x3`,
  `speakers FL/FR`, LPCM only). `HDMI/DP,pcm=3 Jack` = `on`, all four `IEC958 Playback Switch`
  = `on`, `default-routes` has `hdmi-output-0` unmuted at 1.0. The other 35 `eld#2.*` are unused
  pins reading 0 — same trap as EF10.
- **Therefore: with everything above green, silence is the TV's, and only an ear can tell them
  apart.** This 2011 Samsung is the classic case — an HDMI input labelled `PC`/`DVI PC` is
  treated as DVI and the set mutes HDMI audio while showing perfect video; "Sound Output" left
  on an external/optical device does the same. Neither is visible from the host: DDC/CI answers
  `ERR` here (EF10) and nothing in sysfs, RandR, EDID or ELD moves.
- **The discriminating test, by ear, in this order** (there is no `pc audio test` verb):
  1. TV: `pw-play --target alsa_output.pci-0000_00_1f.3.hdmi-stereo -P '{ state.restore-target = false, state.restore-props = false }' /usr/share/sounds/alsa/Front_Center.wav`
  2. If silent, the laptop speakers — this needs a profile change, so restore it:
     `pactl set-card-profile alsa_card.pci-0000_00_1f.3 output:analog-stereo+input:analog-stereo`,
     `pw-play --target alsa_output.pci-0000_00_1f.3.analog-stereo -P '{ state.restore-target = false, state.restore-props = false }' /usr/share/sounds/alsa/Front_Center.wav`,
     then `pactl set-card-profile alsa_card.pci-0000_00_1f.3 output:hdmi-stereo+input:analog-stereo`.
  Speakers audible + TV silent = the TV. Both silent = re-open host-side (and only then).
- `snd_hda_intel power_save=1` (kernel default, no fleet drop-in) powers the codec down 1 s after
  idle and can clip the **start** of a clip on this codec. It cannot explain a whole silent track;
  do not chase it first, and do not raise it without the ear test above.
- Never flap the card profile to "test" this (`analog ↔ off ↔ hdmi`, as happened on 2026-09-06):
  it proves nothing the ELD and `pcm3p/status` do not already say, and the PTT sidecar owns the
  bluez card profile (`toolbox.md` §4).

## XM5 buds: "the digital assistant is not connected" (E24)
- Symptom: one tap on the right bud triggers the buds' own voice-assistant announcement and **nothing
  reaches the host** — no event on the grabbed `WF-1000XM5 (AVRCP)` node, nothing in `bluetoothd`, no D-Bus
  call. Reads as "the tap only works while a media app plays", because a reconnect happens to clear it.
- Cause: bud-side gesture state, not the host. The buds keep a phantom voice/call context after a mic close
  and re-route the right-bud gestures to their assistant. Marker in the journal, seconds after the last good
  mic close: `kernel: Bluetooth: hci0: SCO packet for unknown connection handle` + `bluetoothd: .../fd0: fd(N) ready`.
- Fix: case in and out, or `bluetoothctl disconnect $HARNESS_BUDS_MAC && sleep 5 && bluetoothctl connect …`.
  Both restore the taps within seconds; check the card lands back on `a2dp-sink`.
- Mechanism: PipeWire holds the (e)SCO for its whole suspend timeout after the recorder stops — **6.2 s
  measured** — and the old close path flipped the card back to A2DP on top of the live link. The cheap
  deterministic teardown is `pactl suspend-source <bluez_input…> 1`, which releases it in **1.09 s**.
- The sidecar now suspends the source, waits (bounded 4 s) for `hcitool con` to show no (e)SCO, falls back
  to disconnecting **only** the HFP profile (`org.bluez.Device1.DisconnectProfile`, Handsfree UUID — A2DP
  and the AVRCP node survive), and only then returns to A2DP; then watches 30 s. Verified at the audio
  layer (close 1.09-1.14 s, link down before the flip); **not yet verified with the owner's own taps**.
- **The kernel marker is the teardown's own echo, not a stuck link (E30).** A live mic open on this box is
  `< eSCO $HARNESS_BUDS_MAC handle 3584` — the *same* handle as every "SCO packet for unknown connection
  handle 3584" line (~35 of them on 2026-09-06, ~7-9 s after each close, working cycles either side). So
  the marker never justifies a recovery on its own: a bounce fired on it at 15:51:52 and cost the owner
  10 s of audio for a healthy link. A live (e)SCO in `hcitool con` is the only evidence worth acting on,
  and the sidecar now climbs a ladder — `suspend-source` → HFP-only DisconnectProfile+ConnectProfile →
  whole-device bounce — one step per 5 s poll, never while the mic is open or within 4 s of a tap.
- Ruled out with evidence (E24 in `~/the-dark-eye/RUNBOOK-earbuds.md`): registering a dummy
  `org.bluez.MediaPlayer1` AVRCP target, and a silent `pw-cat` keeping A2DP `RUNNING`. Neither made a single
  tap arrive. Also: a registered player would *take* the keys off evdev (BlueZ falls through to uinput only
  when no player is registered), so it is a rewrite of the sidecar's key path, not an addition.

## Screen captures while the owner is present
Every `pc shot` / gnome-screenshot is visible to the owner on the TV (he counted 20 during a parity check and asked why). The rule that follows from it is `KB/toolbox.md` §6 practice 2; renderer comparisons dump frames offscreen (cairo `write_to_png`, `glReadPixels`/FBO) from a seeded scene instead.

- **Hand-run eye-render hijacks the live eye** unless the socket is private (the bridge `sock` option alone is not enough; `net.createServer` accepts any number of clients). 2026-09-06 15:46: E29 made the production eye flap and vanish 3 s. **Do not type the recipe — run `body-sandbox`** (EF06); its subcommands, the mandatory `--x-offset -1400` and the scene names are in `KB/toolbox.md` §3. Sandbox processes carry `DARK_EYE_SANDBOX=<name>` and live under the sandbox dir, so `sentinel-runaway` rule 3 tells them from a hijack and still reaps one older than 2 h — `body-sandbox down` is the normal exit. Since TSP-016 (2026-09-21) rule 3 matches the body by argv[0] (Node >= 23 sets comm to `MainThread`) and, when `/proc/<pid>/environ` carries `DARK_EYE_SANDBOX=<name>`, runs `body-sandbox down --name <name>` once per name instead of killing one pid; processes inside `dark-eye.service`'s cgroup are never touched.

- **Sony WF-1000XM5 "digital assistant is not connected" on tap**: caused by the Sony app voice-assistant setting ("Asistente digital"), not by the host. Set it to "No utilizar". Verified 2026-09-06. Do not chase it host-side again; `buds-capture` shows the gesture is silent on the wire in that state.

- **dark-eye runs straight from the working tree**: any `systemctl --user restart dark-eye` while another agent is mid-edit ships a half-applied build (16:30 2026-09-06: empty transcripts). Before restarting, check no other agent is editing body/src (ask the orchestrator) and that `npm test` passes on the tree as it is.

- **PipeWire `log.level` — never raise it globally**: `pw-metadata -n settings 0 log.level 4` (E30, 2026-09-06) plus three wireplumber restarts while it was raised (E23) wrote 33 054 pipewire lines in 2 s and 13 711 wireplumber lines at 01:31 — 14 + 6 MB of that day's journal, doubled into `/var/log/syslog` by rsyslog (EF09). Level is back to 2.
- Debug one client instead: `PIPEWIRE_DEBUG="spa.bluez5*:4"` on that process's env, never the global `log.level`.
- If `log.level` must go up host-wide for a moment, wrap it in a `trap` that resets it to 2 within 10 s — a level left raised across a restart is what turned one burst into three. EF09's sentinel resets any level it finds above 2; this rule is for the human/agent side, not a substitute for it.
  `agent-preflight` reads the live level back with five other Dark-Eye facts in one screen
  (`KB/toolbox.md` §3) — run it first in any Dark-Eye session.

## PT01-PT16 (`pc` tools)
- **`/tmp` is tmpfs on this box**: a disk-IO test that writes there measures RAM, not disk. `pc io`'s and any other test's scratch files go under `$HOME` (or `$XDG_RUNTIME_DIR`, also tmpfs but the accepted one for sockets/caches) instead.
- **`busctl --json` cannot dump bluez `ManufacturerData`**: the property is `a{qv}` with a variant value that `busctl`'s JSON encoder does not serialise; `pc bt`/`pc dbus` read it with `get-property` on the specific key, never a blanket `GetManagedObjects --json` dump when that field is wanted.
- **BlueZ discovery is per-client**: `StartDiscovery`/`StopDiscovery` are scoped to the calling D-Bus connection, so two one-shot `busctl` calls cannot hold a scan window open (the second call's `StopDiscovery` answers "No discovery started"). `pc bt scan --seconds N` keeps one `bluetoothctl --timeout N scan on` connection alive for the whole window instead.
- **`systemctl show --value` ignores the property order given on the command line**: `systemctl show -p A,B --value unit` prints values in systemd's own property order, not `A,B`'s — never zip the two lists positionally; ask for one property per call, or use the (ordered) non-`--value` form and pick fields out by name.
- **`dmesg -J` ignores `--time-format`**: JSON output always carries raw monotonic/realtime microsecond fields regardless of `--time-format`; convert them in `jq`/python, don't pass `--time-format iso` expecting it to touch the JSON path.
- **python-evdev's `UInput` node lookup costs 1.9 s of a 2.3 s `pc input inject`**: it retries `/dev/input/event*` 19 times at 0.1 s on a node the calling user cannot open, before falling back. `UI_GET_SYSNAME` on the freshly created uinput fd gets the node name directly and skips the retry loop (PT10).
- **jq operator precedence in `a|b and c`**: `|` binds looser than expected next to `and`/`or`, so `.pci|length>5 and (...)` pipes `.pci` into the *entire* `and` expression, not just `length>5`. Parenthesise the piped side: `(.pci|length>5) and (...)` (found in `pc hw`'s own success-check line, PT07).
- **Parallel sandboxes collide on the default name.** 2026-09-14: a second ticket's `body-sandbox up` found `s1` already up, left `DARK_EYE_CONFIG` empty and its `eye speak` reached the live body; its unnamed `down` then killed the sibling's sandbox. When more than one agent may be running, always `body-sandbox up --name <ticket>` and `down --name <ticket>`. Guarded since M02b (2026-09-14): `down` refuses without `--name`/`--all`, an unnamed `up` is `sb-<pid>`, and `up` on a name already up prints `export DARK_EYE_CONFIG=/nonexistent; false` so the eval'd session cannot reach the live body.
