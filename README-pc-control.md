# PC control cheat sheet (Ubuntu 26.04, GNOME 50, **Wayland**)

## Desktop control: the `pc` CLI (T07)
- **One entry point: `pc <sub>` (`~/agents/bin/pc`, on PATH via `~/.local/bin/pc`). `pc help` lists the subcommands, `pc <sub> -h` prints its usage.**
- One row per subcommand, with its usage and warm bench time, is generated into `~/agents/KB/pc-cli.md`
  (`pc help --md`, never hand-edited); the by-group index is `~/agents/KB/toolbox.md` §2. `pc selftest` is
  the PASS/FAIL end-to-end run (~20 s, opens the calculator).
- **Rule 0: text before pixels (T28a).** The non-GUI route first (`KB/toolbox.md` §2), then the loop
  **`pc see` → act → `pc wait-for … --see`**; `pc shot` only when `ui:` reports no accessible tree, when
  rendering or layout itself is the question, or when the tree gives no coordinates. Keep `--scale 0.5`
  for the screenshots you do take. `pc see`'s `ui:` reads text fields and document bodies through the AT-SPI Text
  interface (first 120 chars per node), which OCR drops whole lines of (QA D4/D12). The preference order for
  *finding* something on screen is one list, in `KB/toolbox.md` §2.
- Skill for agents: `~/agents/skills/desktop/SKILL.md` (see-act-verify loop, `pc` vs Playwright), symlinked into the agent CLI's skills dir by `adapters/$HARNESS_AGENT/install`.
- Mechanisms behind the subcommands (unchanged): portal screenshot `bin/portal_shot.py`; ydotool for pointer and key chords
  (absolute move needs mouse accel flat); mutter `org.gnome.Mutter.RemoteDesktop` keysyms for `type` (layout-independent — the
  layout here is `latam`, so `ydotool type` mistypes symbols); `wl-copy`/`wl-paste` for the clipboard.
- `screenshot.sh` is a thin deprecated wrapper around `pc shot`; use `pc` in new code. The `click.sh`/`type.sh`/`key.sh` wrappers were deleted in GH21 — nothing called them.
- Proven loop: gnome-calculator 7 + 8 = -> "15" both by typing and by clicking; Chrome omnibox typed URL + Enter -> page loaded.

## The ledger, `pc doctor`/`pc bench`, and `pc explain` (PT01/PT15/PT16)
- `pc` now also reaches the kernel/hardware, session-bus and services layers (`pc top|io|power|
  thermal|trace|kernel|net|hw`, `pc dbus|mutter|input|audio|bt`, `pc units|journal|docker`) —
  every command's usage, description and warm bench time is generated into
  `~/agents/KB/pc-cli.md` (`pc help --md > ~/agents/KB/pc-cli.md`, never hand-edited); look
  there, or ask `pc explain <thing>`, before re-deriving a fact this KB already has.
- **Every mutating verb is read-only by default.** Without `--apply` it prints `would: <before>
  → <after>` and exits 0; with `--apply` the change is recorded before and after in
  `~/agents/log/changes.jsonl` and the last line printed is `rollback: pc undo <id>`. `pc undo
  list [-n N]` / `pc undo show <id>` read the ledger back; `pc undo <id>|--last [--apply]`
  replays the inverse and is itself ledgered. A guarded verb (FLEET §5 — monitor config, power
  state, sshd/ufw/tailscaled, the tmux session `$ORCHESTRATOR_TMUX_SESSION`, `dark-eye.service`, fan control) exits
  3 with the refusal reason, `--apply` or not. `pc undo ack <id> --why "<reason>"` appends a note
  that a known, resolved unverified entry is a non-issue, without touching the original lines, so
  `pc doctor`'s ledger check stops failing on it.
- `pc doctor [--quick] [--json]` is the night-safe PASS/FAIL sweep of the whole family — no
  window, no sound, no TV, nothing restarted, ≤ 10 s full / ≤ 2 s `--quick`; `pc selftest` is
  still the one that drives gnome-calculator. `pc bench [--cold] [--runs N] [--save] [--compare]`
  measures every read-only subcommand and rewrites the table in
  `~/agents/bin/tests/BASELINE-PCTOOLS.md`.
- A script's own flags ride through `pclib.sh`'s `pc_opt` alongside `--json`/`--apply`/`--fresh`/
  `--seconds`: declare `PC_EXTRA_FLAGS=(--deep --level:)` first (a trailing `:` means the flag
  takes a value) and read them back from `PC_EXTRA[]`; anything undeclared exits 2.
