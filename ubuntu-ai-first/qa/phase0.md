# Phase 0 QA report — 2026-09-05

Independent verification of T01–T06 by the QA agent. Every command below was re-run by QA;
tests went beyond the tickets' own Success checks (fault injection where safe).

## Verdict

| Ticket | Success check | Goal met | Verdict |
|---|---|---|---|
| T01 config-baseline-etckeeper | PASS | PASS | **PASS** |
| T02 always-on-desktop | PASS | PASS | **PASS** |
| T03 boot-resilience | PASS | partial | **PASS with defect** (D1) |
| T04 notify-owner | PASS | PASS | **PASS** |
| T05 pc-status-and-kb | PASS | PASS | **PASS** |
| T06 tailscale-ssh-second-path | FAIL (as written) | NOT met | **FAIL** (D2, D3) |

## Evidence

### T01 — PASS
- `sudo etckeeper vcs status` → `On branch master / nothing to commit, working tree clean`.
- Log: `f1e033d Initial commit`, `fb12a80 baseline 2026-09-05`, `6572874 pre T06`, `0fe5f73 T02 …`.
- **apt hook proven live**: `apt-get install -y lynx-common` produced
  `[master 85567cf] committing changes in /etc made by "apt-get install -y lynx-common"` (7 files);
  `apt-get purge` produced `4a1ed4d` with the reverse delta. Tree clean again after both.
  (`sl` install produced no commit — correct: it touches nothing under `/etc`.)
- `/etc/dconf/db/local.d/00-agents`, `/etc/dconf/profile/user`, `/etc/dconf/db/local` are tracked.
- `baseline.sh`: tarball valid (`tar tzf` clean), contains `.claude/settings.json`, `.claude/hooks/*`,
  `.claude/skills/*`, `CLAUDE.md`, `agents/bin/*`, `dconf.ini` (96 lines).
- **Prune proven**: seeded 24 dated dummy tarballs (25 total), ran `baseline.sh` → 20 remain,
  oldest deleted, real baselines kept. Dummies removed by QA.

### T02 — PASS
- `lockcheck.sh` → `OK`, exit 0. All 9 gsettings keys hold the expected values.
- **Fault injection**: `gsettings set …screensaver lock-enabled true` → `lockcheck.sh` prints
  `FAIL org.gnome.desktop.screensaver lock-enabled = true (expected false)`, exit 1. Restored to false.
- System profile `/etc/dconf/profile/user` = `user-db:user` + `system-db:local`; `00-agents` carries all
  keys; `/etc/dconf/db/local` compiled 18:43.
- **Screenshot read by QA with the lid physically closed, on AC**: real GNOME desktop (dock, top bar
  "Sep 5 18:54", wallpaper, Home icon). Not a lock screen, not black
  (extrema R 14–255, G 10–255, B 13–255). This is the strongest evidence in Phase 0.

### T03 — PASS with defect D1
- `restart: unless-stopped` × 3 in `shared/docker-compose.yml`, × 2 in `5.2/docker-compose.yml`.
- All 5 running containers report `unless-stopped` via `docker inspect`.
- `/moodle-install` template: `~/.claude/skills/moodle-install/install.sh` and the synced
  `~/moodle-harness` copy both emit `restart: unless-stopped` (lines 100, 105).
- `Linger=yes`. `systemctl --user is-enabled claude-orchestrator` → `enabled`, `is-active` → `inactive`
  (correct: not started, running tmux session untouched). Wants-symlink present under `default.target.wants`.
- `boot-check.sh` → 11 OK lines, exit 0. **Fault injection**: a copy pointing at a stopped dummy
  container printed `FAIL docker qa-dummy2` and exited 1. Dummy removed.
- **Defect D1** below: the ExecStart is *not* safe against an existing tmux session.

