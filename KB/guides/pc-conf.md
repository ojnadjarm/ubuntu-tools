# Write a config file or systemd drop-in with undo (pc conf put)

Ticket: T1040, T1074 · Last verified: 2026-10-21 by bin/tests/pc-conf.test.sh (55 ok) and real applies of /etc/tmpfiles.d/99-t1040-probe.conf (+ undo) and /etc/apparmor.d/local/{who,hostname,locale}

## When to use
Any persistent change to a sysctl.d, tmpfiles.d, journald/logind/oomd `.conf.d`, unit drop-in (`/etc/systemd/{system,user}/<unit>.d/`, `~/.config/systemd/user/<unit>.d/`), `/etc/netdata/**`, `/etc/default/grub.d/*.cfg` AppArmor local override `/etc/apparmor.d/local/<profile>` or `/etc/modprobe.d/90-agents-*.conf` file. Never `sudo tee`. Not for runtime-only values (`pc kernel sysctl set`) or unit start/stop (`pc units`).

## The path we took
No fleet verb wrote a config file with an undo; six OS tickets (T1041 T1045 T1046 T1052 T1055 T1056) needed one. `pc-conf` reuses pclib's `pc_apply` ledger and `pc undo`, like `pc crashes archive`:
- `put` checks the deny-list and roots, then dry-runs (`would: <path> <old> → <new> (+A -R)` + `diff -u`) or applies.
- Apply: saves `old` (or an `absent` marker) and `new` under `~/agents/backups/conf/<stamp>-<path>/`; ledger before/after = `absent` or `sha:<12 hex>`; writes with `sudo install` (plain outside root for `$HOME`), keeps an existing file's mode (new: 0644); `sudo etckeeper commit` for /etc; then the reload; re-reads the hash (`verified`).
- `pc undo <id>` restores the old bytes or removes the file, commits and reloads again.
- `put` replaces the whole file: for a big file (netdata.conf) pass an edited copy with `--from`.

## Exact commands
```bash
pc conf put /etc/sysctl.d/90-agents.conf --line 'vm.swappiness=10'                          # dry run + diff
pc conf put /etc/systemd/journald.conf.d/90-agents.conf --line '[Journal]' --line 'SystemMaxUse=600M' --reload systemd-journald --apply
pc conf put ~/.config/systemd/user/fleet.slice.d/50-cpu.conf --from /path/new.conf --daemon-reload --apply   # user scope, no sudo
pc conf put /etc/systemd/system/user@.service.d/90-oomd.conf --from f --daemon-reload --apply
pc conf put /etc/apparmor.d/local/who --from f --apply                                       # -Q check, write, apparmor_parser -r
pc conf get /etc/systemd/journald.conf.d/90-agents.conf                                       # content + last ledger id
pc conf put /etc/modprobe.d/90-agents-regdom.conf --line "options cfg80211 ieee80211_regdom=$WIFI_REGDOM" --apply   # T1091, effective at boot
pc undo <id> --apply
```

