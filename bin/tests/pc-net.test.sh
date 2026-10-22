#!/usr/bin/env bash
# host-only: live listeners, Moodle containers and tailscale of this box
# PT06: pc net against tests/fixtures/net (listener join, port owner, exposure summary, tailscale,
# JSON validity, wall). Only `wifi pin` writes, to stub nmcli state under mktemp (5c).
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/net"
. "$BIN/tests/lib/budget.sh"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

fx() { PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-net" "$@"; }

# 1. the listener join: 8642 -> dark-eye.service, scope lo.
J=$(fx listeners --json)
[ -n "$J" ] && ok 'listeners --json produces output' || nok 'listeners --json produces output' empty
is 'listeners is valid JSON' "$(jq -e 'type' <<<"$J" 2>/dev/null)" '"array"'
is '8642 scope is lo'            "$(jq -r '.[]|select(.port==8642)|.scope' <<<"$J")" lo
is '8642 unit is dark-eye.service' "$(jq -r '.[]|select(.port==8642)|.unit' <<<"$J")" dark-eye.service
is '19998 scope is all'          "$(jq -r '.[]|select(.port==19998)|.scope' <<<"$J")" all
is '19998 unit is agents-dashboard.service' "$(jq -r '.[]|select(.port==19998)|.unit' <<<"$J")" agents-dashboard.service

# 2. who <port> — docker port owner and a plain unit.
out=$(fx who 8052)
case "$out" in *moodle52-app-1*) ok 'who 8052 -> moodle52-app-1';; *) nok 'who 8052 -> moodle52-app-1' "$out";; esac
out=$(fx who 22)
case "$out" in *sshd*) ok 'who 22 -> sshd';; *) nok 'who 22 -> sshd' "$out";; esac
out=$(fx who 59999 2>&1); rc=$?
is 'who on a closed port exits 1' "$rc" 1

# 3. exposure summary equals the machine.md table shape for 22 (LAN CIDR + tailscale0).
out=$(fx fw)
echo "$out" | grep -E '^ *22 ' | grep -q 192.168.1.0/24 && ok 'fw: 22 lists the LAN CIDR' || nok 'fw: 22 lists the LAN CIDR' "$out"
echo "$out" | grep -E '^ *22 ' | grep -q tailscale0 && ok 'fw: 22 lists tailscale0' || nok 'fw: 22 lists tailscale0' "$out"
raw=$(fx fw --raw)
is 'fw --raw is valid JSON' "$(jq -e 'has("nftables")' <<<"$raw" 2>/dev/null)" true

# 4. tailscale: self + at least two serve mappings.
out=$(fx tailscale --json)
is 'tailscale self.hostname' "$(jq -r .self.hostname <<<"$out")" example-host
is 'tailscale has >= 2 serve entries' "$(jq -e '(.serve|length) >= 2' <<<"$out")" true

# 5. ifaces, sockets, wifi, dns, top all produce JSON/text without crashing.
is 'ifaces --json is an array' "$(fx ifaces --json | jq -e 'type')" '"array"'
is 'sockets --json is an array' "$(fx sockets --json | jq -e 'type')" '"array"'
is 'sockets --pid filters'      "$(fx sockets --pid 1004 --json | jq -e 'all(.pid==1004)')" true
is 'wifi --json reports the SSID' "$(fx wifi --json | jq -r .ssid)" HomeNet
is 'dns --json is an array'     "$(fx dns --json | jq -e 'type')" '"array"'
out=$(fx top --seconds 2 | head -5); [ -n "$out" ] && ok 'top produces output' || nok 'top produces output' empty

# 5b. wifi roams from the wpa.log fixture: ping-pong pair, plain roam, disconnect reason, empty, mutation.
out=$(fx wifi roams --since 7d)
is 'roams summary line' "$(head -1 <<<"$out")" \
  'roams 5 · ping-pong 1 (A→B→A within 10 min) · disconnects 1 (reasons 8) · regdom WORLD resets 2 · AP steer requests 1'