- Not to be confused with `pc bench` above: `~/agents/bin/pcbench` (PB, its own family) is the
  old-toolbox-vs-new-toolbox A/B harness for agents, not a `pc` subcommand — `pcbench run --set
  night`, report of record `~/agents/bench/BASELINE-PCBENCH.md`.

## Window management (T08)
- `pc win list|focused|focus|move|resize|close|minimize|maximize|wait` — see `~/agents/skills/desktop/SKILL.md`.
  `<sel>` = window id or a case-insensitive substring of the title or `wm_class`.
- Backed by the GNOME extension **`window-calls@domandoman.xyz`** (v21, `shell-version` includes 50), D-Bus
  `org.gnome.Shell.Extensions.Windows` on `/org/gnome/Shell/Extensions/Windows`. `List` has no geometry; `pc win`
  merges `Details` per window for x/y/width/height.
- **Installing a Shell extension live on Wayland:** `gnome-extensions install` copies the files but the running
  shell never scans the directory, so `gnome-extensions enable` says "does not exist" and `ReloadExtension` is
  deprecated/dead in GNOME 50. What works without a logout: `gdbus call --session --dest org.gnome.Shell
  --object-path /org/gnome/Shell --method org.gnome.Shell.Extensions.InstallRemoteExtension "<uuid>"` — it pops an
  "Install Extension" dialog (confirm with `pc click` on Install) and then loads *and* enables the extension live.
- `pc win focus`/`pc win wait` click just inside the window's bottom edge after `Activate` (`--no-click` skips it):
  a window that does not take keyboard focus on map is reported focused by the shell while every keystroke is
  dropped, and only a click inside it grants real Wayland keyboard focus. The id is recorded in
  `$XDG_RUNTIME_DIR/pc-focus-window`; `pc win verify` (and so `pc type`/`pc key`) exits non-zero when nothing is
  focused or when another window took focus since. `--force` bypasses the guard.
- `pc click`/`move`/`drag` reject non-integer or off-screen coordinates with exit 2 (screen size from `xrandr`),
  so a bad coordinate can no longer land on the top-left hot corner and open the Activities overview.
- Extension zips: `https://extensions.gnome.org/extension-query/?search=<name>` gives the `shell_version_map`
  (pk = version_tag) and `https://extensions.gnome.org/download-extension/<uuid>.shell-extension.zip?version_tag=<pk>`
  the file. The project's GitHub releases 404.

## Findings (GNOME 50 Wayland)
- ydotool pointer/keys DO reach every window (Chrome included). The earlier "click did nothing" was libinput pointer acceleration: ydotool
  has no ABS axes, `--absolute` is emulated with relative moves and the default accel profile made them land elsewhere.
  Fix applied: `gsettings set org.gnome.desktop.peripherals.mouse accel-profile 'flat'` (speed 0.0) -> 1:1 mapping. Keep it.
- `pc shot --diff [PREV]` answers "did anything change, and where": it compares with the previous capture to the
  same path (kept as `<out>.prev.png`), masks `--ignore X,Y,W,H` (default the top bar `0,0,1366,32`) and prints
  `unchanged` or `changed bbox=X,Y,W,H`; `--changed-only` writes just that crop, `--quiet` prints only the verdict.
  Every `pc shot` now prints `path WxH NKB` so the agent sees the Read it is about to pay for.
- Screenshots: `org.gnome.Shell.Screenshot` -> AccessDenied even on the session bus (only whitelisted callers); `gnome-screenshot -f` broken;
  `grim`/`scrot` no. Portal `org.freedesktop.portal.Screenshot.Screenshot` works non-interactively (see `bin/portal_shot.py`). Fallback: `pc key shift+Print` -> newest file in ~/Pictures/Screenshots.
- `pc open <url>` goes through `xdg-open` -> the default browser (Chrome) with no flags, so the owner's real profile can pop
  a "Choose password for new keyring" or "Choose your search engine" dialog on top of the page. Always `pc shot` and read it
  before acting; dismiss with `pc click` on Cancel. Flag-controlled launches (`--password-store=basic`) need `google-chrome` directly, not `pc open`.
