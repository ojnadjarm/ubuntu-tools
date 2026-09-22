# Toolbox — what this machine already has

Every agent reads this before building anything. If a line here answers your question, do not
re-derive it. Deeper detail: `~/agents/KB/machine.md`, `~/agents/KB/quirks.md`,
`~/agents/README-pc-control.md`, `~/agents/RUNNER.md`, `~/agents/FLEET.md`,
`~/the-dark-eye/RUNBOOK.md`.

## 0. Roles: user vs owner
- **The user** — whoever is talking to an agent right now (voice or terminal); use this noun in instruction files.
- **The owner** — the config role: whose `config.env`/ntfy topic this install belongs to, the target of `notify-owner`. Usually the same person as the user. Full definition: `FLEET.md` §0.

## 1. Hardware, displays, audio

- ASUS Vivobook X1503ZA · Intel i5-12500H, 16 threads · 37 GB RAM · Ubuntu 26.04.1, kernel 7.0.0-31.
- GPU: Intel Iris Xe (Alder Lake-P GT2), `0000:00:02.0` — no discrete GPU; EGL/Mesa, `LIBGL_ALWAYS_SOFTWARE=1` gives llvmpipe.
- Disk: `/dev/nvme0n1p2` 468 G on `/`, ~8 % used, SMART PASSED. Never a disk-space excuse.
- Session: Wayland, GNOME 50, keyboard layout `latam`. Always on AC; never suspends (lid ignored).
- Displays *as currently configured* (`gdctl show`): one logical monitor at (0,0) = **HDMI-1**, the
  Samsung 32" TV, **1366x768@59.79**. `eDP-1` (built-in, 1920x1080 preferred) is present but in no
  logical monitor. Screen coordinates are therefore 1366x768. **Never change monitor config without the owner.**
- Audio (PipeWire/WirePlumber): sinks are `alsa_output.pci-0000_00_1f.3.hdmi-stereo` (TV) and
  `bluez_output.<HARNESS_BUDS_MAC with _>.1` (Sony WF-1000XM5). Default sink = the earbuds.
- Network: LAN and Tailscale addresses are `HARNESS_LAN_IP` / `HARNESS_TAILNET_FQDN` in config.env and
  are printed in full by `machine.md`. ufw allows the tailnet and the LAN only; ports table in `machine.md`.

## 2. Machine state and control — the `pc` family

`pc` is `~/agents/bin/pc` (also `~/.local/bin/pc`); `~/agents/bin` is on PATH from `.bashrc`.
`pc help` lists commands, `pc <sub> -h` prints usage. Scripts run from systemd/cron must source
`~/agents/bin/env.sh` first (XDG_RUNTIME_DIR, WAYLAND_DISPLAY, DBUS_SESSION_BUS_ADDRESS, YDOTOOL_SOCKET).

