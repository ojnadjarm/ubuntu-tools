# T02 — Always-on desktop (no lock, no blank, no idle)

**Phase 0 · must · Model: opus · Estimated agent time: 30 min**

## Goal
The GNOME session never locks, blanks or goes idle, so screenshots and input from agents always hit the real desktop, 24/7, on AC or battery.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"` (available after T01).
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Current: `org.gnome.desktop.screensaver lock-enabled true`, `org.gnome.desktop.session idle-delay 300`, `idle-activation-enabled true`. Sleep is already disabled (logind drop-in in `/etc/systemd/logind.conf.d/`, `sleep.target`/`suspend.target` masked, power plugin `sleep-inactive-*-type nothing`).
- GDM autologin is on for `oscar-nadjar` (`/etc/gdm3/custom.conf`).
- Screenshot tool: `~/agents/bin/screenshot.sh`. Session env: `~/agents/bin/env.sh`.
- Mutter keeps the internal panel on when the lid is closed and no external monitor exists; this must be confirmed by the owner (cannot be simulated).

## Steps
1. `gsettings set org.gnome.desktop.screensaver lock-enabled false`; `idle-activation-enabled false`; `org.gnome.desktop.session idle-delay 0`; `org.gnome.desktop.screensaver lock-delay 0`; `org.gnome.desktop.lockdown disable-lock-screen true`.
2. Verify power plugin stays `nothing` for AC and battery; set `org.gnome.settings-daemon.plugins.power idle-dim false` and `power-button-action nothing`.
3. Make the settings persistent across dconf resets: add a dconf profile override under `/etc/dconf/db/local.d/00-agents` with the same keys, `sudo dconf update` (etckeeper commit).
4. Add a `pc`-compatible check: `~/agents/bin/lockcheck.sh` printing `OK` if all keys have the expected values and the screen is unlocked (`gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.GetActive` returns false).
5. Write a 2-line note in `~/agents/README-pc-control.md` and add an owner TODO in your report: "close the lid for 2 min, then ask the orchestrator for a screenshot".

## Success check
```bash
~/agents/bin/lockcheck.sh                       # prints OK
gsettings get org.gnome.desktop.session idle-delay   # uint32 0
sleep 360 && ~/agents/bin/screenshot.sh /tmp/t02.png && python3 -c "from PIL import Image; im=Image.open('/tmp/t02.png'); print(im.getextrema())"   # not all-black (install python3-pil if missing); or simply Read the PNG and confirm the desktop is visible
```

## Rollback
`gsettings reset` each key; remove `/etc/dconf/db/local.d/00-agents` and `sudo dconf update`.
