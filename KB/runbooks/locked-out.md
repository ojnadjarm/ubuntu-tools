# Runbook — locked out of the machine

This machine's host name, user, tailnet name, node IP and LAN IP are the `HARNESS_*` values in
`~/.config/pc-harness/config.env`, and the generated `~/agents/KB/machine.md` prints them all.
Below, `$HOST` / `$USER` / `$TSIP` / `$LANIP` stand for them. Written by T06.

> Print them from a working shell first: `pc status --facts | head -20`.

## Access paths (in order of preference)

1. **Tailscale SSH** — `ssh $USER@$HOST` (or `$TSIP`) from any device in the
   tailnet. No key or password needed: authentication is the tailnet identity. Enabled with
   `sudo tailscale set --ssh` (`RunSSH: true`). The Tailscale SSH server intercepts port 22 for
   traffic arriving over the tunnel, so over the tailnet this path *replaces* OpenSSH.
2. **OpenSSH with a key over the LAN** — `ssh -i <key> $USER@$LANIP`. Bypasses
   Tailscale entirely. Authorized keys: `~/.ssh/authorized_keys`.
3. **OpenSSH with a password** — **disabled since T25** (`PasswordAuthentication no` in
   `/etc/ssh/sshd_config.d/50-agents.conf`). Only paths 1, 2 and 4 exist.
4. **Physical** — the laptop autologins to GNOME on tty2; a console on tty1..tty6 always works.
   This is the last resort and it is not blocked by ufw or sshd.

## Tailscale admin console
https://login.tailscale.com/admin/machines — machines, keys, and the ACL policy file
(`ssh` section). The default tailnet policy already allows a user to SSH into their own devices
(`action: accept`, `src autogroup:member`, `dst autogroup:self`, `users: autogroup:nonroot, root`),
which is what grants path 1. If a device is denied, check that it is signed in as the same user
and is not tagged.

Minimal ACL snippet if the default is ever replaced:
```json
"ssh": [
  { "action": "accept", "src": ["autogroup:member"], "dst": ["autogroup:self"],
    "users": ["autogroup:nonroot", "root"] }
]
```

## Reverting a bad change

### T25 firewall / SSH — exact commands (from a local console or any working SSH)

```bash
# 1. Firewall completely off (restores the pre-T25 "no firewall" state)
sudo ufw --force disable

# 2. Firewall on but LAN/tailnet re-allowed (preferred over a full disable)
sudo ufw allow in on tailscale0
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
sudo ufw --force enable

# 3. Undo the docker source policy only (published ports go back to reachable from anywhere)
sudo cp /root/t25-backup/after.rules /etc/ufw/after.rules   # pristine pre-T25 copy
sudo ufw --force reload
sudo iptables -L DOCKER-USER -n        # must be empty again

# 4. Undo the SSH hardening (brings password auth back)
sudo rm -f /etc/ssh/sshd_config.d/50-agents.conf
sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin'

# 5. Undo everything under /etc via etckeeper
cd /etc && sudo git log --oneline -20          # find the "pre T25" / preceding commit
sudo git checkout <commit> -- ufw ssh
sudo ufw --force reload && sudo sshd -t && sudo systemctl reload ssh
```

Backups of the pre-T25 files: `/root/t25-backup/after.rules`, `/root/t25-backup/default-ufw`.
Never `systemctl restart ssh` — `reload` only, so live sessions survive a bad config.

### General

- **Tailscale SSH:** `sudo tailscale set --ssh=false` (and `--ssh` to put it back).
- **Rule for any agent:** never change sshd/ufw/tailscale without first arming an auto-revert,
  e.g. `sudo systemd-run --on-active=5m --unit=revert-x /bin/sh -c '<undo command>'`, and cancel it
  (`sudo systemctl stop revert-x.timer`) only after a login on the new path has been verified.
  Check none are left behind: `systemctl list-timers --all | grep revert-`.

## Known gaps (T06, still true after T25)
- Tailscale SSH cannot be tested from this machine: a connection from the machine to its own
  tailnet IP is handled by the local OpenSSH, not by the Tailscale SSH server (verified — the
  banner is `SSH-2.0-OpenSSH`, not `SSH-2.0-Tailscale`). It must be tested from a second device.
- The tailnet currently has **only this node** (0 peers). Until the owner installs Tailscale on
  the user's phone or laptop, path 1 has no client.
- `~/.ssh/authorized_keys` holds only this machine's own key
  (`$USER@<this machine>`). No key from an external owner device is installed.

## T25 notes
- ufw is **active** since T25: default deny incoming, allow outgoing, all in on `tailscale0`,
  and 22/4444/8025/8052/8452/19998/19999 tcp from `192.168.1.0/24`. Exposure table in
  `~/agents/KB/machine.md`.
- Docker publishes ports through DNAT and never touches ufw's INPUT chain, so the same policy is
  enforced in `DOCKER-USER` (`/etc/ufw/after.rules`). Match on `-m conntrack --ctorigdstport`,
  **not** `--dport`: DNAT rewrites 8052 to the container's port 80 before FORWARD, so a
  `--dports 8052` rule never matches.
- `tailscale ssh $USER@$HOST` cannot be run **from this machine** — a connection to
  its own tailnet IP is served by the local OpenSSH, and the wrapper's host-key check against the
  coordination server then fails ("No ED25519 host key is known"). Test it from a second device.
- Because password auth is now off and `~/.ssh/authorized_keys` still holds only this machine's
  own key, the only remote way in from a *new* device is Tailscale SSH. Install Tailscale on that
  device first, or add its public key from a local console.