### T04 — PASS
- `notify-owner -t "QA Phase 0" "Phase 0 QA running"` → exit 0; log line
  `2026-09-05T18:55:45+02:00	ok	default	Phase 0 QA running`.
- `~/agents/secrets` 700, `ntfy.env` 600, owner `oscar-nadjar`.
- **Failure paths all non-zero**: empty `NTFY_TOPIC` → exit 1; env file with no vars → exit 1;
  missing env file → exit 1 with a clear message; unresolvable `NTFY_URL` → exit 1; no arguments → exit 2 + usage.
- **No secret leak**: the 40-char topic appears in no file under `~/agents`, `~/CLAUDE.md`,
  `~/.claude/CLAUDE.md`, the orchestrator memory files or `~/moodle-harness` — only in `secrets/ntfy.env`.

### T05 — PASS
- `pc status` prints 8 sections, every line `[OK]`/`[FAIL]`/`[-]`, `FAILURES: 0`, exit 0.
- `pc status --json` is valid JSON (`generated`, `fails`, `sections`).
- `pc status --check` → exit 0. **Fault injection**: a created-but-not-running container labelled
  `com.docker.compose.project=qatest` made it print `FAIL docker.qatest: 0/1 up`, exit 1. Removed; back to exit 0.
- `pc status --brief` → 137 chars, `real 0m0.247s` (well under 1 s).
- **Values cross-checked against raw sources**: `/sys/class/power_supply/AC*/online`=1 → `AC`;
  `BAT*/capacity`=100 → `100%`; `/proc/acpi/button/lid/*/state`=closed → `lid=closed`;
  `docker ps -q | wc -l`=5 → `docker=5/5`; `tailscale status --json .BackendState`=Running → `ts=up`;
  `df /`=7% → `disk=7%`; `systemctl --user list-timers`=4 → `timers=4`; SSID `Livebox6-47FF` matches. All correct.
- SessionStart hook: `~/.claude/hooks/machine-status.sh` registered in `~/.claude/settings.json` as a
  **second** SessionStart group, Moodle hook intact, no duplicates, valid JSON, all 3 hook paths executable.
- **End-to-end injection proven**: `claude -p --model sonnet "What is the machine's power source and lid
  state right now? Answer from context only, no tool calls."` → `AC power, lid closed.`
- KB: `machine.md`, `quirks.md`, `runbooks/{reboot,new-wifi,tailscale-down,docker-down,disk-full,locked-out}.md`.
  `pc status --facts` regenerated identically to the committed `machine.md` (diff empty apart from the timestamp).
- `grep -c "agents/KB" ~/CLAUDE.md` → 1.

### T06 — FAIL
- `tailscale debug prefs | grep RunSSH` → `"RunSSH": true`. ✔
- `ufw status` → `inactive`. ✔ `sshd -T`: `passwordauthentication yes`, `pubkeyauthentication yes`. ✔
- `~/agents/KB/runbooks/locked-out.md` exists, 3.2 KB, lists all four access paths. ✔
- **The ticket's own Success check fails**: `tailscale ssh oscar-nadjar@moodle-lab echo tailscale-ssh-ok`
  → `No ED25519 host key is known for moodle-lab and you have requested strict checking. Host key
  verification failed.` exit 255. (D3)
- **The key-login "proof" is self-referential** (D2): `ssh -o BatchMode=yes oscar-nadjar@100.99.234.53`
  does succeed (`key-login-ok`), but `ssh -v` shows it authenticated against **OpenSSH_10.2p1**, i.e. the
  local sshd, not the Tailscale SSH server; and `~/.ssh/authorized_keys` contains exactly one key which is
  byte-identical to this machine's own `~/.ssh/id_ed25519.pub`. The machine can SSH to itself. **No owner
  device key is installed**, so the second access path is not proven from anywhere but this laptop.

## Defects