is 'ping-pong row: back to 0a on 5 GHz' "$(sed -n 4p <<<"$out" | cut -c14-)" \
  '02:00:00:00:00:0b → 02:00:00:00:00:0a  5GHz ch52  ping-pong'
is 'plain roam row: band from nmcli CHAN' "$(sed -n 5p <<<"$out" | cut -c14-)" \
  '02:00:00:00:00:0a → 02:00:00:00:00:0c  5GHz ch44'
is 'return after > 10 min is no ping-pong' "$(fx wifi roams --json | jq -c '[.events[] | .ping_pong]')" \
  '[false,false,true,false,false]'
is 'json disconnect reasons' "$(fx wifi roams --json | jq -c .disconnect_reasons)" '[8]'
: > "$WORK/empty.log"
is 'empty journal -> nothing:' "$(PC_NET_WPA_LOG="$WORK/empty.log" fx wifi roams | cut -c1-8)" 'nothing:'
fx wifi nosuch >/dev/null 2>&1; is 'unknown wifi verb exits 2' "$?" 2
mkdir -p "$WORK/mut"; ln -s "$BIN/pclib.sh" "$WORK/mut/pclib.sh"
sed 's/^PINGPONG_SECS=600$/PINGPONG_SECS=0/' "$BIN/pc-net" > "$WORK/mut/pc-net"; chmod +x "$WORK/mut/pc-net"
m=$(PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" "$WORK/mut/pc-net" wifi roams --json | jq .ping_pong)
[ "$m" != 1 ] && ok "mutation (window 0 s) turns the ping-pong case red ($m)" || nok 'mutation turns the ping-pong case red' "$m"

# 5c. dns --stats from the resolvectl stub + resolved.log: line, JSON, empty journal, failures, mutation.
is 'dns --stats line' "$(fx dns --stats | sed 's/lookup [0-9]* ms/lookup N ms/')" \
  'dns cache 25 % hit · flushes 2 · degraded 3 (192.0.2.1, 192.0.2.53) · grace 1 · api lookup N ms'
J=$(fx dns --stats --json)
is 'dns --stats json counts' "$(jq -c '[.cache_hit_pct,.cache_hits,.cache_misses,.transactions,.timeouts,.flushes,.degraded,.grace_recoveries]' <<<"$J")" \
  '[25,200,600,5000,2,2,3,1]'
is 'dns --stats json lookup_ms is a number' "$(jq -r '.lookup_ms|type' <<<"$J")" number
is 'empty resolved journal -> zero counts' "$(PC_NET_RESOLVED_LOG="$WORK/empty.log" fx dns --stats | sed 's/lookup [0-9]* ms/lookup N ms/')" \
  'dns cache 25 % hit · flushes 0 · degraded 0 · grace 0 · api lookup N ms'
is 'failed lookup -> api lookup failed' "$(PC_NET_GETENT_FAIL=1 fx dns --stats --json | jq -c .lookup_ms)" null
PC_NET_RESOLVECTL_FAIL=1 fx dns --stats >/dev/null 2>&1; is 'resolvectl statistics failure exits 1' "$?" 1
sed 's/Using degraded feature set/Using degraded set/' "$BIN/pc-net" > "$WORK/mut/pc-net"; chmod +x "$WORK/mut/pc-net"
m=$(PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" "$WORK/mut/pc-net" dns --stats --json | jq .degraded)
[ "$m" != 3 ] && ok "mutation (degraded pattern) turns the degraded case red ($m)" || nok 'mutation turns the degraded case red' "$m"

# 5c. wifi pin (T1098) on a stateful stub nmcli/systemd-run/systemctl: dry run, weak target refused,
# apply arms the dead-man first, the revert fires without confirm, confirm cancels, undo, mutation.
PF="$WORK/pin"; PS="$WORK/pin/state"; mkdir -p "$PF/bin" "$PS"
cat > "$PF/bin/nmcli" <<'STUB'
#!/usr/bin/env bash
echo "nmcli $*" >> "$PIN_STATE/calls"
case "$*" in
  *TYPE,STATE,CON-UUID*) echo "wifi:${DEV_STATE:-connected}:${DEV_UUID-uuid-1}";;
  *'-g 802-11-wireless.band,802-11-wireless.bssid con show uuid-1')
    cat "$PIN_STATE/band" 2>/dev/null || echo; cat "$PIN_STATE/bssid" 2>/dev/null || echo;;
  *ACTIVE,BSSID,FREQ*) printf '%s\n' 'no:02\:00\:00\:00\:00\:0B:2437 MHz' "yes:${ACTIVE_AP:-02\\:00\\:00\\:00\\:00\\:0A}:${ACTIVE_FREQ:-5260 MHz}";;
  *'-g 802-11-wireless.ssid,802-11-wireless.band,802-11-wireless.bssid con show uuid-1')
    echo HomeNet; cat "$PIN_STATE/band" 2>/dev/null || echo; cat "$PIN_STATE/bssid" 2>/dev/null || echo;;
  *'-g 802-11-wireless.band con show'*) cat "$PIN_STATE/band" 2>/dev/null || echo;;
  *'-g 802-11-wireless.bssid con show'*) cat "$PIN_STATE/bssid" 2>/dev/null || echo;;
  *BSSID,SSID,FREQ,SIGNAL*) printf '%s\n' '02\:00\:00\:00\:00\:0A:HomeNet:5260 MHz:79' \
    '02\:00\:00\:00\:00\:0B:HomeNet:2437 MHz:100' '02\:00\:00\:00\:00\:0C:HomeNet:5180 MHz:40';;
  'con modify uuid-1 802-11-wireless.'*) echo "$5" > "$PIN_STATE/${4#802-11-wireless.}";;
  *'con up uuid-1') :;;
  *) exit 9;;
