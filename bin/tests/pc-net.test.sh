#!/usr/bin/env bash
# PT06: pc net against tests/fixtures/net (listener join, port owner, exposure summary, tailscale,
# JSON validity, wall). Read-only — no verb here ever writes anything.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/net"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

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
  "$BIN/pc-net" >/dev/null 2>/dev/null # warm any cache
  t=$(/usr/bin/time -f '%e' "$BIN/pc-net" 2>&1 >/dev/null | tail -1)
  awk -v t="$t" 'BEGIN{exit !(t<=0.5)}' && ok "wall $t s <= 0.5 s budget" || nok "wall budget" "$t s"
fi

[ $bad = 0 ] && echo 'PASS pc-net' || echo 'FAIL pc-net'
exit $bad
