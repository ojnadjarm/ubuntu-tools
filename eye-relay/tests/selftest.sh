#!/bin/bash
# Sandboxed selftest: N lines through fake bridge -> eye-relay -> spool -> eye-channel -> fake MCP client,
# with a relay restart at N/3 and a session (channel) kill -9 at 2N/3. Usage: selftest.sh [N] [gap_seconds]
set -u
N=${1:-100}; GAP=${2:-0.1}
HERE=$(cd "$(dirname "$0")" && pwd); BIN=$HOME/agents/bin
T=$(mktemp -d "${TMPDIR:-/tmp}/eye-relay-test.XXXX")
PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
SECRET=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
printf '{"secret":"%s","port":%s}\n' "$SECRET" "$PORT" > "$T/config.json"
export DARK_EYE_CONFIG=$T/config.json EYE_RELAY_STATE=$T/state EYE_RELAY_POLL_MS=${EYE_RELAY_POLL_MS:-3000} EYE_CHANNEL_SETTLE=0.5
REAL=${XDG_CONFIG_HOME:-$HOME/.config}/dark-eye/config.json
pids=()
cleanup() { kill "$(cat "$T/relay.pid")" "${pids[@]}" 2>/dev/null; sleep 0.5; rm -rf "$T"; }
trap cleanup EXIT

# Sandbox proof before anything runs: fixture port, fixture secret, fixture state dir.
python3 - "$REAL" "$T/config.json" <<'EOF' || { echo "SANDBOX FAIL"; exit 1; }
import json, sys
real, fx = (json.load(open(p)) for p in sys.argv[1:3])
assert fx["port"] != real.get("port", 8642), "fixture port equals the real bridge port"
assert fx["secret"] != real["secret"], "fixture secret equals the real one"
EOF
case $EYE_RELAY_STATE in "$HOME"/agents/eye-relay/state*) echo "SANDBOX FAIL: real state dir"; exit 1;; esac
echo "sandbox ok: port $PORT, state $EYE_RELAY_STATE"

node "$HERE/fake-bridge.js" "$PORT" "$SECRET" & pids+=($!)
start_relay() { "$BIN/eye-relay" main & echo $! > "$T/relay.pid"; }
start_client() { python3 "$HERE/fake-client.py" main "$T/received" "$BIN/eye-channel" & CLIENT=$!; pids+=($CLIENT); }
start_relay; start_client; sleep 1.5

push() { curl -s -o /dev/null -H "x-dark-eye-key: $SECRET" -d "{\"text\":\"t38 line $1\"}" "http://127.0.0.1:$PORT/push?brain=main"; }
real_conns=0
RPORT=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("port",8642))' "$REAL")
t0=$(date +%s)
for i in $(seq -w 1 "$N"); do
  push "$i"
  if [ "$((10#$i))" -eq $((N / 3)) ]; then
    ( rp=$(cat "$T/relay.pid"); s=$(date +%s.%N); kill -TERM "$rp"; while kill -0 "$rp" 2>/dev/null; do sleep 0.1; done
      echo "relay restart: drained in $(python3 -c "import time;print(round(time.time()-$s,1))")s"; start_relay ) &
  fi
  if [ "$((10#$i))" -eq $((2 * N / 3)) ]; then
    kill -9 $(pgrep -P "$CLIENT") "$CLIENT" 2>/dev/null; sleep 2; start_client; echo "session kill -9 + restart"
  fi
  c=$(ss -tnp "dport = :$RPORT" 2>/dev/null | grep -c "pid=$(cat "$T/relay.pid")," )
  real_conns=$((real_conns + c))
  sleep "$GAP"
done
for _ in $(seq 120); do [ "$(sort -u "$T/received" 2>/dev/null | wc -l)" -ge "$N" ] && break; sleep 1; done
elapsed=$(( $(date +%s) - t0 ))
python3 - "$T/received" "$N" "$elapsed" "$real_conns" <<'EOF'
import sys
lines = [l.strip() for l in open(sys.argv[1]) if l.strip()] if __import__("os").path.exists(sys.argv[1]) else []
n = int(sys.argv[2])
want = [f"VOICE: t38 line {i:0{len(str(n))}d}" for i in range(1, n + 1)]
seen, uniq = set(), []
for l in lines:
    if l not in seen: seen.add(l); uniq.append(l)
lost = [w for w in want if w not in seen]
print(f"emitted {n} · received {len(uniq)} · lost {len(lost)} · duplicates {len(lines) - len(uniq)} · in order {uniq == [w for w in want if w in seen]} · elapsed {sys.argv[3]}s · real-bridge connections {sys.argv[4]}")
sys.exit(0 if not lost and sys.argv[4] == "0" else 1)
EOF
