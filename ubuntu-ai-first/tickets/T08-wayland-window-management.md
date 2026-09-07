# T08 — Window management on Wayland (`pc win`)

**Phase 1 · must · Model: opus · Estimated agent time: 90 min**

## Goal
Agents can list, focus, move, resize, minimise and close windows on the GNOME Wayland session, which `wmctrl`/`xdotool` cannot do.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/` (after T05), `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- GNOME Shell 50.1 on Wayland. `org.gnome.Shell.Eval` is disabled; `org.gnome.Shell.Introspect` is whitelisted to GNOME's own remote-desktop callers. The standard workaround is a Shell extension exposing a D-Bus API.
- Preferred: the "Window Calls" extension (`window-calls@domandoman.xyz`, D-Bus `org.gnome.Shell.Extensions.Windows`: List, Activate, Move, Resize, Close, Minimize, Maximize). Check its `metadata.json` `shell-version` for 50 before installing (`gnome-extensions install` from the GitHub release zip, or extensions.gnome.org).
- Fallback if incompatible: write a minimal extension `agent-windows@moodle-lab` (ESM `extension.js`, `metadata.json` with `shell-version: ["50"]`) exporting the same D-Bus methods via `Gio.DBusExportedObject`. Keep it under 120 lines; no UI, no prefs.
- Extensions load on session start; `gnome-extensions enable` works live on Wayland for new extensions (no restart needed in GNOME 45+). If it does not, ask the orchestrator to schedule a logout/reboot (T03 makes that safe).

## Steps
1. Install/enable the extension (steps above); verify with `gdbus introspect --session --dest org.gnome.Shell --object-path /org/gnome/Shell/Extensions/Windows`.
2. Implement `pc-win` (python3 + `gi` Gio): `list` (id, app/wm_class, title, x,y,w,h, focused, workspace as a table or `--json`), `focus <id|title-substring|wm_class>`, `move <id> X Y`, `resize <id> W H`, `close <id>`, `minimize <id>`, `maximize <id>`, `wait <title-substring> [timeout]` (poll list until a matching window exists and is focused).
3. Make `pc type` refuse (exit 2) when no window is focused; add `--force`.
4. Extend `pc selftest` to open two apps, focus each by title, move one to 100,100 and verify via `list`.
5. Document in the `/desktop` skill: "focus before typing, verify with `pc win list`".

## Success check
```bash
gnome-extensions list --enabled | grep -iE "window-calls|agent-windows"
pc win list | head                         # at least the Chrome/terminal windows with geometry
pc open gnome-text-editor && pc win wait "Text Editor" 10 && pc win move $(pc win list --json | python3 -c 'import json,sys;print([w for w in json.load(sys.stdin) if "Text Editor" in w["title"]][0]["id"])') 100 100 && pc win list | grep "Text Editor"   # x=100 y=100
pc selftest                                # PASS
```

## Rollback
`gnome-extensions disable`/`uninstall` the extension; delete `pc-win`; revert the `pc type` guard.