| Group | Commands | Use |
|---|---|---|
| state | `pc status [--json\|--check\|--brief\|--facts] [--fresh]` | power, disk, docker, network, desktop, agents — read this instead of asking. Timings and the probe cache: `README-pc-control.md` "Machine state: `pc status`" |
| look (text) | `pc see [SEL]` (0.5 s), `pc tree [app] [--find N] [--role R] [--all]` (0.13 s; no app = the focused one, `--all` walks every registrant at 5 s), `pc win list\|focused\|focus\|move\|resize\|close\|wait\|verify` | AT-SPI names **and** real screen coordinates; the first thing to try |
| look (pixels) | `pc shot [out] [--scale F] [--region] [--diff] [--changed-only] [--quiet]`, `pc find "text"` | only when no text route answers; `--diff` says *what changed* without another Read |
| act | `pc click X Y`, `pc a11y-click "name"`, `pc click-text`, `pc move`, `pc drag`, `pc scroll`, `pc type`, `pc key`, `pc clip get\|set`, `pc open`, `pc notify` | one verified action at a time |
| wait | `pc wait-for --window\|--focus\|--text\|--gone SUB [--timeout S] [--see]`, `pc wait S` | never `sleep`; animations are off, windows appear at once |
| profile | `pc mode [agent\|human\|status]`, `pc selftest`, `pc spotify …` | agent mode = no animations, one workspace, no overview |
| kernel | `pc top`, `pc io`, `pc power`, `pc idle`, `pc thermal`, `pc trace`, `pc kernel`, `pc net`, `pc hw` | CPU/wake/IO, watts/RAPL/GPU, `pc idle` for the idle-power baseline (median package/psys watts, top wakers, fleet RSS; the weekly row lands in `bench/BASELINE-IDLE.tsv`), thermal zones, eBPF/perf one-liners, dmesg/sysctl/cgroups, sockets/tailscale/fw, PCI/USB/DMI — `pc mutter` replaces a screenshot for window/monitor geometry, `pc trace` replaces guessing who wakes the CPU or writes the disk |
| session | `pc dbus`, `pc mutter`, `pc input`, `pc audio`, `pc bt` | the session/system bus, compositor state (read-only), evdev, PipeWire, bluez |
| services | `pc units`, `pc journal`, `pc docker` | systemd units/timers, structured journal queries, compose stacks |
| safety | `pc undo`, `pc explain <thing>`, `pc bench`, `pc doctor` | the change ledger and rollback, ranked KB lookup (`pc explain` before opening `toolbox.md`/`quirks.md` whole), timing table, night-safe PASS/FAIL |

Full reference, one row per command with its usage and warm bench time: `~/agents/KB/pc-cli.md`
(generated — `pc help --md > ~/agents/KB/pc-cli.md`, never hand-edited). Every mutating verb is
read-only without `--apply`; the ledger, `pc undo` and the guard exits are in
`README-pc-control.md` "The ledger, `pc doctor`/`pc bench`, and `pc explain`".

- **Order of preference for finding things on screen:** `pc see`/`pc tree` → `pc a11y-click` →
  `pc win` → `pc click-text`/`pc find` (OCR) → coordinates read off a screenshot. Drop a level only
  when the one above finds nothing.
- Before driving any GUI at all, look for the non-GUI route: `gsettings`, `gdbus`, `gio`, `wpctl`,
  `pactl`, `playerctl`, `nmcli`, `systemctl`, `journalctl`, the app's own CLI.
- `pc type`/`pc key` exit 2 when focus is not the window you focused, or while a GTK4 in-window modal
  is up (`pc see` prints a `modal:` line; answer it with `pc a11y-click`). `--force` bypasses.
- `agents-log --pc [--since 24h]` prints your pixel:text ratio; `pc status --json` carries
  `pc_look_ratio_24h`. Target: one screenshot per task, not per step.

## 3. The Eye (`~/the-dark-eye`)

