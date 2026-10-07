# Runbook: reboot the machine

1. Warn first: `notify-owner -p high -t "reboot" "rebooting $HARNESS_HOST, back in ~1 min"`.
2. Check nothing is mid-flight: `pc status --check` and `agents-status` (no agent run in flight).
3. `sudo systemctl reboot`.
4. From the same or another machine, wait for SSH: `until ssh -o ConnectTimeout=3 "$USER@$HARNESS_TAILNET_FQDN" true; do sleep 5; done`
5. Verify: `pc status --check` (exit 0). If docker stacks are down:
   `docker compose -f ~/moodle-envs/shared/docker-compose.yml up -d && docker compose -f ~/moodle-envs/5.2/docker-compose.yml up -d`
6. If the desktop session did not come back, screenshots fail: check `loginctl list-sessions` for a
   `wayland` session on seat0 (GDM autologin should recreate it).

## Unattended reboot policy (T23)

**Owner decision 2026-09-13: no automatic reboots.** `MAINT_AUTO_REBOOT=0` in
`~/.config/pc-harness/config.env` makes `maintenance-run` refuse every reboot with reason
`auto-reboot-disabled-by-owner` before any other gate, push once ("reboot required … do it
yourself when convenient") and exit 3. The owner reboots by hand (steps above). Setting the
switch back to 1 restores the gated behaviour below. Unset also means 0 (T116).

T116 (2026-09-27, rebooted at 04:06 despite the switch): `env.sh` sourced config.env without
exporting it, and a child `maintenance-run` skips `env.sh` once `HARNESS_ENV_LOADED` is set, so
under `agent-run` the switch never arrived and the old `:-1` default rebooted. `env.sh` now
exports every config.env key (`set -a`); `bin/tests/maintenance-run.test.sh` replays the unit's
chain in bwrap with a pending reboot and shutdown/sudo stubbed.

T118: the fleet guard (`bin/guards/_guard`, on every headless agent's PATH) obeys the same switch.
With `MAINT_AUTO_REBOOT` 0 or unset it refuses `reboot`, `shutdown`, `poweroff`, `halt` and
`sudo systemctl reboot|poweroff|halt|kexec|soft-reboot` at any hour (exit 3); with 1 it allows them
only 04:00–05:00. Test: `bash ~/agents/bin/tests/guards.test.sh` (stubs only).

Only `maintenance-run` may reboot this machine. No agent, and no unattended-upgrades run, may
reboot outside it (`Automatic-Reboot "false"`).

Gates (only with `MAINT_AUTO_REBOOT=1`) — all four must pass or the reboot waits for the next Sunday window:
1. 04:00–05:00 Europe/Madrid;
2. `pc status --check` exit 0;
3. `boot-check.sh` exit 0;
4. no `agent@*.service` active besides `agent@maintenance`.

Sequence: `maintenance-run` → gates → `notify-owner -p high "rebooting $HARNESS_HOST in 5 min"` →
`sudo shutdown -r +5` → after boot the sentinel (15 min timer) verifies and the 08:00 digest
reports. Exit 3 = reboot required but refused (one push, retried next Sunday); exit 4 = scheduled.

Dry-run the whole decision without touching anything:
`maintenance-run --dry-run --assume-reboot` (prints the refusal and its reason).
Test: `bash ~/agents/bin/tests/maintenance-run.test.sh` (fixture config, `shutdown` stubbed).

Manual reboot (owner present) still follows the steps above: warn, check, `sudo systemctl reboot`,
then `boot-check.sh`.
