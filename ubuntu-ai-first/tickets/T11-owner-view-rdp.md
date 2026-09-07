# T11 — Owner can watch the desktop (RDP over Tailscale)

**Phase 1 · nice · Model: opus · Estimated agent time: 45 min**

## Goal
The owner can open the live desktop from their phone or another device over the tailnet, to see what agents are doing; nothing is exposed outside the tailnet.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/` (after T05), `~/agents/ubuntu-ai-first/PLAN.md` (sections 3 and 4).
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- `gnome-remote-desktop 50.2` is installed, user service disabled, RDP needs a TLS cert/key and credentials (`grdctl`). Session is the existing Wayland desktop (screen sharing, not headless).
- Tailscale IP 100.99.234.53; ufw is inactive today (T25 will restrict). Bind or firewall RDP to `tailscale0` only.
- Owner answered PLAN §7 Q5; skip the ticket if he said no.

## Steps
1. Generate a self-signed cert/key under `~/.local/share/gnome-remote-desktop/` (openssl, 10 years); `grdctl rdp set-tls-cert/key`, `grdctl rdp set-credentials <user> <random-password>` (store the password in `~/agents/secrets/rdp.env`, 600), `grdctl rdp disable-view-only`, `grdctl rdp enable`; `systemctl --user enable --now gnome-remote-desktop`.
2. Restrict to the tailnet: if ufw is still inactive, add a minimal nftables/iptables rule rejecting 3389 on `wlo1` (via `/etc/ufw/before.rules` only when T25 is done; otherwise a `systemd` oneshot with `iptables -I INPUT -p tcp --dport 3389 ! -i tailscale0 -j REJECT`), etckeeper commit.
3. Write `~/agents/KB/runbooks/watch-desktop.md`: client apps (Microsoft Remote Desktop / Remmina), address `moodle-lab.tail2ea32e.ts.net:3389`, where the password is.

## Success check
```bash
grdctl status | grep -E "Status|View-only|Port"    # enabled, view-only no, 3389
ss -tlnp | grep 3389
nc -zv 100.99.234.53 3389; nc -zv 192.168.1.20 3389   # first open, second refused
```
Owner connecting once from the phone closes the ticket.

## Rollback
`grdctl rdp disable`; `systemctl --user disable --now gnome-remote-desktop`; remove the firewall rule.
