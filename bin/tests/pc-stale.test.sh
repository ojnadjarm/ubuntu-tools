#!/usr/bin/env bash
# pc-stale on a PC_FIXTURE with stub needrestart/bluetoothctl/systemctl/pc: safe → restart, NetworkManager → held, empty → nothing, --apply calls pc units per safe unit; a mutant without the network hold goes red.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
R=$(mktemp -d); trap 'rm -rf "$R"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

export PC_FIXTURE="$R/fx" PC_LEDGER="$R/changes.jsonl" NR="$R/nr.out" BT="$R/bt.out" LOG="$R/pc.log"
mkdir -p "$PC_FIXTURE/bin"
cat >"$PC_FIXTURE/bin/needrestart" <<'EOF'
#!/bin/sh
cat "$NR"
EOF
cat >"$PC_FIXTURE/bin/bluetoothctl" <<'EOF'
#!/bin/sh
cat "$BT"
EOF
cat >"$PC_FIXTURE/bin/systemctl" <<'EOF'
#!/bin/sh
echo 'Sun 2026-10-25 04:00:00 CET'
EOF
# Stub `pc`: logs argv and drops the restarted unit from the needrestart output, except "sticky.service".
cat >"$PC_FIXTURE/bin/pc" <<'EOF'
#!/bin/sh
echo "$*" >>"$LOG"
[ "$3" = sticky.service ] || { grep -vx "NEEDRESTART-SVC: $3" "$NR" >"$NR.t"; mv "$NR.t" "$NR"; }
echo "rollback: pc undo x"
EOF
chmod +x "$PC_FIXTURE"/bin/*
hdr='NEEDRESTART-VER: 3.11
NEEDRESTART-KSTA: 1'
svc() { printf '%s\n' "$hdr"; for u in "$@"; do printf 'NEEDRESTART-SVC: %s\n' "$u"; done; }
: >"$BT"

svc fwupd.service NetworkManager.service ssh.service docker.service user@$UID.service moodle45-x.service bluetooth.service >"$NR"
out=$("$BIN/pc-stale")
is 'safe units → restart' "$(grep '^restart ' <<<"$out" | paste -sd,)" 'restart fwupd.service,restart bluetooth.service'
is 'NetworkManager → held with the reboot date' "$(grep NetworkManager <<<"$out")" 'held NetworkManager.service (network: next reboot 2026-10-25)'
is 'ssh, docker, user@, Vass held' "$(grep -oE '^held [^ ]+ \([^:]+' <<<"$out" | sed 's/^held //; s/ (/=/' | paste -sd,)" \
  "NetworkManager.service=network,ssh.service=access,docker.service=fleet,user@$UID.service=access,moodle45-x.service=not ours"
is 'dry run ends with would:' "$(tail -1 <<<"$out")" 'would: restart 2 units (--apply)'
[ ! -e "$LOG" ] && ok 'dry run calls no pc units' || nok 'dry run' "called: $(cat "$LOG")"

echo 'Device 00:00:5E:00:53:01 Buds' >"$BT"
is 'bluetooth with a connected device → held' "$("$BIN/pc-stale" | grep bluetooth)" 'held bluetooth.service (bluetooth device connected: next reboot 2026-10-25)'
: >"$BT"

svc >"$NR"
is 'empty → nothing' "$("$BIN/pc-stale")" 'nothing: no service on stale libraries'
echo 'sudo: a password is required' >"$NR"
"$BIN/pc-stale" >/dev/null 2>&1; is 'unreadable needrestart exits 1' "$?" 1

svc fwupd.service NetworkManager.service geoclue.service >"$NR"
out=$("$BIN/pc-stale" --apply); rc=$?
is 'apply exits 0' "$rc" 0
is 'apply restarts each safe unit through pc units --system --apply' "$(paste -sd, "$LOG")" \
  'units restart fwupd.service --system --apply,units restart geoclue.service --system --apply'
is 'apply re-reads needrestart' "$(grep '^after:' <<<"$out")" 'after: 1 stale: NetworkManager.service'

svc sticky.service >"$NR"; : >"$LOG"
"$BIN/pc-stale" --apply >/dev/null 2>"$R/err"; rc=$?
is 'a unit still stale after restart exits 1' "$rc" 1
is 'stderr names it' "$(cat "$R/err")" 'pc stale: still stale after restart: sticky.service'

M="$R/mut"; mkdir -p "$M"; ln -s "$BIN/pclib.sh" "$M/pclib.sh"; [ -e "$BIN/env.sh" ] && ln -s "$BIN/env.sh" "$M/env.sh"
sed 's/NetworkManager\*|//' "$BIN/pc-stale" >"$M/pc-stale"; chmod +x "$M/pc-stale"
svc NetworkManager.service >"$NR"
mut=$("$M/pc-stale" | grep NetworkManager)
[ "$mut" != 'held NetworkManager.service (network: next reboot 2026-10-25)' ] && ok 'mutant without the network hold is red' || nok 'mutant' "still held: $mut"
exit $bad
