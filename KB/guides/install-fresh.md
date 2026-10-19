# Prove install.sh / uninstall.sh on a fresh machine (Ubuntu container with systemd)

Ticket: T456 · Last verified: 2026-10-19 by `bin/tests/install-fresh.sh` (PASS ubuntu:24.04 + 26.04, 62 s)

## When to use
After changing install.sh, uninstall.sh, units/, adapters/*/install or anything a fresh box needs. Not for the
`--links` step alone (`bin/tests/bin-links.test.sh` is faster).

## The path we took
- Existing: install.sh had only run on this box; piece tests (bin-links, no-machine-values). Chosen: a Docker
  image per Ubuntu release with systemd as PID 1 and a lingering user `fleet` (no systemd-in-docker image
  needed: 10-line Dockerfile on the official `ubuntu:<ver>` base).
- Sandbox: `--network none`, no bind mounts, not privileged; `--cap-add SYS_ADMIN` + `apparmor=unconfined` only
  so the entrypoint can remount the *private* cgroup namespace rw. The test asserts `none 0 false` from
  `docker inspect` and that the host `~/.local/bin` and `~/.config/systemd/user` are unchanged.
- Input: the working-tree copy of `git ls-files` (what a clone would have, plus uncommitted edits) and
  `fixtures/install-fresh/config.env` (placeholders, `HARNESS_AGENT=claude` to exercise the adapter).
- Checks: install.sh exit 0, units enabled, `harness context`, `pc status --json`, `guide wait`, then
  uninstall.sh leaves 0 links into ~/agents and 0 files under ~/.config/systemd/user.

## Exact commands
```bash
bash ~/agents/bin/tests/install-fresh.sh            # both releases; last line PASS/FAIL
bash ~/agents/bin/tests/install-fresh.sh 26.04      # one release
```
Image build needs network once (apt); the containers never have one. Images `install-fresh:<ver>` stay cached
(~0.7 GB both); `docker rmi install-fresh:24.04 install-fresh:26.04` to reclaim.

## Pitfalls (measured)
- systemd exits silently without the cgroup remount ("Failed to create /init.scope control group: Read-only file
  system"); `--cap-add SYS_ADMIN` alone is not enough, the docker-default AppArmor profile blocks the remount.
- `systemctl is-system-running --wait` right after `docker run` fails with "Failed to connect to bus"; poll until
  `running|degraded`.
- `docker exec` sets no USER: pc-status:134 dies on `USER: unbound variable`; the test passes USER like a login does.
- install.sh used to exit with `pc doctor --quick`'s code (1 on any headless box); now an advisory line.
- uninstall.sh left `agent@<name>.service.d/timeout.conf` (written by install.sh for UNIT_TIMEOUT); now removed.
- Untracked files a fresh clone lacks (2026-10-19): bin/moodlelib.sh (sourced by pc-status:36), bin/claims
  (pc-doctor:45) and 103 more `??` paths; the owner must `git add` them. The test prints such `line N:` errors.
- pc-status:200 defaults KEEPALIVE_UNITS to this box's units, so a fresh box reports 4 `ka_*` FAILs.
- A config.env value with a space must be quoted (it is sourced by bash).

## Links
- Code: ~/agents/install.sh, ~/agents/uninstall.sh
- Tests: ~/agents/bin/tests/install-fresh.sh, fixtures in ~/agents/bin/tests/fixtures/install-fresh/
