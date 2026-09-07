# Ubuntu AI-first — master plan

Owner: see config.env. Machine: `moodle-lab` (Ubuntu 26.04.1, GNOME 50.1 Wayland, i5-12500H 16 threads,
37 GB RAM, 476 GB NVMe, Iris Xe). Written 2026-09-05 by the architect session. Tickets live in
`tickets/`, one Opus agent per ticket, briefed by the orchestrator session in `~`.

## 1. Vision

1. Anything a human power user can do on this laptop, an agent can do faster and can prove it did.
2. The machine is a 24/7 workstation + server for a fleet of agents; the owner watches from
   the mobile app and gets short pushes.
3. Main workload: Moodle plugin/core development in Docker (`~/moodle-envs/<ver>`).

## 2. Principles

1. **CLI first, MCP only when stateful.** The agent CLI is strongest with Bash + files. A script in
   `~/agents/bin` costs zero context; an MCP server costs schema tokens and a process. MCP is kept
   only for the browser (Playwright: a live page session cannot be a one-shot CLI).
2. **Standard tools, thin glue.** systemd timers, etckeeper, restic, ufw, tailscale, tesseract.
   Custom code only where Wayland/GNOME leaves no standard path (window management extension).
3. **Verify, don't trust.** Every control action has a read-back (screenshot, `pc status`, exit
   code). Every ticket has a success check the agent runs itself.
4. **Rollback before change.** `/etc` is in git (etckeeper); config baselines committed before
   each ticket; every ticket lists its rollback.
5. **LLM on failure, not on schedule.** Scheduled checks are plain bash; `claude -p` is invoked
   only when a check fails or a task truly needs judgement. Cheap, predictable, auditable.
6. **Never lock the owner out, never push to git.** Two access paths (SSH + Tailscale SSH) must
   both work before touching either. Owner manages git.
7. **Know your own machine; never ask the owner about it.** Power/AC, battery, lid, network,
   services, timers, screen contents and focused window are all readable. `pc status` (T05) is
   the single cheap facility every agent calls before stating or deciding anything about the
   machine; a SessionStart hook injects `pc status --brief` into every session so the baseline is
   already in context. Owner's words: "It's your computer. You should know what is happening on
   your computer."

## 3. Current state (inspected 2026-09-05)

### Works
- The agent CLI 2.1.261 native build, `bypassPermissions`, passwordless sudo, Fable default model,
  Moodle harness hooks/skills (`~/.claude`, source `~/moodle-harness`).
- MCPs: `playwright` (user scope), claude.ai Gmail / Calendar / Drive connectors.
- Desktop see-click-verify loop: `~/agents/bin/{screenshot,click,type,key}.sh` (portal screenshot,
  ydotool pointer/keys, mutter RemoteDesktop keysym typing). Mouse accel flat. Cheat sheet
  `~/agents/README-pc-control.md`.
- Never-suspend: logind drop-in (lid ignored), sleep/suspend targets masked, gsettings sleep
  `nothing`. GDM autologin on. Wayland session on tty2.
- Moodle 5.2 stack (`moodle52-app-1`, `moodle52-db-1`) + shared stack (proxy :80, mailhog :8025,
  selenium :4444). Site on `http://moodle-lab.tail2ea32e.ts.net:8052`.
- Tailscale `100.99.234.53` (MagicDNS), SSH server (password + keys), tmux session `claude` runs
  the orchestrator with Remote Control.
- Tooling: docker 29, node 24 (nvm), python 3.14 with `gi` (AT-SPI bindings present), php,
  composer, ffmpeg, mpv, vlc, playerctl, wl-clipboard, btop/htop, bpftrace, strace, sysstat.

### Gaps
1. **Screen lock still on** (`lock-enabled true`, `idle-delay 300`): after 5 min idle the desktop
   locks; screenshots show the lock screen and clicks land on it.
2. **Nothing survives a reboot**: compose files have no `restart:` policy, `Linger=no`, the tmux
   `claude` session is not auto-started, docker group needs a re-login.
3. **No channel to reach the owner from a headless agent** (PushNotification only works inside a
   Remote Control session).
4. **No scheduler / runner** for persistent agents; no logs of what agents did; no kill switch.
5. **No window management on Wayland** (`wmctrl`/`xdotool` only see Xwayland windows): agents
   cannot list, focus, move or close windows.
