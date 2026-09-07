# T28c — Agent-first desktop profile: `pc mode agent|human`, deterministic layout, pre-answered dialogs

**Phase 1 · should · Model: opus · Estimated agent time: 75 min · After T28a**

## Goal
The GNOME session behaves predictably for agents (no animations, no overview stealing the first click, no tooltip/tiling/update surprises, windows placed and sized the same way every time, no keyring or first-run prompts) and stays usable by the owner when he sits down or watches the TV; one command `pc mode agent|human` switches the profile and `pc status` reports which one is active.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/quirks.md`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4), tickets T02 (always-on dconf profile) and T28a (`pc see`). Run `pc status` first; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. `~/agents/bin/baseline.sh` before touching `~/agents/bin`; `sudo etckeeper commit "pre T28c"` before any `/etc` change.
- **Never call `org.gnome.Mutter.DisplayConfig` or change monitor settings**: the TV (`HDMI-1`) is currently the only logical monitor (lid closed, `eDP-1` off) and the mirror must not change. Everything in this ticket is gsettings / dconf / files under `~`.
- The owner is watching: open only gnome-calculator / gnome-text-editor for tests and close them.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken — including the keyring decision (step 3), which the owner must confirm.

## Context / pointers (inspected 2026-09-05)
- Already agent-friendly and **left alone**: `enable-hot-corners false`, `center-new-windows true`, `auto-maximize true`, `attach-modal-dialogs true`, `edge-tiling false`, `focus-new-windows smart`, `night-light false`, `color-scheme prefer-dark` (OCR was tuned on it), `show-banners true` (banners are read by `pc see`). T02's always-on keys live in `/etc/dconf/db/local.d/00-agents` and apply to **both** modes — never reset them.
- To change in agent mode: `org.gnome.desktop.interface enable-animations false` (windows appear at once; the 2–3 s "give the UI time" rule shrinks), `com.ubuntu.update-notifier no-show-notifications true` + `regular-auto-launch-interval 0` (`update-notifier` is running now and pops a GUI updater; T23 owns updates), disable the `tiling-assistant@ubuntu.com` extension (tiling popups on window moves/keys; `gnome-extensions disable` works live), `org.gnome.mutter dynamic-workspaces false` + `org.gnome.desktop.wm.preferences num-workspaces 1` (one workspace, so every window `pc win list` shows is on screen). Tooltips have no GNOME switch; instead `pc win list` must hide surfaces with no wm_class/title (tooltips, popups, quirks.md "cosmetics") unless `--all`.
- Overview: `org.gnome.Shell` exposes the **read-write** D-Bus property `OverviewActive` on `/org/gnome/Shell`; GNOME opens the overview after every login (autologin included), which swallows the first click. `pc mode agent` sets it `false`; `pc see` prints `overview: active` when it is `true`; `boot-check.sh` (T03) closes it after boot.
- Keyring: `~/.local/share/keyrings/` is **empty**, which is why a cold Chrome start shows "Choose password for new keyring". Pre-answer by creating a plaintext default keyring (`Default_keyring.keyring` with `[keyring] display-name=Default keyring`, `lock-on-idle=false`, `lock-after=false`, and a `default` file containing `Default_keyring`, then restart `gnome-keyring-daemon`). Trade-off: passwords Chrome saves are stored unencrypted on an already unencrypted disk (PLAN §4 accepted; no owner personal data here). Implement it, but report it explicitly as the owner's call; the rollback is deleting the two files.
- First-run and search-engine prompts in Chrome are already answered/pinned by policy (`/etc/opt/chrome/policies/managed/default-search.json`); `welcome-dialog-last-shown-version` is `50.1` so the GNOME tour is done. Do not set `screen-reader-enabled` (starts Orca).
- Human mode = `gsettings reset` of exactly the keys agent mode sets, re-enable `tiling-assistant`, and nothing else. Agent mode is expected to stay on permanently; `human` exists so the owner can get stock behaviour back in one command. No idle-based automatic switching (over-engineering; an agent would fight the owner for the desktop either way).

## Steps
1. **`pc-mode [agent|human|status]`**: a table of `schema key agent-value` in the script (the keys above); `agent` applies them, disables `tiling-assistant`, sets `OverviewActive false`, writes `~/agents/state/pc-mode`; `human` resets them, re-enables the extension; `status` (default) prints `agent`/`human`/`mixed` by reading the live keys, exit 1 when mixed. Idempotent; every key applied with a read-back.
2. **Persistence:** agent-mode values also go into `/etc/dconf/db/local.d/10-agent-mode` (+ `sudo dconf update`) so a fresh session starts in agent mode; `pc mode human` writes a user-level override (gsettings) on top, so `human` survives a re-login too, and `pc mode agent` removes the override (`gsettings reset`) rather than re-writing values.
3. **Keyring pre-answer** as in Context; verify with a fresh Chrome only if none is running (`pc open https://example.com`, `pc see` shows no `Choose password` / `Cancel` dialog; close the window with `pc win close`). Chrome running → defer, say so.
4. **`pc win list`** hides rows without wm_class and title unless `--all`; `pc see` gets an `overview:` line (only when active) and a `mode:` line; `pc status --brief` and `--json` gain `mode=agent|human|mixed`. `boot-check.sh` sets `OverviewActive false` and reports `mode`.
5. **Docs:** desktop skill gets three lines ("the desktop runs in agent mode: no animations — `pc wait-for` instead of sleeps; one workspace; `pc mode human` hands it back to the owner"), README/quirks get the key table, the keyring note and the DisplayConfig prohibition. Skill stays under 90 lines.

## Success check
```bash
pc mode agent && pc mode                                   # agent, exit 0
gsettings get org.gnome.desktop.interface enable-animations   # false
gnome-extensions list --enabled | grep -c tiling-assistant    # 0
gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.freedesktop.DBus.Properties.Get org.gnome.Shell OverviewActive   # (<false>,)
pc open org.gnome.Calculator && time pc wait-for --focus Calculator   # ok after < 2 s (no animation)
pc open gnome-text-editor && pc wait-for --focus "Text Editor" && pc win list | grep -c "None" ; killall gnome-calculator gnome-text-editor   # 0 transient rows
pc status --brief | grep -o 'mode=[a-z]*'                   # mode=agent
ls ~/.local/share/keyrings/                                 # Default_keyring.keyring  default
pc mode human && pc mode; gsettings get org.gnome.desktop.interface enable-animations; gnome-extensions list --enabled | grep -c tiling-assistant   # human; true; 1
pc mode agent && pc mode                                    # agent
python3 -c "from gi.repository import Gio;b=Gio.bus_get_sync(Gio.BusType.SESSION,None);r=b.call_sync('org.gnome.Mutter.DisplayConfig','/org/gnome/Mutter/DisplayConfig','org.gnome.Mutter.DisplayConfig','GetCurrentState',None,None,0,5000,None).unpack();print([m[0] for l in r[2] for m in l[5]])"   # ['HDMI-1'] unchanged
lockcheck.sh                                                # OK (T02 keys untouched)
pc selftest                                                 # PASS
```

## Rollback
`pc mode human`; `sudo rm /etc/dconf/db/local.d/10-agent-mode && sudo dconf update`; `rm ~/.local/share/keyrings/{Default_keyring.keyring,default}`; restore `pc-win`, `pc-see`, `pc-status`, `boot-check.sh`, skill/README/quirks from the `baseline.sh` tarball; delete `pc-mode` and `~/agents/state/pc-mode`.