- The owner's Chrome profile has answered the EU "Choose your search engine" prompt (Google), and
  `/etc/opt/chrome/policies/managed/default-search.json` pins the default search provider by policy so it cannot
  come back (visible in `chrome://policy`). The GNOME keyring prompt still appears on a cold Chrome start — dismiss
  it with Cancel.
- Chrome first run: create the profile dir with an empty `First Run` file and launch with `--no-first-run --no-default-browser-check`
  -> no "Additional Terms of Service" dialog (verified with a fresh `--user-data-dir`). Add `--password-store=basic` or GNOME asks to create a keyring.
- The mutter RemoteDesktop D-Bus API also accepts pointer input (`NotifyPointerMotionRelative`, absolute needs a ScreenCast stream) with no permission prompt; `NotifyKeyboardKeycode` did not act as Enter, so `pc type` uses ydotool for Enter/Tab.
- No need to switch to Xorg; Wayland does not block injection here.

## Owner notifications (`notify-owner`)
- `notify-owner [-p low|default|high|urgent] [-t title] [-g tags] "message"` -> push to the owner's phone via ntfy. Exit 0 = delivered.
  Works from any script, systemd timer or `agent-run`; no agent session needed.
- Config: `~/agents/secrets/ntfy.env` (`NTFY_URL`, `NTFY_TOPIC`), mode 600 in a 700 dir. **Secrets live in `~/agents/secrets`; never echo, log or push them.**
  The topic *is* the password of the channel (public ntfy.sh server): keep pushes under ~200 chars, no credentials, no tokens. Long content -> Gmail MCP or a local file path.
- Every send is appended to `~/agents/log/notify.log` (`timestamp<TAB>ok|fail<TAB>priority<TAB>message`).
- Phone setup: install the **ntfy** app (Android: Play Store / F-Droid; iOS: App Store), keep the default server `https://ntfy.sh`,
  add a subscription with the topic from `~/agents/secrets/ntfy.env`, allow notifications. Test: `notify-owner -t test "hello"`.

## Always-on desktop (T02)
- Lock/blank/idle are off (`screensaver lock-enabled|idle-activation-enabled false`, `session idle-delay 0`, `lockdown disable-lock-screen true`, `power idle-dim false`), persisted as system defaults in `/etc/dconf/db/local.d/00-agents` (+ `/etc/dconf/profile/user`).
- `~/agents/bin/lockcheck.sh` prints `OK` when every key holds and the screensaver is inactive; if it ever reports active, `gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.SetActive false`.

## Agent-first desktop profile (T28c)
- `pc mode [agent|human|status]` (default `status`; prints `agent`/`human`/`mixed`, exit 1 on mixed). State file:
  `~/agents/state/pc-mode`. `pc see` prints a `mode:` line and `overview: active` only when the overview is up;
  `pc status --brief`/`--json` carry `mode=`; `boot-check.sh` closes the overview and checks the mode.

  | schema | key | agent | human (stock) |
  |---|---|---|---|
  | `org.gnome.desktop.interface` | `enable-animations` | `false` | `true` |
  | `com.ubuntu.update-notifier` | `no-show-notifications` | `true` | `false` |
  | `com.ubuntu.update-notifier` | `regular-auto-launch-interval` | `0` | `7` |
  | `org.gnome.mutter` | `dynamic-workspaces` | `false` | `true` |
  | `org.gnome.desktop.wm.preferences` | `num-workspaces` | `1` | `4` |

  Plus: the `tiling-assistant@ubuntu.com` extension is disabled in agent mode, and `OverviewActive` is set `false`
  (the read-write `org.gnome.Shell` D-Bus property; GNOME opens the overview after every login and it swallows the
  first click). The agent values are system defaults in `/etc/dconf/db/local.d/10-agent-mode` (no locks), so
  `pc mode agent` is a `gsettings reset` and `pc mode human` a user-level `gsettings set` that survives a re-login.
- **Never change monitor settings without the owner** (`KB/quirks.md` "Agent-first desktop profile"); every
  desktop-profile change below is gsettings/dconf, never a monitor change.
- **Keyring pre-answered:** `~/.local/share/keyrings/{Default_keyring.keyring,default}` is a **plaintext** default
  keyring (`lock-on-idle=false`, `lock-after=false`), so Chrome never shows "Choose password for new keyring".
  Owner-approved 2026-09-05: passwords Chrome saves are unencrypted on an already unencrypted disk, nobody else has
  physical access. Rollback: delete both files and restart `gnome-keyring-daemon.service`.

