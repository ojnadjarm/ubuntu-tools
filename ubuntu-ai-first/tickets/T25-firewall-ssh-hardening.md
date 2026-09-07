# T25 — Firewall and SSH hardening without locking anyone out

**Phase 5 · should · Model: opus · Estimated agent time: 60 min**

## Goal
Only the tailnet and the home LAN can reach services on this laptop; SSH accepts keys (and Tailscale SSH) only — unless the owner said otherwise in PLAN §7 Q2 — and every step auto-reverts if the agent loses access.

## Ground rules (every ticket)
- Read `~/.claude/CLAUDE.md` first. Never commit/push in any user repo; only `etckeeper` commits under `/etc` are allowed.
- Machine facts: `~/agents/README-pc-control.md`, `~/agents/KB/`, `~/agents/ubuntu-ai-first/PLAN.md` (sections 2–4). Run `pc status` before making any statement about the machine; never ask the owner for state you can read.
- Passwordless sudo and `bypassPermissions` are on. Install packages freely with apt/pipx/npm.
- Before changing anything under `/etc`: `sudo etckeeper commit "pre T<NN>"`.
- Finish by running the Success check yourself and pasting its output in your report. Report: what works now, what is left, decisions taken.

## Context / pointers
- ufw installed, inactive. Services on 0.0.0.0: 22, 80, 1025, 4444, 5452, 5900, 7900, 8025, 8052 (docker-proxy publishes ports and **bypasses ufw INPUT rules**; use the `DOCKER-USER` chain or bind published ports to specific IPs). Public IPv4 without CGNAT: any router port-forward would expose these directly.
- Access paths verified in T06 (OpenSSH keys + Tailscale SSH). Owner's devices: phone (Claude app, SSH client), possibly a second laptop; LAN 192.168.1.0/24, tailnet 100.64.0.0/10.
- Auto-revert pattern: before each change, `sudo systemd-run --on-active=5m --unit=revert-T25 sh -c 'ufw --force disable; cp /etc/ssh/sshd_config.d/50-agents.conf.bak ...; systemctl reload ssh'`; after a successful login test from the tailnet (`tailscale ssh`) and from LAN (if possible), `systemctl stop revert-T25.timer`.

## Steps
1. etckeeper commit; ufw rules: default deny incoming, allow in on `tailscale0`, allow from `192.168.1.0/24` to any (LAN), allow 22 from both (already covered), `ufw enable` under the auto-revert timer; test SSH via tailnet, cancel revert.
2. Docker: add `/etc/ufw/after.rules` DOCKER-USER block (standard "ufw-docker" snippet) so published ports honour the same two sources; verify Moodle 8052 still answers from the tailnet and LAN and is rejected from a docker container with an external source spoof is not needed — just confirm the chain exists and counters move.
3. SSH: `/etc/ssh/sshd_config.d/50-agents.conf`: `PasswordAuthentication no` (only if Q2 = default), `PermitRootLogin no`, `MaxAuthTries 4`, `ClientAliveInterval 60`; `sshd -t`; reload under the auto-revert timer; test a key login from the tailnet (`ssh -o PasswordAuthentication=no oscar-nadjar@100.99.234.53 true`), cancel revert.
4. Update `~/agents/KB/runbooks/locked-out.md` with the revert commands and `~/agents/KB/machine.md` with the exposure table.

## Success check
```bash
sudo ufw status verbose | head -12                       # active, deny incoming, tailscale0 + LAN allowed
sudo iptables -L DOCKER-USER -n | head -5                # rules present
ssh -o PasswordAuthentication=no -o BatchMode=yes oscar-nadjar@100.99.234.53 echo key-ok
tailscale ssh oscar-nadjar@moodle-lab echo ts-ok
systemctl list-timers | grep -c revert-T25               # 0 (all reverts cancelled)
curl -sI http://moodle-lab.tail2ea32e.ts.net:8052 | head -1   # HTTP 200/303
```

## Rollback
`sudo ufw --force disable`; delete `50-agents.conf`, `systemctl reload ssh`; `sudo etckeeper vcs revert` of `/etc/ufw`.