esac
STUB
cat > "$PF/bin/systemd-run" <<'STUB'
#!/usr/bin/env bash
echo "systemd-run $*" >> "$PIN_STATE/calls"
[ "${SDRUN_RC:-0}" = 0 ] || exit "$SDRUN_RC"
u=; while [ $# -gt 0 ]; do case $1 in --unit=*) u=${1#*=};; --*) ;; *) break;; esac; shift; done
printf '%q ' "$@" > "$PIN_STATE/timer-$u"
STUB
cat > "$PF/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
shift; v=$1; shift
case $v in
  stop) for t in "$@"; do rm -f "$PIN_STATE/timer-${t%.timer}"; done;;
  is-active) [ "$1" = -q ] && shift; [ -e "$PIN_STATE/timer-${1%.timer}" ];;
esac
STUB
printf '#!/usr/bin/env bash\necho "default via 10.0.0.1 dev wlo1"\n' > "$PF/bin/ip"
printf '#!/usr/bin/env bash\nexit "${PING_RC:-0}"\n' > "$PF/bin/ping"
printf '#!/usr/bin/env bash\necho "{\\"BackendState\\":\\"${TS_STATE:-Running}\\"}"\n' > "$PF/bin/tailscale"
chmod +x "$PF/bin/"*
px() { PIN_STATE="$PS" PC_FIXTURE="$PF" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/pin.jsonl" "${PCNET:-$BIN/pc-net}" "$@"; }
fire() { local f="$PS/timer-pc-net-wifi-pin-revert-$1" c; c=$(<"$f"); rm -f "$f"; eval "PIN_STATE='$PS' PC_FIXTURE='$PF' XDG_RUNTIME_DIR='$WORK' PC_LEDGER='$WORK/pin.jsonl' $c"; }
is 'pin band auto when unset -> nothing:' "$(px wifi pin band auto)" 'nothing: wifi band already auto'
is 'pin band a dry run -> would:' "$(px wifi pin band a)" 'would: wifi band auto → a'
out=$(px wifi pin bssid 02:00:00:00:00:0c --apply); rc=$?
is 'weak target (signal 40) refused, exit 1' "$rc:${out%% *}" '1:refused:'
[ ! -e "$PS/bssid" ] && [ -z "$(ls "$PS" | grep timer-)" ] && ok 'refused pin changed nothing, armed nothing' || nok 'refused pin changed nothing' "$(ls "$PS")"
out=$(px wifi pin band a --apply)
is 'apply pins band a' "$(cat "$PS/band")" a
[ -e "$PS/timer-pc-net-wifi-pin-revert-band" ] && ok 'apply armed the dead-man timer' || nok 'apply armed the dead-man timer' "$(ls "$PS")"
is 'apply ledger row verified' "$(tail -1 "$WORK/pin.jsonl" | jq -r .verified)" true
grep -q '^rollback: pc undo ' <<<"$out" && ok 'apply prints the rollback line' || nok 'apply prints the rollback line' "$out"
a=$(grep -n '^systemd-run' "$PS/calls" | head -1 | cut -d: -f1); b=$(grep -n 'con modify' "$PS/calls" | head -1 | cut -d: -f1)
[ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && ok 'dead-man armed before the modify' || nok 'dead-man armed before the modify' "run $a modify $b"
fire band >/dev/null
is 'revert fires without confirm -> band auto' "$(cat "$PS/band")" ''
is 'revert ledgered and verified' "$(tail -1 "$WORK/pin.jsonl" | jq -r '"\(.verified) \(.observed)"')" 'true auto'
px wifi pin band a --apply >/dev/null
export DEV_STATE=disconnected DEV_UUID=
out=$(fire band 2>&1); rc=$?
is 'revert after the pin broke the link -> band auto' "$rc:$(cat "$PS/band")" '0:'
unset DEV_STATE DEV_UUID
px wifi pin band a --apply >/dev/null; rm -f "$PS/timer-pc-net-wifi-pin-revert-band"
id=$(grep -o '"id":"[^"]*","session[^}]*"target":"wifi band"' "$WORK/pin.jsonl" | tail -1 | cut -d'"' -f4)
DEV_STATE=disconnected DEV_UUID= PIN_STATE="$PS" PC_FIXTURE="$PF" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/pin.jsonl" "$BIN/pc-undo" undo "$id" --apply >/dev/null 2>&1
is 'pc undo while the wifi is disconnected -> band auto' "$(cat "$PS/band")" ''
px wifi pin bssid 02:00:00:00:00:0a --apply >/dev/null
out=$(TS_STATE=Stopped px wifi pin --confirm); rc=$?
[ "$rc" = 1 ] && [ -e "$PS/timer-pc-net-wifi-pin-revert-bssid" ] && ok 'confirm refused while tailscale is not Running' || nok 'confirm refused while tailscale is not Running' "$rc $out"
out=$(PING_RC=1 px wifi pin --confirm); rc=$?
[ "$rc" = 1 ] && [ -e "$PS/timer-pc-net-wifi-pin-revert-bssid" ] && ok 'confirm refused without a gateway reply' || nok 'confirm refused without a gateway reply' "$rc $out"
out=$(ACTIVE_AP='02\:00\:00\:00\:00\:0B' ACTIVE_FREQ='2437 MHz' px wifi pin --confirm); rc=$?
[ "$rc" = 1 ] && [ -e "$PS/timer-pc-net-wifi-pin-revert-bssid" ] && ok 'confirm refused while another AP is in use' || nok 'confirm refused while another AP is in use' "$rc $out"
out=$(px wifi pin --confirm)
is 'confirm cancels the revert' "${out%% *}:$(ls "$PS" | grep -c timer-)" 'confirmed::0'
is 'confirmed pin stays' "$(cat "$PS/bssid")" 02:00:00:00:00:0A
id=$(grep -o '"id":"[^"]*","session[^}]*"target":"wifi bssid"' "$WORK/pin.jsonl" | tail -1 | cut -d'"' -f4)
PIN_STATE="$PS" PC_FIXTURE="$PF" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/pin.jsonl" "$BIN/pc-undo" undo "$id" --apply >/dev/null 2>&1
is 'pc undo of the pin -> bssid auto' "$(cat "$PS/bssid")" ''
out=$(SDRUN_RC=1 px wifi pin band bg --apply 2>&1)
is 'dead-man that fails to arm leaves band unchanged' "$(cat "$PS/band")" ''
px wifi pin band x >/dev/null 2>&1; is 'bad band exits 2' "$?" 2
px wifi pin bssid nope >/dev/null 2>&1; is 'bad bssid exits 2' "$?" 2
sed 's/^PIN_MIN_SIGNAL=60$/PIN_MIN_SIGNAL=0/' "$BIN/pc-net" > "$WORK/mut/pc-net-pin"; chmod +x "$WORK/mut/pc-net-pin"
m=$(PCNET="$WORK/mut/pc-net-pin" px wifi pin bssid 02:00:00:00:00:0c 2>&1)
[ "${m%% *}" != refused: ] && ok "mutation (min signal 0) turns the weak-target case red ($m)" || nok 'mutation turns the weak-target case red' "$m"

# 6. default output = ifaces + listeners + tailscale, in that order.
out=$(fx)
l_ifaces=$(grep -n '^tailscale0' <<<"$out" | head -1 | cut -d: -f1)
l_listen=$(grep -n '8642' <<<"$out" | head -1 | cut -d: -f1)
l_ts=$(grep -n '^tailscale ' <<<"$out" | head -1 | cut -d: -f1)
if [ -n "$l_ifaces" ] && [ -n "$l_listen" ] && [ -n "$l_ts" ] && [ "$l_ifaces" -lt "$l_listen" ] && [ "$l_listen" -lt "$l_ts" ]; then
  ok 'default output has ifaces, listeners, then tailscale'
else
  nok 'default output has ifaces, listeners, then tailscale' "$out"
fi

# 7. usage, unknown verb/option.
fx -h >/dev/null; is '-h exits 0' "$?" 0
fx nosuchverb >/dev/null 2>&1; is 'unknown verb exits 2' "$?" 2
fx --nosuchflag >/dev/null 2>&1; is 'unknown option exits 2' "$?" 2
grep -q '^  pc net ' <<<"$("$BIN/pc" help)" && ok 'pc help lists pc net' || nok 'pc help lists pc net' 'missing'

# 8. wall budget (live machine, no fixture): ≤ 0.5 s warm for the default snapshot.
if command -v /usr/bin/time >/dev/null; then
  # A private cache and a refusing sudo (T1136): no root `ss`, the live listeners cache untouched.
  mkdir -p "$WORK/live/nosudo"; printf '#!/bin/sh\nexit 1\n' >"$WORK/live/nosudo/sudo"; chmod +x "$WORK/live/nosudo/sudo"
  lv() { PATH="$WORK/live/nosudo:$PATH" XDG_RUNTIME_DIR="$WORK/live" "$@"; }
  lv "$BIN/pc-net" >/dev/null 2>/dev/null # warm any cache
  t=$(lv /usr/bin/time -f '%e' "$BIN/pc-net" 2>&1 >/dev/null | tail -1)
  b=$(budget 0.5)
  awk -v t="$t" -v b="$b" 'BEGIN{exit !(t<=b)}' && ok "wall $t s <= $b s budget" || nok "wall $b s budget" "$t s"
fi

[ $bad = 0 ] && echo 'PASS pc-net' || echo 'FAIL pc-net'
exit $bad