**D1 — HIGH — T03 — `claude-orchestrator.service` ExecStart fails (and restart-loops) when the tmux session already exists.**
- Repro (QA ran it, on a throwaway session name, never touching `claude`):
  `tmux new-session -d -s qa2 -c $HOME 'sleep 60'` then
  `tmux new-session -A -d -s qa2 -c $HOME 'sleep 60'` → `open terminal failed: not a terminal`, **exit 1**.
  `-A` means "attach if it exists", and attaching from systemd's non-tty context always fails; `-d` does not
  suppress it in tmux 3.x.
- Impact: with `Type=forking` + `Restart=on-failure` + `RestartSec=10`, any `systemctl --user start
  claude-orchestrator` while a `claude` session is alive gives an infinite 10 s restart loop, and the
  documented hand-over procedure in `README-pc-control.md` ("exit the tmux session, then start the service")
  is the only order that works — the README's claim *"idempotent: it never clashes with an existing session"*
  is false.
- Fix: `ExecStart=/bin/sh -c 'tmux has-session -t claude 2>/dev/null || exec tmux new-session -d -s claude -c %h "%h/.local/bin/claude --remote-control moodle-lab"'`
  (QA verified the guarded form returns exit 0 in both states), and correct the README line.

**D2 — HIGH — T06 — no owner key in `~/.ssh/authorized_keys`; the second access path is unproven.**
- Repro: `diff <(cut -d' ' -f1,2 ~/.ssh/authorized_keys) <(cut -d' ' -f1,2 ~/.ssh/id_ed25519.pub)` → identical.
  `wc -l` = 1.
- Impact: T06's goal ("the owner can reach a shell two independent ways") is not met. T25 (SSH password auth
  off) **must not run** until this is fixed, or the owner is locked out of the OpenSSH path.
- Fix: the ticket's own step 3 — ask the owner for his laptop/phone public key and append it; do not
  count the machine's self-key. Until then T06 stays open.

**D3 — MEDIUM — T06 — Tailscale SSH cannot be verified from this host, and the ticket's Success check is wrong.**
- Repro: see T06 evidence. `tailscale ssh` to the node's own MagicDNS name fails host-key verification, and a
  plain `ssh` to `100.99.234.53` from this machine is answered by the local sshd, not by tailscaled — a loopback
  connection never traverses the tunnel, so the Tailscale SSH server is never exercised.
- What *is* known: `RunSSH: true`, tailnet CapMap contains `https://tailscale.com/cap/ssh`, so the tailnet
  policy grants SSH; `tailscaled` logged `EditPrefs: MaskedPrefs{RunSSH=true}` at 18:44 with no ACL error.
- Fix: replace the Success check with one the owner runs from a *second* tailnet device
  (`ssh oscar-nadjar@moodle-lab` from his phone/laptop); record the result in the ticket.

**D4 — MEDIUM — T05 — `pc status` cannot detect a whole compose stack that has been `down`ed.**
- Repro: the docker section is built from `docker ps -a`, so "expected" containers are whatever containers
  still exist. A stopped container is caught (proven), but `docker compose down` on `moodle52` removes both
  containers, the `moodle52` row disappears and the remaining 3 shared containers report `docker=3/3` `[OK]`
  — a false green. Only *zero* containers anywhere is reported as a failure.
- Fix: read the expected service list from `~/moodle-envs/*/docker-compose.yml` (or a small
  `~/agents/etc/expected-containers` list) and FAIL on any missing project, not just any stopped container.

**D5 — LOW — T02 — the dconf system defaults are not locked.**
- `/etc/dconf/db/local.d/locks/` does not exist, so `00-agents` only supplies *defaults*: any `gsettings set`
  (by a user, an agent, or GNOME Settings) silently re-enables the lock screen and survives, and only a full
  dconf reset falls back to the safe values. The ticket asked for persistence "across dconf resets", which is
  met, but the stronger and cheaper guarantee is a lock file.
