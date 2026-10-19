#!/usr/bin/env bash
# T347-01: notify-owner and the netdata drain deliver with HOME unset, send `@…` literally, keep one log row per push.
# Runs inside bwrap --unshare-net against a fake local ntfy and a fake $HOME; selftest proves no route out.
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
SRC=${NOTIFY_OWNER_SRC:-$BIN/notify-owner}
DRAIN=${NETDATA_DRAIN_SRC:-/usr/local/sbin/netdata-alert-drain}
if [ -z "${NO_SANDBOXED:-}" ]; then
  exec bwrap --dev-bind / / --unshare-net --setenv NO_SANDBOXED 1 --setenv NOTIFY_OWNER_SRC "$SRC" \
    --setenv NETDATA_DRAIN_SRC "$DRAIN" -- bash "$SELF"
fi
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

WORK=$(mktemp -d); trap 'kill "${SRV:-0}" 2>/dev/null; rm -rf "$WORK"' EXIT
if curl -sS -m 3 -o /dev/null https://ntfy.sh 2>/dev/null; then echo 'FAIL selftest: sandbox reaches the network'; exit 1; fi
ok 'selftest: the sandbox has no route to ntfy.sh'

FH="$WORK/home"; mkdir -p "$FH/agents/bin" "$FH/agents/log"
cp "$SRC" "$FH/agents/bin/notify-owner"; cp "$BIN/fleetlib.sh" "$BIN/env.sh" "$FH/agents/bin/"
NO="$FH/agents/bin/notify-owner"

python3 - "$WORK/port" "$WORK/got.jsonl" <<'PY' &
import json, sys, http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        with open(sys.argv[2], 'a') as f:
            f.write(json.dumps({'path': self.path, 'prio': self.headers.get('Priority'), 'body': body}) + '\n')
        self.send_response(200); self.end_headers(); self.wfile.write(b'{}')
    def log_message(self, *a): pass