6. **No safety net**: no etckeeper, no snapshots, no backups, no DB dumps. Disk unencrypted.
7. **Access**: SSH password auth on, ufw inactive, Tailscale SSH off (single access path).
8. **Tuning**: WiFi power save on (SSH/Tailscale stalls), `powersave` governor, inotify watches
   65536 (too low for Moodle repos + grunt watch), journald not capped, docker logs unbounded,
   no battery charge limit (battery already at 72 % health while plugged 24/7).
9. **Browser**: Playwright MCP uses a throwaway profile (logins lost each run); no Moodle URL/login
   helper; Claude-in-Chrome integration not set up.
10. **Knowledge**: machine facts live only in the orchestrator's auto-memory; worker agents
    rediscover ports, paths, quirks every time.

## 4. Architecture by layer

| # | Layer | Chosen approach | Rejected (why) |
|---|---|---|---|
| 1 | Safety / rollback | etckeeper (git on `/etc`), baseline commits per ticket, restic backups, per-ticket rollback | Timeshift (rsync on the same disk, heavy, no gain over git for config); btrfs migration (reinstall) |
| 2 | Always-on desktop | GNOME session with lock/blank/idle disabled, autologin, linger, systemd user units for orchestrator + stacks | Xorg switch (not needed, injection works on Wayland); headless RDP session (loses the physical screen) |
| 3 | Desktop control | One CLI `pc` (`~/agents/bin/pc`) wrapping portal screenshot, ydotool, mutter RD; GNOME extension for windows; tesseract OCR; AT-SPI tree; `/desktop` skill | Custom MCP server (schema tokens, no benefit over bash + Read on PNGs); pyautogui/xdotool (X11 only); switching to KDE/Sway (loses the owner's desktop) |
| 4 | Browser | Playwright MCP with persistent profiles + config file; `/moodle-web` skill; optional Claude-in-Chrome for the owner's real browser | Selenium scripting (Behat only); custom CDP scripts (Playwright MCP already gives snapshot/click) |
| 5 | Agent runtime | systemd **user** timers → `agent-run <name>` → `claude -p --model opus` with brief, logs, report, notify; `claude --bg` for long interactive jobs | cron (no journal, env pain); cloud routines `/schedule` (run off-machine, cannot touch the laptop); `/loop` (needs a live session); custom daemon |
| 6 | Observability | `pc status` (bash; text, JSON, `--brief` one-liner injected at SessionStart), PostToolUse audit log (`~/agents/log/actions.jsonl`), journald, sentinel timer; Netdata later | Prometheus + Grafana (over-engineered for one box) |
| 7 | Owner comms | `notify-owner` CLI on ntfy (phone app), Gmail MCP for long reports | Telegram bot (owner deferred; more code); email-only (too slow for alerts) |
| 8 | Remote access | Tailscale (SSH + Tailscale SSH), RDP via gnome-remote-desktop over tailnet only, ufw default-deny except tailnet + LAN | Public port-forwards (exposure); VNC/x11vnc (X11) |
| 9 | OS / kernel | sysctl.d drop-ins (inotify, swappiness, limits), journald cap, docker daemon.json, power-profiles + charge limit, WiFi power save off | Custom kernel builds (no need, breaks updates); disabling AppArmor (keep) |
| 10 | Knowledge | `~/agents/KB/` (machine.md auto-generated, runbooks/, quirks.md) linked from `~/CLAUDE.md`; per-agent `~/agents/<name>/` (BRIEF.md, state.json, logs/) | Vector DB / RAG (files + grep are enough at this size) |

Notes on choices:
- **Why a GNOME extension for windows.** GNOME 41+ removed `org.gnome.Shell.Eval` and restricts
  `Introspect` to whitelisted callers. The community "Window Calls" extension exposes exactly a
  list/activate/move/resize/close D-Bus API; if it is not GNOME 50 compatible, a ~80-line own
  extension with the same API is the minimum custom code.
- **Why `claude -p` under systemd user units.** Same user, same OAuth in `~/.claude.json`, same
  `~/.claude` settings/skills/hooks, native binary in `~/.local/bin` (no nvm needed). Linger makes
  timers fire even if the graphical session dies.
- **Why text before pixels (T28).** A screenshot is two tool calls (`pc shot` 0.8 s + Read of ~1400
  image tokens) and a model turn spent reading pixels, repeated on every `pc wait`; a text digest is one
  call, greppable and exact. Measured: `pc win list` 0.09 s, `pc tree <app>` 0.19 s / 3.8 KB, and GTK4's
  "0,0 extents" are only a coordinate-type issue (`CoordType.WINDOW` + window-calls `GetFrameRect` gives
  real screen coordinates). window-calls has no signals, so `pc wait-for` polls cheap text at 250 ms
  instead of registering AT-SPI events; notifications are read from the gnome-shell a11y tree instead
  of a bus-monitor daemon. An MCP server was rejected again: every perception is a stateless query,
  so it would add schema tokens and a process without a live session to justify them. The desktop
  itself is tuned for agents (`pc mode agent`: no animations, no overview, one workspace, dialogs
  pre-answered) with `pc mode human` as the way back; the audit log (T16) measures the
  screenshot-vs-text ratio per session so the skill text can be tuned against a number.
- **Why no disk encryption.** FDE needs a passphrase at boot, which kills unattended reboots and
  self-repair. Trade-off accepted; secrets stay minimal and exposure is tailnet/LAN only.

## 5. Roadmap

Legend: **must** / should / nice. Time = estimated Opus agent time.

### Phase 0 — Safety net and always-on (6 tickets, all must)
- T01 config-baseline-etckeeper — git on `/etc`, baseline dump of gsettings, `~/.claude`, `~/agents`. 45 min
- T02 always-on-desktop — kill screen lock/blank/idle; verify screenshot after idle. 30 min
- T03 boot-resilience — compose `restart` policies (+ harness template), linger, orchestrator tmux service, docker group. 60 min
- T04 notify-owner — ntfy channel + `notify-owner` CLI; owner subscribes on the phone. 45 min
- T05 pc-status-and-kb — `pc status` (text/JSON/`--brief`), SessionStart hook injecting the brief, `~/agents/KB/` with auto machine.md. 90 min
- T06 tailscale-ssh-second-path — Tailscale SSH on, key login verified; second access path. 30 min

### Phase 1 — Desktop control v2 (8 tickets)
- T07 pc-cli-input (must) — unify scripts into `pc` subcommands (shot, click, drag, scroll, type, key, clip, open, selftest) + `/desktop` skill. 90 min
- T08 wayland-window-management (must) — `pc win list/focus/move/resize/close` via extension. 90 min
- T09 screen-text-ocr (nice) — tesseract, `pc find "text"` → coordinates, `pc click-text`. 60 min
- T10 a11y-tree (nice) — AT-SPI dump `pc tree` for semantic element lookup. 60 min
- T11 owner-view-rdp (nice) — gnome-remote-desktop RDP bound to tailnet so the owner can watch. 45 min
- T28a screen-perception-see (must) — `pc see` text digest (focus, windows, interactive a11y tree with real GTK4 coordinates, notifications, clipboard), `pc wait-for` blocking waits, skill order "text before pixels". 90 min
- T28b screen-perception-shots-metric (should) — `pc shot --diff`/`--changed-only`, Chrome in the a11y tree (`ACCESSIBILITY_ENABLED`), `agents-log --pc` screenshot-vs-text ratio. 60 min
- T28c agent-first-desktop-profile (should) — `pc mode agent|human`: animations off, overview closed, one workspace, no tiling/update popups, plaintext default keyring; transient rows hidden in `pc win list`. 75 min

### Phase 2 — Browser automation (3 tickets)
- T12 playwright-mcp-hardening (must) — config file, persistent profiles, headed/headless switch, output dir. 60 min
- T13 moodle-web-skill (must) — `/moodle-web`: env URL map, login, purge caches, plugin pages via Playwright. 60 min
- T14 claude-in-chrome (nice) — `--chrome` integration with the owner's Chrome profile in the session. 45 min

### Phase 3 — Agent runtime and fleet (5 tickets, all must)
- T15 agent-runner — `agent-run`, `agent@.service/.timer` templates, logs, REPORT.md, `agents-status`, `agents-stop`. 90 min
- T16 audit-log-hook — PostToolUse hook → `~/agents/log/actions.jsonl` + `agents-log` viewer. 45 min
- T17 sentinel-agent — 15-min health check, `claude -p` repair on failure, daily 08:00 digest. 75 min
- T18 moodle-keeper-agent — daily: stacks up, DB dumps, docker prune, weekly stable-branch pull when clean. 75 min
- T19 fleet-contract-docs — `~/CLAUDE.md` roster + fleet contract, `~/agents/README.md`, KB runbooks. 45 min

### Phase 4 — OS tuning and maintenance (5 tickets)
- T20 sysctl-journald-docker-limits (should) — inotify, swappiness, nofile, journald cap, docker log rotation + live-restore. 45 min
- T21 power-battery-network (must) — WiFi power save off, performance profile on AC, battery charge limit 80 %. 45 min
- T22 backups-restic (must) — restic repo, daily timer, includes DB dumps; optional rclone to Drive. 75 min
- T23 updates-reboot-policy (should) — unattended-upgrades security-only, weekly maintenance agent, reboot window rules. 60 min
- T24 disk-health-smart (nice) — smartmontools + smartd, SMART/battery in `pc status`. 30 min

### Phase 5 — Remote and observability extras (3 tickets)
- T25 firewall-ssh-hardening (should) — ufw default deny, allow tailnet + LAN, SSH password auth off after keys verified. 60 min
- T26 netdata (nice) — Netdata bound to tailnet for the owner's phone. 45 min
- T27 tailscale-serve-https (nice) — HTTPS names for Moodle envs via `tailscale serve`. 60 min

Dependencies: T05 → T17; T04 → T15/T17/T18; T15 → T17/T18/T23; T01 before any `/etc` change;
T06 before T25; T07 before T08–T10; T12 before T13/T14; T18 before T22 (dumps);
T08+T10 before T28a; T28a and T16 before T28b; T28a before T28c.

## 6. Risks and safety rails

| Risk | Where | Mitigation |
|---|---|---|
| Lock the owner out (sshd, ufw, tailscale, sudoers) | T06, T25 | Two paths verified before touching one; changes applied with a 5-min auto-revert timer (`at`/systemd-run) that the agent cancels only after a successful login test; etckeeper commit before |
| Desktop stops being controllable (lock screen, lid, session crash) | T02, T03 | Lock/idle off; owner lid-closed test; orchestrator service restarts tmux; sentinel checks `pc shot` works |
| Reboot leaves services down | T03, T23 | restart policies, linger, user units; sentinel verifies after boot; reboot only in window and after notify |
| Runaway or looping agents (cost, CPU) | T15, T17 | `TimeoutStartSec`, `MemoryMax`, one instance per agent (systemd), `agents-stop` kill switch, `--max-budget-usd` where API-billed |
| Agent breaks the harness (`~/.claude`) | T01, T16 | Baseline copies in `~/agents/backups`, audit log shows which session changed what; `~/moodle-harness` is the reference copy |
| Data leak (creds in pushes, public ntfy topic) | T04 | Random 32-char topic, pushes carry no secrets, long content goes via Gmail MCP or a local file path |
| Disk full (docker images, journald, logs, dumps) | T18, T20, T22 | Caps on journald/docker logs, prune in keeper, restic retention, `pc status` disk alert at 85 % |
| Kernel/OS tuning regressions | T20, T21 | Only drop-in files in `/etc/sysctl.d`, `/etc/NetworkManager/conf.d`; revert = delete file + reload; etckeeper |
| Unencrypted disk on a travelling laptop | all | Accepted trade-off (see §4); no owner personal data on this machine; Moodle creds are dev-only |
| Wrong-window input (typing into the wrong app) | T07, T08 | `pc win focus` before typing, screenshot read-back after, `pc type` refuses when no focused window |

## 7. Open questions for the owner

1. **Notification channel.** Default: ntfy (free app, one curl). Alternative: Telegram bot (more
   code, richer). Answer changes T04 only.
2. **SSH password login.** Default: turn it off once key login and Tailscale SSH are verified from
   your phone/laptop (T25). Keep it if you rely on password SSH from devices without keys.
3. **Off-machine backup target.** Default: restic to a local repo only, plus optional rclone to
   your Google Drive (T22). Say if Drive is off-limits or you have a NAS/another box.
4. **Unattended reboots.** Default: agents may reboot for kernel/security updates only between
   04:00–05:00 Europe/Madrid, after a push and only when all health checks pass (T23). Say if you
   want every reboot to require your OK.
5. **Watching the desktop.** Default: enable RDP over Tailscale (T11) so you can see the screen
   from the phone. Skip if you never need to watch.
