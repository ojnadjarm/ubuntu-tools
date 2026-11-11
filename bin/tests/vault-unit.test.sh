#!/usr/bin/env bash
# T1634-V8: unit mode for the Discord bot on fixtures: the gateway unit's shape (own user, sealed credential, own
# network namespace, root-owned code), the installer in a fixture root, the REST callers on the vault, and live: a
# throwaway system unit with the gateway's hardening reads a fake TPM-sealed credential that this user reads by none of
# 5 routes. Never the real store, the real token or the real gateway unit.
set -uo pipefail
A=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
D="$A/discord-bot"; W=$(mktemp -d); U="fleet-selftest-v8-$$"
trap 'sudo -n systemctl stop "$U.service" >/dev/null 2>&1; sudo -n rm -rf "$W" 2>/dev/null || rm -rf "$W"' EXIT
. "$A/bin/tests/lib/assert.sh"
G="$D/units/discord-bot-gateway.service"; N="$D/units/discord-bot-netproxy.service"
key() { sed -n "s/^$2=//p" "$1"; }

# 0. Selftest: fixture names and places only.
case "$W" in /tmp/*|"${TMPDIR:-/tmp}"/*) ok "selftest: fixture root $W, unit $U, credential fleet.selftest-v8" ;;
  *) nok "selftest" "fixture root outside the temp dir: $W"; exit 1 ;; esac

# 1. The gateway unit: own user, the sealed credential by name, its own network namespace, code from /opt only.
is "gateway: own user and group" "$(key "$G" User) $(key "$G" Group)" "fleet-discord fleet-discord"
is "gateway: token by LoadCredentialEncrypted from the vault's store" "$(key "$G" LoadCredentialEncrypted)" "fleet.discord-bot-token"
ev "gateway: the bot reads it at \$CREDENTIALS_DIRECTORY" 'grep -q "DISCORD_TOKEN_FILE=%d/fleet.discord-bot-token" "$G"'
is "gateway: private network, no home, no new privileges, no capabilities" \
   "$(key "$G" PrivateNetwork) $(key "$G" ProtectHome) $(key "$G" NoNewPrivileges) [$(key "$G" CapabilityBoundingSet)]" "yes yes yes []"
ev "gateway: code and venv from the root-owned /opt/discord-bot, never the repo" \
   '[[ $(key "$G" ExecStart) == /opt/discord-bot/.venv/bin/python\ -E\ -s\ -B\ * ]] && ! grep -q "%h\|/home/\|agents/secrets" "$G" "$N"'
is "gateway: state bound from the installer's path to /var/lib/discord-bot" "$(key "$G" BindPaths)" "@STATE@:/var/lib/discord-bot"
is "netproxy: same user, no credential, network kept" "$(key "$N" User) $(grep -c Credential "$N") $(grep -c PrivateNetwork "$N")" "fleet-discord 0 0"
ev "serve: with the gateway unit enabled the user unit runs the runner only; the token file is never named" \
   'grep -A1 "is-enabled --quiet discord-bot-gateway.service" "$D/bin/serve" | grep -q "exec .*discordbot runner" && ! grep -q "discord-bot-token" "$D/bin/serve"'
ev "REST callers: bot CLI, runner, liaison CLI and relay build Rest through make_rest" \
   '! grep -n "Rest(cfg.api_base, cfg.token())" "$D/discordbot/cli.py" "$D/discordbot/runner.py" "$A/discord-liaison/liaison/cli.py" "$A/discord-liaison/liaison/po.py" && [ "$(grep -l "make_rest(cfg" "$D/discordbot/cli.py" "$D/discordbot/runner.py" "$A/discord-liaison/liaison/cli.py" "$A/discord-liaison/liaison/po.py" | wc -l)" = 4 ]'
ev "liaison triage brief asks its Discord lease by brief line" 'grep -qx "Secrets: discord-bot-token" "$A/discord-liaison/BRIEF.md"'

# 2. Installer in a fixture root: settings filtered, units filled in, code and venv copied, dry run writes nothing.
R="$W/root"; mkdir -p "$W/state"
printf 'DISCORD_GUILD_ID=100\nDISCORD_FORUM_REPLIES=liaison\nDISCORD_OWNER_ID=1 ; touch /x\nFAKE_PASSWORD=x\nDISCORD_TOKEN_FILE=/tmp/x\n' >"$W/config.env"
export DISCORD_BOT_ROOT="$R" DISCORD_BOT_OWNER="$(id -un)" DISCORD_BOT_STATE="$W/state" DISCORD_BOT_CONFIG="$W/config.env"
dry=$("$D/install" 2>&1); rc=$?
is "install: dry run exits 0 and writes nothing" "$rc $([ -e "$R" ] && echo wrote || echo none)" "0 none"
"$D/install" --apply >"$W/install.log" 2>&1; rc=$?
is "install: fixture apply exits 0" "$rc" 0
is "install: bot.env keeps only the allowed DISCORD_* settings with clean values" "$(tr '\n' ' ' <"$R/etc/discord-bot/bot.env")" \
   "DISCORD_GUILD_ID=100 DISCORD_FORUM_REPLIES=liaison "
is "install: state path filled into the gateway unit" "$(key "$R/etc/systemd/system/discord-bot-gateway.service" BindPaths)" \
   "$W/state:/var/lib/discord-bot"
ev "install: code without tests or caches, the venv beside it, the units and sysusers in place" \
   '[ -f "$R/opt/discord-bot/discordbot/gateway.py" ] && [ ! -e "$R/opt/discord-bot/tests" ] && [ -z "$(find "$R/opt/discord-bot" -name __pycache__)" ] && [ -e "$R/opt/discord-bot/.venv/bin/python" ] && [ -f "$R/etc/systemd/system/discord-bot-netproxy.service" ] && [ -f "$R/etc/sysusers.d/discord-bot.conf" ]'
imp=$(cd "$R/opt/discord-bot" && .venv/bin/python -E -s -B -c 'import discord, aiohttp, discordbot.gateway, discordbot.netproxy; print("ok")' 2>&1)
is "install: the copied venv imports discord.py and the bot from /opt (relocated)" "$imp" ok
ev "install: no systemd, user or ACL step in a fixture root" 'grep -q "skip (fixture root): systemctl enable" "$W/install.log" && grep -q "skip (fixture root): setfacl" "$W/install.log"'
unset DISCORD_BOT_ROOT DISCORD_BOT_OWNER DISCORD_BOT_STATE DISCORD_BOT_CONFIG

# 3. Live, on a throwaway unit: own user + the gateway's hardening read a fake sealed credential; this user cannot.
if ! sudo -n true 2>/dev/null; then echo "SKIP live: no sudo -n"; exit $bad; fi
[ ! -e /etc/credstore.encrypted/fleet.selftest-v8 ] && ok "selftest: no fixture in the real store" || nok "selftest" "real store holds fleet.selftest-v8"
VALUE="fixture-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
printf %s "$VALUE" | sudo -n systemd-creds encrypt --with-key=tpm2 --name=fleet.selftest-v8 - "$W/selftest-v8.cred" 2>/dev/null \
  && sudo -n chmod 600 "$W/selftest-v8.cred" || { nok "live: seal the fixture" "systemd-creds encrypt failed"; exit $bad; }
props=(-p LoadCredentialEncrypted="fleet.selftest-v8:$W/selftest-v8.cred")
if getent passwd fleet-discord >/dev/null; then props+=(-p User=fleet-discord -p Group=fleet-discord); else props+=(-p DynamicUser=yes); fi
while IFS= read -r line; do props+=(-p "$line"); done < <(sed -n '/^\[Service\]/,/^\[/p' "$G" | grep -E '^[A-Za-z]+=' |
  grep -vE '^(Type|User|Group|WorkingDirectory|EnvironmentFile|Environment|ExecStart|LoadCredentialEncrypted|BindPaths|Restart|RestartSec|SuccessExitStatus)=')
want=$(printf %s "$VALUE" | sha256sum | cut -c1-64)
got=$(sudo -n systemd-run --quiet --wait --pipe --collect "${props[@]}" /bin/sh -c 'sha256sum "$CREDENTIALS_DIRECTORY/fleet.selftest-v8"' 2>/dev/null | cut -c1-64)
is "live: the unit itself reads the sealed fixture (sha256 match)" "$([ "$got" = "$want" ] && echo match || echo "no match")" match
sudo -n systemd-run --quiet --unit "$U" --collect "${props[@]}" /bin/sleep 120 >/dev/null 2>&1
out=$("$D/bin/gateway-selftest" --unit "$U.service" --cred fleet.selftest-v8 --store "$W/selftest-v8.cred" 2>&1); rc=$?
is "live: other uid, own network namespace, 5 routes read 0 bytes from this user" "$rc" 0
echo "     $out"
sudo -n systemctl stop "$U.service" >/dev/null 2>&1
same=("${props[@]/#User=fleet-discord/User=$(id -un)}"); same=("${same[@]/#Group=fleet-discord/Group=$(id -gn)}")
same=("${same[@]/#DynamicUser=yes/User=$(id -un)}")
sudo -n systemd-run --quiet --unit "$U" --collect "${same[@]}" /bin/sleep 120 >/dev/null 2>&1
ctl=$("$D/bin/gateway-selftest" --unit "$U.service" --cred fleet.selftest-v8 --store "$W/selftest-v8.cred" 2>&1); rc=$?
ev "live control: the same probe fails a unit under this user (it can see a leak)" '[ "$rc" = 1 ] && grep -q "runs as this user" <<<"$ctl" && grep -q "a route read bytes" <<<"$ctl"'
ev "live: the fixture value is in no output" '! grep -qF "$VALUE" <<<"$out$ctl$dry$(cat "$W/install.log")"'
exit $bad