s = http.server.HTTPServer(('127.0.0.1', 0), H)
open(sys.argv[1], 'w').write(str(s.server_port))
s.serve_forever()
PY
SRV=$!
for _ in $(seq 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
printf 'NTFY_URL=http://127.0.0.1:%s\nNTFY_TOPIC=fixture\n' "$(cat "$WORK/port")" >"$WORK/ntfy.env"
: >"$WORK/got.jsonl"

export HARNESS_CONFIG=/dev/null NTFY_ENV_FILE="$WORK/ntfy.env" NTFY_LOG_FILE="$WORK/notify.log"
sent() { wc -l <"$WORK/got.jsonl"; }
last() { tail -1 "$WORK/got.jsonl" | jq -r "$1"; }

# 1. HOME unset (the root drain unit's environment)
env -u HOME "$NO" "home unset" 2>"$WORK/err1"; is 'HOME unset: exit 0' "$?" 0
is 'HOME unset: the push arrived' "$(last .body)" 'home unset'

# 2. a message starting with @ is sent as text, never a file
HOME="$FH" "$NO" "@/etc/hostname" 2>/dev/null
is '@ message: body is the literal text' "$(last .body)" '@/etc/hostname'

# 3. a newline keeps one log row
HOME="$FH" "$NO" $'line a\nline b' 2>/dev/null
is 'newline: body keeps the newline' "$(last .body)" $'line a\nline b'
is 'newline: one log row per push' "$(wc -l <"$WORK/notify.log")" 3
is 'newline: the row holds an escaped \n' "$(tail -1 "$WORK/notify.log" | cut -f4)" 'line a\nline b'

# 4. a bad priority is refused before sending
n=$(sent); HOME="$FH" "$NO" -p bogus "x" 2>/dev/null
is 'bad priority: exit 2' "$?" 2
is 'bad priority: nothing sent' "$(sent)" "$n"
HOME="$FH" "$NO" -p min "m" 2>/dev/null; is 'priority min is accepted' "$(last .prio)" min

# 5. over 200 chars warns on stderr and still sends
long=$(printf 'x%.0s' $(seq 201))
HOME="$FH" "$NO" "$long" 2>"$WORK/err5"; is 'long: exit 0' "$?" 0
is 'long: one stderr warning' "$(grep -c '201 chars' "$WORK/err5")" 1

# 6. T377: a high push with the same cause within 24 h is logged dup, not sent
export NTFY_KEYS_FILE="$WORK/keys.tsv"
n=$(sent); a='ci failed at declutter (rc 1): ✖ declutter failed: 06-chain-rule'
HOME="$FH" "$NO" -p high -k "$a" "nightly $a · ~/l/ci.log" 2>/dev/null
HOME="$FH" "$NO" -p high -k "$a" "full $a · ~/l/ci-full.log" 2>"$WORK/err7"; is 'dup: exit 0' "$?" 0
is 'dup: one of two same-key pushes sent' "$(( $(sent) - n ))" 1
is 'dup: logged dup in the key ledger' "$(cut -f2 "$NTFY_KEYS_FILE" | tr '\n' ' ')" 'sent dup '
is 'dup: notify.log holds only the sent push' "$(grep -c 'declutter' "$WORK/notify.log")" 1
n=$(sent); HOME="$FH" "$NO" -p high "agent x failed (exit 1)"; HOME="$FH" "$NO" -p high "agent x failed (exit 143)" 2>/dev/null
is 'dup: no -k, texts equal but digits → one sent' "$(( $(sent) - n ))" 1
HOME="$FH" "$NO" -p high "z broke"; rk=$(grep -P '\tz broke$' "$WORK/notify.log" | tail -1 | cut -f1,4 | tr -d '\n' | sha1sum | cut -c1-10)
printf '{"ts":"%s","key":"%s","state":"resolved"}\n' "$(date +%FT%T%z)" "$rk" >>"$FH/agents/log/notify-resolved.jsonl"
n=$(sent); HOME="$FH" "$NO" -p high "z broke" 2>/dev/null; is 'dup: a resolved push of the same cause is sent again' "$(( $(sent) - n ))" 1
n=$(sent); HOME="$FH" "$NO" -p high "agent y failed (exit 1)"; HOME="$FH" "$NO" "agent x failed (exit 1)"
is 'dup: another cause and a default-priority repeat are sent' "$(( $(sent) - n ))" 2
printf '%s\tsent\told cause\told\n' "$(( $(date +%s) - 86401 ))" >>"$NTFY_KEYS_FILE"
n=$(sent); HOME="$FH" "$NO" -p high "old cause"; is 'dup: a key older than 24 h is sent again' "$(( $(sent) - n ))" 1
printf 'NTFY_URL=http://127.0.0.1:1\nNTFY_TOPIC=fixture\n' >"$WORK/dead.env"
NTFY_ENV_FILE="$WORK/dead.env" HOME="$FH" "$NO" -p high "lost cause" 2>/dev/null
n=$(sent); HOME="$FH" "$NO" -p high "lost cause"; is 'dup: a failed send does not block the retry' "$(( $(sent) - n ))" 1
unset NTFY_KEYS_FILE

# 7. the netdata drain, paths swapped to fixtures, delivers a spooled alarm with HOME unset
if [ -r "$DRAIN" ]; then
  mkdir -p "$WORK/spool"
  sed -e "s#/var/spool/netdata-alerts-retry#$WORK/retry#g" -e "s#/var/spool/netdata-alerts#$WORK/spool#g" \
      -e "s#/var/log/netdata-alert.log#$WORK/alert.log#g" -e "s#/[^ ]*/agents/bin/notify-owner#$NO#g" \
      -e "s#/etc/agents/ntfy.env#$WORK/ntfy.env#g" "$DRAIN" >"$WORK/drain"
  is 'drain selftest: no real spool, log or env path left' "$(grep -cE '/var/|/etc/agents' "$WORK/drain")" 0
  echo 'fixture is critical: test alarm' >"$WORK/spool/1-1"
  n=$(sent); env -u HOME -u NTFY_ENV_FILE -u NTFY_LOG_FILE bash "$WORK/drain" 2>"$WORK/err6"
  is 'drain: one push delivered' "$(( $(sent) - n ))" 1
  is 'drain: sent urgent' "$(last .prio)" urgent
  is 'drain: spool and retry are empty' "$(ls "$WORK/spool" "$WORK/retry" | grep -vc ':$\|^$')" 0
  is 'drain: ok row in the alert log' "$(cut -f2 "$WORK/alert.log")" ok
else
  echo "skip drain: $DRAIN not readable"
fi

[ $bad = 0 ] && echo 'PASS notify-owner' || echo 'FAIL notify-owner'
exit $bad
