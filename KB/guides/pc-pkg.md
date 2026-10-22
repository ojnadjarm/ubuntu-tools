# Install or remove an apt package with a ledger and an undo (pc pkg)

Ticket: T1087 · Last verified: 2026-10-21 by bin/tests/pc-pkg.test.sh (30 ok) and the real `pc pkg install iw nvme-cli --apply` (id dmakkmohohyf, verified)

## When to use
Any agent that needs an Ubuntu package (a diagnostic tool, a build dependency). Never raw `sudo apt-get install`:
47 such calls in 6 weeks left 0 ledger rows and no undo. Not for upgrades (unattended-upgrades owns them) or snaps.

## The path we took
apt has no transaction undo of its own (`apt-mark`/`/var/log/apt/history.log` only record), so `pc pkg` wraps
`apt-get` the way the other pc verbs wrap their tools:
- simulate (`apt-get -s install --no-install-recommends`) → the new set = `Inst` lines without `[old version]`;
- refuse when the simulation also removes or upgrades anything, or a name (asked or pulled in) is on the deny-list;
- `--apply` (outside ci-window) → `pc_apply` ledger row `target: pkg <new set>`, `absent → installed`, then
  `sudo -n nice -n 19 apt-get install -y` under a 600 s timeout, re-read with `pc-pkg state <new set>`;
- rollback = `pc-pkg remove <new set> --apply`; `remove` only accepts packages pc pkg still owns (their last
  finished `pkg` row, rotations included, says `installed`) and refuses when apt would remove anything else;
- the rollback of a remove is `pc-pkg install <set> --apply --auto <the ones apt-mark showauto listed>`, so the
  undo puts the auto marks back.

## Exact commands
```bash
pc pkg install iw nvme-cli                 # would: install nvme-cli (2.2 MB)  |  nothing: already installed
pc pkg install iw nvme-cli --apply         # last line: rollback: pc undo <id>
pc undo <id> --apply                       # = pc pkg remove <new set> --apply
pc pkg remove nvme-cli                     # would: remove nvme-cli (2.2 MB); refused unless a pc pkg row installed it
nice -n 19 bash ~/agents/bin/tests/pc-pkg.test.sh
```

## Pitfalls (measured)
- `iw` was never missing: it sits in `/usr/sbin` (installed 2026-08-26 as a dependency), and agent shells whose PATH lacks
  `/usr/sbin` see `command -v iw` fail. `nvme` lands in `/usr/sbin` too. Check with `dpkg-query -W <pkg>` or
  `pc pkg install <pkg>` (`nothing:`), not `command -v`.
- Only the asked names that are new go on the `apt-get install` line: naming an installed auto package (iw) would
  flip it to manual (`iw set to manually installed` in the simulation), a change the undo cannot see.
- An undone install, later reinstalled by hand, is no longer owned: its last row says `absent`. The row an undo writes
  before it runs does not count yet (no verification line), so `pc undo` of an install can still remove.
- Refusals (deny-list, ownership, ci-window) go to stderr; stdout `nothing:` only means there is nothing to do.
- Deny-list (exit 3): openssh*, ufw, sudo, tailscale, docker*, containerd*, linux-*, systemd*, network-manager*, gdm3,
  apparmor*, also when only a dependency matches. A package installed by hand (not a ledger row) cannot be removed with
  `pc pkg remove` (exit 1): that is the owner's call.
- needrestart prints its service report on stdout during `--apply`; the `rollback:` line is still the last line.
- The size is the summed candidate `Installed-Size` (`apt-cache show`), not the download size.

## Links
- Code: ~/agents/bin/pc-pkg (pclib.sh `pc_apply`, `pc_root`)
- Tests: `nice -n 19 bash ~/agents/bin/tests/pc-pkg.test.sh` (stub sudo/apt-get/apt-cache/apt-mark/dpkg-query, temp ledger, two mutants)
- Design: ~/agent-work/research/2026-10-21/T1079/BACKLOG.md §8