## Clipboard / notifications
- `wl-copy < file`, `wl-paste` (Wayland); `xclip` only for Xwayland apps. `notify-send "title" "body"`

## Volume (PipeWire)
- `wpctl get-volume @DEFAULT_AUDIO_SINK@`; `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5` / `5%+` / `5%-`; `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle`
- `pactl list short sinks`; `playerctl play-pause|next|status` (MPRIS players: vlc, chrome, mpv with --input-ipc or mpv-mpris)

## Media
- `mpv --no-terminal file_or_url &` (yt-dlp integrated: `mpv "https://youtube.com/..."`); audio only: `mpv --no-video url`
- `yt-dlp -f best -o ~/Videos/%(title)s.%(ext)s URL`; `vlc file`; `ffmpeg -i in.mp4 out.mp3`

## Spotify (T-spotify, `pc spotify`)
- **Never screenshot Spotify.** The snap (1.2.95) is Electron with no AT-SPI tree, so `pc tree`/`pc see` show
  nothing; every fact and every action is available without pixels through `pc spotify`.
- `pc spotify status [--json] | play | pause | toggle | next | prev | vol <0-100> | seek <s|+s|-s> |
  open <uri|url> | output [earbuds|speakers|tv|<sink>] | search <q> | library | auth`.
- Control and status are MPRIS (`playerctl -p spotify`, `dbus-send --dest=org.mpris.MediaPlayer2.spotify`);
  `vol` maps onto the stream volume, `output` is `pactl move-sink-input <spotify-input> <sink>` (aliases:
  `earbuds` → `bluez_output*`, `speakers` → `*analog*`, `tv` → `*hdmi*`; the HDMI sink only exists while the TV
  is connected).
- **`OpenUri` and `LoadContextUri` are no-ops in this client** (verified on 1.2.95: both return without changing
  the track), and so is `spotify --uri=…` / `xdg-open spotify:…` beyond navigating the UI. Starting a *specific*
  track/playlist therefore needs the Web API (`PUT /me/player/play` on the desktop Connect device), which
  `pc spotify open` uses when credentials exist.
- Web API (`search`, `library`, and playback start in `open`): needs `~/agents/secrets/spotify.env` with
  `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET` from https://developer.spotify.com/dashboard (redirect URI
  `http://127.0.0.1:8899/callback`), then a one-time `pc spotify auth` **run by the owner** (it opens a browser).
  Tokens land 0600 in `~/agents/secrets/spotify-token.json` and refresh themselves. Without the file those
  subcommands print the setup steps and exit 2. Helper: `~/agents/bin/spotify_api.py`.
- Web API quirks: `me/playlists` items carry the track count in `items.total`, **not** `tracks.total`, and some
  entries come back null; `me/player/recently-played` needs a scope the token does not have (403). A
  `PUT /me/player/play` with a `context_uri` can load the context and leave the app paused, so `pc spotify open`
  polls MPRIS and nudges `playerctl play` until `status` reads Playing (it exits 1 if it never does).
- Rejected alternatives: `spotify_player`/`ncspot` (they register their own librespot device and need a separate
  client id, so the logged-in desktop app stops being the player), `spotify-tui` (archived), Spotify MCP servers
  (same Web API credentials, much more weight).

## Browser
- Google Chrome: `google-chrome --new-window URL &`; Playwright chromium in `~/.cache/ms-playwright/`
- MCP: `playwright` (user scope) -> tools `browser_navigate`, `browser_click`, `browser_snapshot`,
  `browser_take_screenshot`; the wrapper, profiles and the session-cookie gotcha are in `KB/quirks.md` "Playwright MCP (T12)".

## Machine state: `pc status` (T21/T24, sped up in EF04, cadence-matched in EF09)
- `pc status [--json|--check|--brief|--facts] [--fresh]`. Warm (900 s caches populated) **0.11 s /
  59 execs**; `--fresh` (every probe cold) **0.71 s / 129 execs**; before EF04 it was **1.6 s / 248
  execs**; the EF09 baseline right after EF04, at a 15-min tick cadence where every probe was
  cold every time, was **1.70 s wall / 0.95 s CPU / 199 execs**.