## Pitfalls (measured)
- Refused with exit 2, `refused: <rule>`: ufw, `/etc/ssh`, sudoers, `~/.claude`, drop-ins or `--reload` of tailscaled/ssh/sshd/dark-eye*/docker*/containerd/sentinel*/agent@*/the orchestrator unit, `..`/`//` paths, symlinks, wrong suffix (systemd ignores a drop-in not ending in `.conf`), anything outside the roots. 30 deny paths + 7 reload units in the test.
- Drop-in deny covers systemd's other lookup dirs: top-level `<type>.d` (`service.d`, `socket.d`: every unit of that type, sshd and tailscaled too) and prefix `<x>-.<type>.d` when a guarded name starts with `<x>-` (`dark-.service.d`, `claude-.service.d`, `docker-.socket.d`); `ssh-*`/`sshd-*` units (sshd-keygen@) count as ssh. The verifier found these bypasses in the first build.
- The deny-list checks paths, not contents: a tmpfiles.d line (`w /etc/sudoers.d/x`, `L /etc/ssh/...`) or `ExecStartPre=` in an allowed drop-in still writes or runs anything as root. Read every diff before `--apply`.
- `get` runs the same path check (`pc conf get /etc/shadow` is refused). An existing file that cannot be read (sudo -n fails) stops `put` with exit 1 before any backup, so `pc undo` can never restore an empty file.
- `(+A -R)` counts every diff body line after the two headers (blank lines and lines starting with `+`/`-` included).
- The internal `write`/`restore` argv is re-parsed by `pc_opt`: a `--reload` token inside it was eaten as a flag and the reload silently never ran (first test run: 3 FAIL). Internal modes are `reload`/`daemon-reload`, no dashes.
- `case /$p/` on an absolute path makes `//etc` and refused every path; normalize checks run on `$p/`.
- `--reload` uses `reload-or-restart`: units without ExecReload (journald) restart.
- Dry run 0.05 s; a real apply + undo of a comment-only tmpfiles file left no file and two etckeeper commits.
- AppArmor `local/<profile>`: only a direct child of `/etc/apparmor.d/local` whose profile `/etc/apparmor.d/<profile>` exists; README, ssh*, tailscale*, bwrap*, docker* and fleet names refused; `--reload`/`--daemon-reload` exit 2 (the reparse is automatic). Before writing, `apparmor_parser -Q -I <tmp>` parses the profile with the new content as `<local/<profile>>` (an `-I` dir wins over /etc/apparmor.d): a syntax error exits 1, nothing written or ledgered. Without it a bad include stayed on disk, ledgered `verified`, and would break that profile at boot.
- T1074 (Ubuntu 26.04): `who` needs `include <abstractions/nameservice-strict>` + `@{run}/systemd/sessions/c@{int} r` (else it prints UID 1000); `hostname`/`locale` need `unix (send, receive) type=stream peer=(label=bwrap|unpriv_bwrap)` for inherited stdio, and `hostname` `owner /tmp/** w` + `owner @{run}/user/@{uid}/** w` for 403+ `file_inherit` denials on redirect files in 3 days (fleet tests' `2>err`). Profiles must stay loaded after `apparmor_parser -r`; denials count with `journalctl -k | grep 'apparmor="DENIED"'`.
- modprobe.d (T1091): only `/etc/modprobe.d/90-agents-*.conf`; a `blacklist`/`install` line is refused (exit 2, dry run too) when `modinfo -n` puts the module under kernel/drivers/{net,input,hid,nvme,ata,scsi,block,md,mmc,usb,pci,thunderbolt}, kernel/net or kernel/fs, or cannot find it. No reload: options apply at the next module load, for cfg80211 the next boot (reloading it drops Wi-Fi). cfg80211 is not in this machine's initramfs, so no `update-initramfs`. `modinfo` lives in /usr/sbin (not on the agent PATH; pc-conf appends it). Read back with `/usr/sbin/modprobe -c | grep <option>`.
- avahi (T1137): `/etc/avahi/avahi-daemon.conf` may change only in `[server]` `allow-interfaces=`/`deny-interfaces=` (exact names; every other byte must match the old file, else exit 2, dry run too). avahi 0.8 compares names with strcasecmp, no globs: `deny-interfaces=veth*` would do nothing, and veth names change per container, so the fix is `allow-interfaces=wlo1` (veth journal lines 86/h → 0; a USB-Ethernet or renamed Wi-Fi gets no mDNS until added). No `--reload`: avahi's reload rereads only services; restart with `pc units restart avahi-daemon --system --apply`, after `pc undo` too.
- Tests: `PC_CONF_ROOT` prefixes every filesystem path; sudo/systemctl/etckeeper/apparmor_parser/modinfo are PATH stubs (the parser stub fails `-Q` on content `BAD`), the test aborts if the real ones are found.

## Links
- Code: ~/agents/bin/pc-conf (ledger: ~/agents/bin/pclib.sh `pc_apply`, ~/agents/bin/pc-undo)
- Tests: `nice -n 19 bash ~/agents/bin/tests/pc-conf.test.sh`
- Design: ~/agent-work/research/2026-10-21/T1037/BACKLOG.md §3