- Fix: add `/etc/dconf/db/local.d/locks/00-agents` listing the same key paths, `sudo dconf update`
  (+ etckeeper commit). `lockcheck.sh` already detects the drift, so this is defence in depth.

**D6 — LOW — T02/docs — `README-pc-control.md` states screenshots are 1920x1080; they are 1366x768.**
- Repro: `python3 -c "from PIL import Image; print(Image.open('shot.png').size)"` → `(1366, 768)`.
- Fix: drop the resolution from the README (it changes with the lid/monitor state) or state it is read at runtime.

**D7 — LOW — T05 — `KB/machine.md` reports the wrong group list.**
- `pc status --facts` uses `id -Gn`, which reflects the *current shell's* groups. Every shell on this box
  predates the `docker` group addition, so `machine.md` says
  `groups: oscar-nadjar,adm,cdrom,sudo,dip,plugdev,users,lpadmin,lxd` — with **no `docker`**, while
  `getent group docker` → `docker:x:115:oscar-nadjar`. An agent reading the KB would wrongly conclude the
  docker group is missing and re-apply the socket ACL.
- Fix: use `id -Gn $USER` / `getent group` in `pc-status --facts`.

**D8 — LOW — T03/T05 — `~/moodle-harness` carries two machine-specific edits beyond the T03 change.**
- `git status --porcelain` (QA did not commit anything): ` M settings.example.json`, ` M
  skills/moodle-install/{SKILL.md,docker-compose.shared.yml,install.sh}`, ` M sync.sh`.
- The compose/SKILL/install.sh edits are the expected T03 work, and the `sync.sh` change (filtering
  non-`moodle-*` hooks out of the exported settings) is correct and required by T05. But
  `settings.example.json` was regenerated from the live file and now pins
  `"model": "claude-fable-5-1[1m]"` (was `"fable[1m]"`) and `"effortLevel": "medium"` (was `"xhigh"`) —
  a machine-specific model id leaking into the shared harness reference.
- Fix: before the owner commits, revert the `model` line in `settings.example.json` to the generic
  `fable[1m]`. (The `effortLevel: medium` change matches the owner's standing preference — keep it.)

**D9 — INFO — leftovers.** `/tmp/t02.png` (18:52) and `/tmp/verify.png` (18:00) were left by the T02 and
desktop-control agents. `~/agents/bin/env.sh` is `+x` but has no shebang (it is only ever sourced). No stray
temp files under `~/agents`, no broken symlinks in `~/agents/bin` or `~/.local/bin`, no duplicate hook entries,
every script in `~/agents/bin` is executable and passes `bash -n`, `/etc` working tree clean.

## Not testable without the owner

1. **Actual reboot** — T03 is proven only by configuration (restart policies, linger, enabled unit).
   Nothing has survived a real boot. Owner or T23 must reboot once and run `boot-check.sh`.
2. **Tailscale SSH inbound** — needs a second tailnet device (D3).
3. **Owner key login** — needs the owner's public key (D2).
4. **ntfy push received on the phone** — QA confirmed `notify-owner` returns 0 and ntfy.sh accepted the POST
   ("QA Phase 0" / "Phase 0 QA running"), but delivery to the handset can only be confirmed by the owner.
5. **Lid-closed over hours** — QA read a real desktop screenshot with the lid closed at 18:54, which settles
   the panel-stays-on question for now; only long-run observation would prove it 24/7.
6. **`docker` group without the ACL** — only a re-login or reboot shows whether `docker ps` works without
   `setfacl` (see D7).

## Update 2026-09-05 19:30 (orchestrator)
D2/D3 closed: owner logged in from Windows node `oscar` (100.68.188.71) over Tailscale SSH (tailscaled audit: "access granted to oscar.nadjar@gmail.com as ssh-user oscar-nadjar"). Second access path proven. Remaining gap for T25: no owner-device public key in `~/.ssh/authorized_keys`; Tailscale SSH counts as the key-less second path.