- `eye` = `~/.local/bin/eye` → `bridge/eye.sh`. `eye help`. Commands: `speak <text>`, `listen`,
  `listen-loop`, `mic [on|off]`, `status <id> working|done|error <label>`, `status` (list them),
  `show <title> <file|-> [--ask]`, `health`. **Orbiters are automatic**: the `SubagentStart` /
  `SubagentStop` hooks (`~/agents/bin/orbit-hook`) light one per subagent and put it out when it
  ends, and the body replays its persisted set on every renderer `ready` — never hand-send or
  refresh them for agents; `eye status <id> working` is only for a ticket you want on the eye.
  The `/eye` skill (in the agent CLI's skills dir) is how a session gets the owner's voice:
  `eye health`, then the **Monitor** tool running `eye listen-loop` persistently.
- **The TV going off is never detected — say it**: `eye tv off` blanks the eye (0 render ticks,
  ~21 points of gnome-shell back), `eye tv on` / `eye tv auto` bring it back, `eye tv` prints the
  mode and `eye health` carries it. Persisted across a restart. The Samsung keeps HPD, EDID and
  ELD up in standby, so no sysfs/DDC/ELD rung can see it (EF10, `KB/quirks.md`).
- Units: `dark-eye.service` (node `body/src/main.js` → bridge on 127.0.0.1:8642, forked voice worker,
  spawned `render/target/release/eye-render`), `dark-eye-ptt.service` (earbud push-to-talk sidecar),
  `dark-eye-failed.service` (pushes the owner). Logs: `journalctl --user -u dark-eye -f`.
- Render socket: `$XDG_RUNTIME_DIR/dark-eye/render.sock`, one JSON object per line; override with
  `DARK_EYE_RENDER_SOCK`. Env flags: `DARK_EYE_IDLE_FPS` (60 on the GPU, 30 in software),
  `DARK_EYE_STATS=1` (fps/ms lines), `DARK_EYE_DEBUG=1` (unredacted speech), `DARK_EYE_GPU`
  (`0` software, `1` force, unset = GPU), `DARK_EYE_GPU_FAIL_AFTER` (fallback test hook),
  `DARK_EYE_DDC`, `DARK_EYE_DDCUTIL`, `DARK_EYE_DISPLAY_SYSFS`, `DARK_EYE_PARITY_DIR`.
- **Backend, since G07 (2026-09-06): the GPU.** `eye-render` is one binary with two backends and
  draws through EGL + GL ES on the Iris Xe by default, falling back to its cairo software renderer
  by itself if EGL/GL fails at start or mid-run. Which one is live:
  `journalctl --user -u dark-eye -n 200 --no-pager | grep -E 'EGL|backend |eye up at'` →
  `[eye-render] backend gpu` and `eye up at 1010,372 (340x380) on HDMI-1 (gpu)`; the same word is
  the `backend` field of `ready`. Unit idle: **2.0 % of a core, 103 MB RSS / 48 PSS at 60 fps**
  (software was 3.3 % / 30 MB at 30). First frame `Started` → `eye up at`: **0.31 s**.
  Rollback, no rebuild: `systemctl --user edit dark-eye` → `[Service]` `Environment=DARK_EYE_GPU=0`
  → `systemctl --user restart dark-eye` (`systemctl --user revert dark-eye` undoes it).
  Full block: `RUNBOOK.md` "GPU backend"; design `~/the-dark-eye/PLAN-GPU.md`.
- **The page, phone and desktop (R04 2026-09-06, M11 · M12 2026-09-15)**:
  `https://$HARNESS_TAILNET_FQDN:8644/` — tap to talk into the same ear, replies come back on it
  (`eye speak --to remote`). Tailnet only via `tailscale serve`, loopback bind, login is the
  body's `secret`. **A turn survives a browser tab switch** (M11): the tab reads `● listening`
  while it records, the upload is counted off the worklet, the turn cap is 300 s / 10 MB, an
  iPhone's `mute` pauses instead of losing it, and a "keep visible" glyph puts the eye in a Document-PiP
  window where the browser has it. **Every Eye line has a ▶ glyph** (M12): the ring's bytes
  while they last, else the body says those words again **to the page only** — which is also how
  a reply waiting in audio notes mode is heard without a sound in the room. **Two modes, the
  Eye's own and global to every channel** (M14): `call` plays a reply as it arrives, `audio
  notes` leaves it waiting for his ▶ — `eye mode [call|notes]`, `eye health` carries it, and
  `eye quiet on|off` is the old name of the same thing. RUNBOOK.md "Remote (the page — phone and desktop)"; silent
  end-to-end: `bash ~/the-dark-eye/body/test/e2e-remote.sh` (needs the live `remotePort`; a
  sandbox drops it — drive the page with `remote.js` in-process on a loopback port instead).
- **A hand-run body or eye: `body-sandbox`, never the recipe by hand** (EF06,
  `body/scripts/body-sandbox` → `~/.local/bin/body-sandbox`). It is the only sanctioned way to run
  a second body or a bare `eye-render`; typing `DARK_EYE_RENDER_SOCK=`/`XDG_CONFIG_HOME=`/
  `node src/main.js` by hand is what hijacked the owner's eye on 2026-09-06 (E29).
  - `eval "$(body-sandbox up --name <ticket> --eye offscreen --stats --audio null)"` — a second body with its own
    config and port (8643+, **`remotePort` dropped**: never a second tailnet listener), its own
    `render.sock`, its own `orbiters.json`, its own state dir and its own `module-null-sink`, all
    under `$XDG_RUNTIME_DIR/dark-eye/sandbox/<name>/`. Up in **~0.2 s**; it exports
    `DARK_EYE_CONFIG` (so `eye health`/`eye speak` talk to the sandbox), `MEASURE_PIDS` and
    `BODY_PID`. `--eye off` runs a body with no renderer at all. Without `--name` the name is
    `sb-<pid>` (unique); a name already up fails and prints `export DARK_EYE_CONFIG=/nonexistent;
    false`, so an eval'd session cannot reach the live body by mistake.
  - **An agent's shell resets its environment between bash calls**, so the `eval` is gone on the
    next call and the next `eye speak` hits the **live** body — that is how a sentence was spoken
    in the owner's room on 2026-09-15. Re-`eval "$(body-sandbox env --name <n>)"` inside *every*
    bash call that touches the sandbox, or prefix each command with `DARK_EYE_CONFIG=…`.
  - `body-sandbox eye [--dump PNG --scene S] [--demo --busy] [--gpu 0|1] [--stats] [--seed N]
    [--seconds N]` — a bare `eye-render` on a dead socket, **always** the offset the script
    derives from RandR at launch; no caller-supplied `--x-offset` is accepted. `place()` puts the
    eye at `largest.x + largest.w - 356 + offset`, so a *fixed* offset is only offscreen on the
    output it was calibrated for: `-1400` was offscreen on the 1366-wide TV and put the eye at
    **x = 164 on the laptop panel with the TV off** (2026-09-15). The script now computes an
    offset that misses every output (1920 wide alone → -2244, x = -680). Its dead socket must be
    inside `$XDG_RUNTIME_DIR/dark-eye/sandbox` and `--dump` an absolute `*.png` there or under
    `/tmp` — an ambient `DARK_EYE_RENDER_SOCK` pointing at a note used to **delete that note**.
    Scenes the binary actually has: `caption`, `resolved`, `heard-caption`, `rings`, `agents`
    (there is no `idle` scene). `DARK_EYE_SEED=<n>` makes both backends draw the same frame.
  - `eval "$(body-sandbox restart --name <ticket>)"` — the same body again on the same dir, config,
    port and sink: `mode.json`, `active.json` and `state/` survive, which is how "this is read back
    on boot" is checked by hand (`eye mode notes` → `restart` → `eye mode` is still `notes`). `up`
    wipes the dir, so the same sequence with `up` loses it. Needs `--name`; non-zero if it is not up.
  - `body-sandbox status | logs [-f] | env | down --name N|--all` — `down` needs an explicit name
    (no shared default); `env`/`logs` need one unless a single sandbox exists. `down` kills by PID (node, then any
    surviving `eye-render`), unloads the sink it loaded, removes the dir and exits 1 if anything
    survived. Down in ~0.15 s. `up` and `eye` **exit 2** if the socket resolves to the live
    `render.sock`. Test: `bash ~/agents/bin/tests/run.sh` (or `body/test/body-sandbox.test.sh`);
    guards on a stub: `bridge/tests/body-sandbox-guards.test.sh`.
- **`agent-preflight` is the first command of every Dark-Eye agent** (`~/agents/bin`, **0.08–0.16 s**):
  unit state + `NRestarts` + backend + last `eye up at`, `eye health`, dirty-file count, any hand-run
  body outside the unit cgroup (sandboxes listed apart), the working orbiters, and hour/sink/buds/
  pipewire `log.level` — the six things every agent used to re-derive. It **exits 1 when the tree is
  dirty or a hand-run body is live**: do not restart. `--brief` prints the six lines only.
  - Backend parity: `cargo test parity` in `body/render` — surfaceless EGL FBO + `glReadPixels`,
    `Rng::seeded(0x2545F491)`, per-region PSNR, PNGs and an amplified diff in `DARK_EYE_PARITY_DIR`
    (default `target/parity/`). `LIBGL_ALWAYS_SOFTWARE=1` runs it on llvmpipe.
- Measurement: `body/scripts/measure.sh --state idle|speaking|mic|tvoff [--seconds N] [--append]` —
  CPU %/process, RSS/PSS, GPU busy, RC6, fps. `MEASURE_PIDS=<pids>` for a hand-run body,
  `MEASURE_PROC=<dir>` for fixtures. **`speaking` and `mic` refuse without `--allow-sound` — the owner
  may be asleep.** Same night rule for anything that makes noise or lights the TV.
- **Speak without interrupting**: the body holds speech while his mic is open (buds or phone)
  and for 1.5 s after, then says it in order; just `eye speak`. `eye health` shows `held`.

## 4. Audio and Bluetooth

- `pc spotify status|play|pause|toggle|next|prev|vol|seek|open|output|search|library|auth` — MPRIS for
  control, no pixels ever. Subcommands, the Web API setup and the client's quirks:
  `README-pc-control.md` "Spotify".
- Volume and sinks: `wpctl get-volume/set-volume/set-mute @DEFAULT_AUDIO_SINK@`, `pactl list short sinks`.
- The XM5 push-to-talk sidecar (`dark-eye-ptt.service`, `body/linux/ptt-earbuds.py`) **owns the bud
  profile**: it grabs the AVRCP evdev node exclusively, switches `a2dp-sink` ↔ `headset-head-unit`
  around the mic and restores the volume. WirePlumber is configured not to fight it
  (`bluetooth.autoswitch-to-headset-profile = false`). Do not switch the card profile by hand while it runs.
- One `pactl move-sink-input` pins **all** later `pw-cat` playback to that sink, and sinks must be
  targeted by name, never by index: `quirks.md` "PipeWire / WirePlumber stream memory (E23)".

## 5. Fleet and comms

- `notify-owner [-p low|default|high|urgent] [-t title] [-g tags] "msg"` → push to the phone (ntfy).
  Any agent may use it when its task needs the owner. When and how: `FLEET.md` §4; config, log and
  phone setup: `README-pc-control.md` "Owner notifications".
- Persistent agents: one folder per agent under `~/agents/<name>/`; every runner command
  (`agent-run`, `agent-now`, `agent-enable`, `agents-status`, `agents-stop`/`agents-start`) is in
  `~/agents/RUNNER.md`. Roster of record: `~/CLAUDE.md`. Owner-facing summary: `~/agents/README.md`.
- Logs and state: `agents-log [--since 24h] [--session ID] [--grep X] [--stats] [--pc]`,
  `~/agents/<name>/logs/`, `~/agents/<name>/REPORT.md`, status page
  http://$HARNESS_TAILNET_FQDN:19998, netdata :19999.
- `buds-capture [seconds] [--quiet]` — one command to freeze the failing state of the XM5 buds
  (btmon HCI trace + bluez/pulse/wireplumber/journal snapshot + the sidecar's evdev view) into
  `~/agents/log/buds-capture/<ts>/`, then print a decoded summary. Run it **before** any recovery.
- `buds-recover` — `bluetoothctl disconnect`/`connect` on the buds, reports what came back, then
  prints the case power-cycle instruction if the taps still fail. Destroys the failing state: capture first.
- Other helpers in `~/agents/bin`: `boot-check.sh` (post-boot OK/FAIL), `lockcheck.sh` (always-on desktop),
  `baseline.sh` (config tarball before changing user config), `maintenance-run`, `moodle-keep`,
  `pcbench-weekly` (Sunday 02:00 A/B run, gated on `pcbench away` — never starts while the owner
  is at the machine; `pcbench-weekly --dry-run` prints the verdict),
  `moodle-envs` (list Moodle envs), `moodle-login-check`, `power-profile-auto`, `sentinel-check`,
  `sentinel-runaway` (runaway-process killer, called by `sentinel-check`; `--dry-run` to preview),
  `playwright-mcp` (headless unless `PW_HEADED=1`, `PW_PROFILE=<name>`).
- Skills: `/desktop` (pc), `/browser` + `/moodle-web` (Playwright MCP), `/eye`, `/moodle-ci`,
  `/moodle-docs` (offline moodledev.io mirror — never web-fetch it), `/moodle-guidelines`,
  `/moodle-install`, `/moodle-pluginskel`, `/set-moodle-harness`, `/i-have-adhd`.

## 6. Practices

1. **Research first.** Existing package, CLI or MCP server before writing one; state what exists, what
   you chose and why in three lines.
2. **Prefer the purpose-built tool.** `pc tree`/`pc see`/`pc a11y-click`/`pc win list`, MPRIS, `pactl`,
   `gsettings`, journals, offscreen frame dumps. A screenshot is legitimate when no such tool answers
   the question — rendering, layout, an app with no accessible tree — but never as the first resort and
   never in loops. The owner sees every `pc shot` on the TV.
3. **One verified action.** Act, then read back: `pc status`/`pc see`/`pc wait-for … --see`, an exit
   code, a file check. Report only what you verified.
4. **Never ask the owner what a sensor can answer.** `pc status`, `gdctl show`, `pactl`, `systemctl`,
   `journalctl` first; the KB second; the owner last.
5. **Announce before acting on the desktop**, and respect the night: nothing that makes sound, speaks or
   lights the TV without the owner's go-ahead (`--allow-sound` exists for exactly this).
6. **Kill by PID, never `killall`/`pkill -f` on a shared binary** (electron, node) — production units
   share it; `killall electron` also kills the production `dark-eye.service`.
7. **Never `git commit` or `git push` in a user repo.** Exceptions: `etckeeper` on `/etc`, `moodle-keep`'s
   weekly ff-only pull. Full forbidden list: `~/agents/FLEET.md` §5.
8. **Moodle work ends with `/moodle-ci`.** Envs are `~/moodle-envs/<ver>` (5.2 on :8052, admin/Admin1234!).
9. **Leave no residue.** Before reporting: hand-run processes killed by PID, temporary null sinks unloaded
   (`pactl unload-module`), test sockets under `$XDG_RUNTIME_DIR/dark-eye/` removed, downloads/profiler
   data/scratch profiles deleted from the scratchpad, screenshots not needed as evidence deleted. Evidence
   PNGs go next to the ticket and stay small. Check: `pgrep -a eye-render pw-cat`, `pactl list modules short | grep null`.
10. **The sentinel catches what you miss (EF03).** `sentinel-runaway` (called by `sentinel-check`
    every 15 min) kills or restarts by PID only, never `pkill -f`, and never touches the
    orchestrator tmux session, `dark-eye.service`'s own cgroup, or anything younger than its rule's
    threshold: (1) a `bash`/`sh` loop under a scratchpad, > 60 min → killed; (2) a
    `journalctl -f`/`tail -f`/`btmon`/`pw-cat -r` with no reader on its stdout, > 30 min →
    killed; (3) a hand-run `eye-render`/`node .../src/main.js` outside `dark-eye.service`'s
    cgroup, > 2 h → killed; (4) `xdg-desktop-portal*`/`gsd-*`/`gjs` at ≥ 90% CPU for 30 min or
    > 300 MB RSS → `systemctl --user restart`, pushed only if it repeats within 24 h; (5) a
    scratchpad whose owning agent process is gone, > 24 h old → `rm -rf`. It reads `/proc`
    directly in one pass (no `ps`/`awk` fork per process) to stay under 0.3 s CPU on a quiet box.
11. **Mutate through `--apply`, undo through `pc undo`.** Use the `rollback: pc undo <id>` line the
    command prints, don't hand-reconstruct the rollback (`README-pc-control.md` "The ledger").
    `pc explain <thing>` before opening `toolbox.md`/`quirks.md` whole for a fact this KB answers.
12. **`pcbench`: `pcbench run --set night`, read `BASELINE-PCBENCH.md` before claiming the
    agents got better.** `~/agents/bin/pcbench` runs a task pack against an old/new toolbox
    arm and scores the trajectory; results and the report of record live under
    `~/agents/bench/` (`BASELINE-PCBENCH.md`, `LAST.json`, `runs/<ts>/rows.jsonl`). Never quote
    a pass rate or a delta that isn't in `rows.jsonl` — read the file, don't estimate.
