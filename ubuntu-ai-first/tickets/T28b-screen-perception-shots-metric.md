# T28b — Cheaper screenshots, Chrome in the a11y tree, screenshot-vs-text metric

**Phase 1 · should · Model: opus · Estimated agent time: 60 min · After T28a and T16**

## Goal
When a screenshot is still needed it costs as little as possible (`pc shot --diff`: "did anything change, and where"), the owner's Chrome shows up in `pc see` like any GTK app, and the audit log tells per session how often agents looked at pixels instead of text, so the skill text can be tuned against a number.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/quirks.md`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4), ticket T28a (done) and T16 (audit log format). Run `pc status` first; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Run `~/agents/bin/baseline.sh` before touching `~/agents/bin` or `~/.claude/skills`.
- The owner's Chrome profile is live: never kill a Chrome that has windows open; if Chrome is already running, defer the Chrome check and say so in the report. Leave no PNGs in `/tmp`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- `pc shot` = portal capture 0.8 s, then PIL crop/scale (`~/agents/bin/pc-shot`, `portal_shot.py`). Screen 1366x768; the GNOME top bar is the first 32 px and its clock changes every minute, so a naive diff is never "unchanged".
- Chrome exposes its AT-SPI tree only when started with `ACCESSIBILITY_ENABLED=1` (or `--force-renderer-accessibility`). `pc open` goes through `xdg-open` → D-Bus activation, so an env var exported in `pc-open` may not reach the browser; the session-wide path is `~/.config/environment.d/50-agents-a11y.conf` (does not exist yet) applied live with `systemctl --user set-environment` + `dbus-update-activation-environment --systemd`. Whether a live change reaches shell-launched apps without a re-login is unknown: test it, and if not, document that it applies at the next login (T23 reboot window). Do **not** set `screen-reader-enabled` (starts Orca).
- Audit log (T16): `~/agents/log/actions.jsonl`, one line per tool call with `tool` and, for Bash, `command` (500 chars); Read calls are not logged, so a "pixel look" is counted from the Bash side: commands matching `pc shot|pc wait [0-9]|pc find|pc click-text` (OCR also screenshots). A "text look" is `pc see|pc wait-for|pc tree|pc win (list|focused)|pc a11y-click`. Viewer: `~/agents/bin/agents-log`.
- A GNOME keyring prompt can cover a cold-started Chrome; it is a gnome-shell dialog, so `pc see` lists its `Cancel` button and `pc a11y-click Cancel` dismisses it.

## Steps
1. **`pc shot --diff [PREV]`**: capture as usual, compare with `PREV` (default: the previous capture written to the same output path, kept as `<out>.prev.png`) using `PIL.ImageChops.difference().getbbox()` after masking `--ignore X,Y,W,H` (default `0,0,1366,32`). Print `changed bbox=X,Y,W,H` or `unchanged` on stderr-free stdout after the path; `--changed-only` writes only the bbox crop (full resolution) so the Read costs a fraction. Exit 0 in both cases; `--quiet` prints only the verdict.
2. **Cost visibility:** `pc shot` prints `path WxH KB` on one line so the agent sees what it is about to Read.
3. **Chrome a11y always on:** create `~/.config/environment.d/50-agents-a11y.conf` (`ACCESSIBILITY_ENABLED=1`), apply live, also `export ACCESSIBILITY_ENABLED=1` in `pc-open` (harmless, covers direct launches). Verify only if no Chrome is running: `pc open https://example.com`, `pc wait-for --window "Example Domain" --timeout 15 --see` must show `heading "Example Domain"`; close the window with `pc win close "Example Domain"`. Record the result (live or next-login) in `~/agents/KB/quirks.md`.
4. **Metric:** `agents-log --pc [--since 24h]` prints one row per session `session pixel text ratio` plus a total row, using the patterns above; `pc status --json` gains `pc_look_ratio_24h`. If T16 is not finished yet, stop and report — do not invent a log format.
5. **Skill:** add a 4-line cost table to `~/.claude/skills/desktop/SKILL.md` (`pc see` ~1 s / ≤4 KB text / greppable; `pc shot --scale 0.5` ~1 s + a Read ~350 tokens, not greppable; `pc shot --diff` for "did anything change"; `pc find` = a screenshot + 1.2 s OCR) and the rule "one screenshot per task is normal, one per step is a smell". Keep the skill under 90 lines.

## Success check
```bash
pc shot /tmp/t28b.png >/dev/null; pc shot /tmp/t28b.png --diff --quiet          # unchanged
pc open org.gnome.Calculator && pc wait-for --focus Calculator && pc shot /tmp/t28b.png --diff --quiet   # changed bbox=… with W and H > 100
pc shot /tmp/t28b.png --diff --changed-only | tail -1; killall gnome-calculator   # a crop smaller than 1366x768
pc shot /tmp/t28b.png | grep -E '[0-9]+x[0-9]+ [0-9]+ ?KB'                        # size line
grep -c ACCESSIBILITY_ENABLED ~/.config/environment.d/50-agents-a11y.conf ~/agents/bin/pc-open   # 1 and 1
pc win list | grep -qi chrome || { pc open https://example.com && pc wait-for --window "Example Domain" --timeout 15 --see | grep -c 'heading "Example Domain"'; pc win close "Example Domain"; }   # 1 (or "deferred: Chrome already running" in the report)
claude -p --model sonnet "Use the desktop skill. Open gnome-calculator, compute 12*3 and report the result, then close it." | tail -3
agents-log --pc --since 10m                                                       # last session: pixel <= 1, text >= 3, ratio <= 0.34
pc status --json | grep -o '"pc_look_ratio_24h": *[0-9.]*'                        # present
rm -f /tmp/t28b.png /tmp/t28b.png.prev.png; ls /tmp/*.png 2>/dev/null | wc -l   # 0 new files
```

## Rollback
`rm ~/.config/environment.d/50-agents-a11y.conf; systemctl --user unset-environment ACCESSIBILITY_ENABLED`; restore `pc-shot`, `pc-open`, `pc-status`, `agents-log`, the skill and quirks.md from the `baseline.sh` tarball.
