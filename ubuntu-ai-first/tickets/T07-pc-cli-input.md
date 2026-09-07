# T07 — `pc` CLI: one command for screenshot, pointer, keyboard, clipboard

**Phase 1 · must · Model: opus · Estimated agent time: 90 min**

## Goal
Agents drive the desktop through one documented CLI (`pc <sub>`) with reliable read-back, instead of four ad-hoc scripts.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/` (after T05), `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- Working pieces (keep their mechanisms): `~/agents/bin/screenshot.sh` + `portal_shot.py` (xdg portal, no prompt), `click.sh` (ydotool absolute move, needs mouse accel flat), `type.sh` + `rd_type.py` (mutter RemoteDesktop keysyms, layout-independent), `key.sh` (ydotool keycodes), `env.sh`. Findings in `~/agents/README-pc-control.md`.
- Dispatcher `~/agents/bin/pc` exists from T05 (`pc <sub>` → `pc-<sub>`).
- Screen is 1920x1080; screenshots are read by agents with the Read tool (PNG). Smaller files = fewer tokens: offer `--scale 0.5`.
- ydotool: scroll = `mousemove -w -x 0 -y N`; drag = `click 0x40` (down) … move … `click 0x80` (up). Verify these flags with `ydotool --help` on the installed version.

## Steps
1. Implement subcommands as `pc-<sub>` scripts: `shot [out] [--scale F] [--region X,Y,W,H]` (region via ImageMagick/PIL crop), `click X Y [left|right|middle] [--double]`, `move X Y`, `drag X1 Y1 X2 Y2`, `scroll up|down [N] [--at X Y]`, `type "text"`, `key CHORD...`, `clip get|set "text"`, `open <app-or-url>` (`gtk-launch`/`xdg-open`, returns immediately), `notify "msg"`, `wait S` (sleep then shot), `selftest`.
2. Keep `screenshot.sh`/`click.sh`/`type.sh`/`key.sh` as thin wrappers calling `pc` (no behaviour change).
3. `pc selftest`: opens gnome-calculator, clicks 7 + 8 =, screenshots, OCR-free check via a11y-less trick: read the result with `pc clip` after `ctrl+a ctrl+c`? If not reliable, assert via a second screenshot Read by the agent; then `killall gnome-calculator`. Must finish in < 20 s and print PASS/FAIL.
4. Write `~/.claude/skills/desktop/SKILL.md`: when to use `pc` vs Playwright, the see-act-verify loop (shot → act → shot), coordinate tips (use `--scale 0.5` then multiply by 2), never type without focusing a window (T08 adds `pc win focus`), `killall` not `pkill -f`. Keep it under 60 lines. Note: this skill is machine-specific; do not add it to `~/moodle-harness`.
5. Update `~/agents/README-pc-control.md` to point to `pc --help` (each `pc-<sub>` prints usage on `-h`).

## Success check
```bash
pc selftest                              # PASS
pc shot /tmp/a.png --scale 0.5 && file /tmp/a.png    # 960x540 PNG
pc open https://example.com && sleep 3 && pc shot /tmp/b.png   # Read /tmp/b.png: Chrome shows example.com
pc clip set "hola" && pc clip get      # hola
ls ~/.claude/skills/desktop/SKILL.md
```

## Rollback
Restore `~/agents/bin` from the latest `~/agents/backups/*.tar.gz`; delete `~/.claude/skills/desktop`.