- The slow probes are cached as *parsed* values in `$XDG_RUNTIME_DIR/pc-status/` (one file per probe, first
  line = epoch), written with a direct redirection (no `mv`, EF09). TTLs: 60 s for anything the sentinel
  repairs — docker, tailscale, the power profile — **900 s (the sentinel's own tick cadence, EF09)** for
  what it only reads — wifi, lock, `pc mode`, the screenshot probe, background agent runs — 1 h for SMART and
  DNS, 24 h for the compose-file service counts. **`--fresh` bypasses every entry**; a reboot clears them
  all.
- `sentinel-check` therefore now warms the 900 s caches on its first tick and reads them straight back on
  the following ones (its own `Consumed` dropped from ~1-3 s to ~0.26-0.28 s CPU, EF09), and still does the
  **re-check after a repair with `--fresh`**, so a cached `docker`/`tailscale` value can never hide the fix.
- EF09: the wifi probe reads the connected wifi device's state (`nmcli -t -f
  DEVICE,TYPE,STATE,CONNECTION dev status`) instead of `nmcli dev wifi`, which needs an AP rescan
  (was 4.68 s of wall time every cold tick) to list the active SSID — `--rescan no` alone does not
  fix this, the AP-list command just doesn't reliably carry the active connection's SSID without a
  scan. The screenshot probe no longer takes a real screenshot in the health-check path at all — a
  `busctl` call to the portal's `Screenshot` interface stands in (still FAILs if the portal is
  dead), even under `--fresh`, because a real screenshot cost 0.81 s wall and ~15 `python3` forks
  for a value that rarely regresses. `lockcheck.sh`/`pc-mode` are sourced instead of exec'd from
  `pc-status`, and each folds its own `gsettings get` calls into one `gsettings
  list-recursively` per schema (was 14 individual `get`s across both scripts, now 8 recursive
  reads).
- Output is byte-identical to the pre-EF04 version in every mode (text, `--brief`, `--check`, `--json`,
  `--facts`); only the genuinely volatile values move between runs.

## System monitoring
- `htop`, `btop`, `ncdu /`, `sensors`, `sudo iotop -o`, `sudo nethogs`, `lsof -i`, `inotifywait -m dir`, `killall name`

## Rollback
- `/etc` is a git repo (etckeeper); apt hooks auto-commit around every package install. Before editing `/etc`: `sudo etckeeper commit "pre T<NN>"`; undo with `cd /etc && sudo git diff` / `sudo git checkout -- <file>`.
- `~/agents/bin/baseline.sh` -> timestamped tarball of `$HARNESS_CONTEXT_DIR/{settings.json,hooks,skills,*.md}`, `~/agents/bin`, `~/CLAUDE.md` and `dconf.ini` in `~/agents/backups/` (last 20 kept). Run it before changing user config.
- Restore: `tar xzf ~/agents/backups/<date>.tar.gz -C ~` (dconf: `dconf load / < dconf.ini`).

## After reboot (T03)
- `~/agents/bin/boot-check.sh` -> one OK/FAIL line per item (docker stacks, Moodle HTTP, the orchestrator tmux session, linger, tailscale, ssh, ydotoold); exit 1 on any FAIL. Run it first after every boot.
- Docker stacks come back on their own: every service in `~/moodle-envs/{shared,5.2}/docker-compose.yml` has `restart: unless-stopped` (the `/moodle-install` generator writes it for new envs too).
- `loginctl enable-linger $USER` is on, so systemd **user** units and timers run without a graphical login.
- Orchestrator: `systemctl --user enable $ORCHESTRATOR_UNIT` is done but the service is NOT started, because the owner's orchestrator `tmux` session is already running. It starts at the next boot (`tmux has-session -t $ORCHESTRATOR_TMUX_SESSION || tmux new-session -d -s $ORCHESTRATOR_TMUX_SESSION '<agent CLI> --remote-control $HARNESS_HOST'`: the has-session guard makes it a no-op when a session already exists). To hand the running session over without rebooting: exit the tmux session, then `systemctl --user start $ORCHESTRATOR_UNIT`.
- `docker` needs no socket ACL after a reboot: the user is in the `docker` group; only shells started before the group was added (the current ones) rely on the ACL on `/var/run/docker.sock`.
- Reboot test is still pending — nothing here was proven across an actual reboot (left for Phase 0 QA / T23).

## Accessibility tree (T10)
- `gsettings org.gnome.desktop.interface toolkit-accessibility` is `true` and is also a system default in
  `/etc/dconf/db/local.d/00-agents`. Rollback: `gsettings reset` + drop that stanza and `sudo dconf update`.
- `pc tree [app] [--depth N] [--json] [--max N] [--all] [--find "name" [--role R]]` walks AT-SPI via
  `~/agents/bin/a11y_tree.py` (python3-gi + `gir1.2-atspi-2.0`); `pc a11y-click "name"` finds and activates.
- **`pc tree` with no app walks the focused application only** (EF04): it prints the window list, one
  `application "<name>"` line per registrant — so `pc tree | grep ^application` still lists them — and the tree
  of the focused app, then names the ones it skipped. `--all` restores the old full walk. gnome-shell alone is
  ~750 nodes and ~7 D-Bus round trips per node, so the full walk costs **5.0 s** against **0.13 s** scoped; the
  wait is the walk itself, not a dead registrant (`PC_TRACE=1 pc tree` prints per-registrant probe and walk times).
- **GTK4 on Wayland returns `0,0` only for `CoordType.SCREEN`; `CoordType.WINDOW` extents are correct.**
  `a11y_tree.py` resolves each AT-SPI frame to its window (frame name == window title, else the focused window),
  reads the origin from window-calls `GetFrameRect`, and adds it — so `pc tree` and `pc tree --find` print real
  screen coordinates for every toolkit (calculator `7` → `592 584`, and the values follow `pc win move`). A frame
  wider/taller than `GetFrameRect` carries CSD shadows: half the difference is subtracted from x and y.
  `GetFrameBounds` throws (`get_frame_bounds is not a function`) — do not use it. `pc a11y-click` keeps the
  `Atspi.Action.do_action(0)` fallback for nodes without coordinates.
- **The Windows interface has no signals**, so `pc wait-for` polls every 250 ms (`List` costs 0.09 s) instead of
  running an AT-SPI event loop. `org.freedesktop.Notifications` has no history API either; `pc see` reads the
  visible banner out of the gnome-shell a11y tree (hidden nodes report `INT_MIN` extents and are pruned).
- Role names in this libatspi are `button`/`toggle button`, **not** the classic `push button` (the T10 success
  check's `grep -c "push button"` therefore counts 0; grep `button` instead).
- Chrome exposes its tree only with `--force-renderer-accessibility`, applied through a desktop-file
  override — the whole story, including what does not work, is `KB/quirks.md` "Chrome accessibility tree (T28b)".
- `pc tree <sub>` exits 1 when the substring matches no AT-SPI application; the a11y application name is not the
  `pc win` selector (`gnome-text-editor` vs `org.gnome.TextEditor`).

## Finding text on screen (T09)
- `pc find "text" [--all] [--region X,Y,W,H] [--json] [--shot FILE]` -> centre `X Y` of the best OCR match, exit 1 if absent (~1.2 s).
  `pc click-text "text" [--index N] [--region ...] [left|right|middle] [--double]` = find + click, prints where it clicked.
- Engine: `tesseract` 5.5 (`tesseract-ocr`, `-eng`, `-spa`; no pytesseract package on 26.04, the CLI TSV output is parsed directly by `bin/ocr_find.py`).
- What made it work on this dark theme: **binarize, do not just invert**. The screen is upscaled 2x, thresholded at L=150 into both
  polarities (dark-on-light and its inverse) and each is run through psm 6 and psm 11. Plain inversion of the greyscale finds almost nothing.
- Lone symbols on big buttons (the calculator `=`) are dropped by every page-segmentation mode. Second stage for queries of <=3 chars:
  8x8-block connected components of the ink mask -> each small isolated cluster is OCR'd with psm 10/7. Adds ~0.9 s, only for short queries.
- Ranking: fuzzy ratio, then confidence bucketed to 5, then glyph area - so a button label wins over a smaller look-alike icon
  (a GNOME hamburger menu reads as `=`, and so does the calculator icon in the dock). Use `--all --json` + `--index N` when it matters.
- Dash/underscore normalisation: `— – ― ‒ − _` all fold to `-` and `=` folds to `--` before matching, because tesseract renders `=` as `—_` at some scales.
- `pc selftest` now includes a `find "7"` check on the calculator.
- Five OCR passes: binarized light/dark through psm 6 and psm 11, plus the plain upscaled greyscale through psm 6 —
  binarizing distorts document text (`alpha` came back as `aloha`), the greyscale pass reads it correctly.
- `pc find` cleans up its own temp screenshot (its EXIT trap only runs because the script no longer `exec`s python).
