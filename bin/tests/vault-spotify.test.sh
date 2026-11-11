#!/usr/bin/env bash
# T1634-V7: Spotify through the broker on fixtures: a repo fleet-vaultd on a temp state, fake client and refresh values,
# a fake Spotify on loopback. The broker refreshes the access token itself, seals a rotated refresh token, retries once
# on 401, routes /v1/ and /api/token to their pinned hosts, serves the sign-in (authorize redirect, code exchange) and
# never hands a token or the client secret to the caller; pc spotify's helper runs against it with a lease only.
set -uo pipefail
A=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
W=$(mktemp -d); PIDS=()
trap 'for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$W"' EXIT
. "$A/bin/tests/lib/assert.sh"
me=$(id -un)
rnd() { head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
CID="fixturecid$(rnd)" CSEC="fixture-csec-$(rnd)" REFRESH="fixture-refresh-$(rnd)"   # fake, random, never real
export FLEET_VAULT_SOCKET="$W/run/admin.sock" FLEET_VAULT_REGISTRY="$W/registry.toml" NO_PROXY=127.0.0.1 no_proxy=127.0.0.1
export HARNESS_CONFIG=/dev/null SECRET_RAISE_CMD=true
unset FLEET_LEASE_SPOTIFY_TOKEN
mkdir -p "$W/run" "$W/state" "$W/store" "$W/creds"; chmod 700 "$W/store"
S="$A/bin/secret"

# 0. Selftest: every path the broker and the client use is a fixture.
for p in "$FLEET_VAULT_SOCKET" "$FLEET_VAULT_REGISTRY" "$W/store" "$W/state" "$W/creds"; do
  case "$p" in "$W"/*) ;; *) echo "FAIL selftest: $p is outside the fixture"; exit 1 ;; esac
done
ok "selftest: socket, registry, store, state and credentials are fixtures ($W)"

# 1. Units: the shipped rows, host routes, row checks, the client has no lease mode.
unit=$(python3 -I - "$A/lib" "$A/vault/registry.toml" <<'EOF'
import sys; sys.path.insert(0, sys.argv[1])
from vault import registry; from vault.proxy import host_for; from vault.grants import refusal
e = registry.load(sys.argv[2]); t = e["spotify-token"]
print(" ".join(host_for(t, p) for p in ("/v1/me", "/api/token", "/authorize")), host_for(e["openrouter"], "/api/v1/x"))
print(",".join(t.methods), t.oauth["client"], bool(refusal(e["spotify-client"], {})), refusal(t, {}))
base = {"class": "free", "used_in": "x", "modes": ["proxy"], "hosts": ["a.example"], "paths": ["/v1/", "/t"]}
bad = [{"routes": {"/v1/": "b.example"}}, {"routes": {"v1": "a.example"}}, {"methods": ["TRACE"]},
       {"oauth": {"client": "c", "token": "/x", "authorize": "/t"}}, {"oauth": {"client": "c", "token": "/t"}}]
n = 0
for extra in bad:
    try: registry.entry("x", {**base, **extra})
    except registry.RegistryError: n += 1
print(n, len(bad))
from vault.oauth import OAuthProxy; from vault.seal import MemorySealer; from vault.mode import Request
import json, types
class Audit:
    def log(self, ev): pass
sealer = MemorySealer(); sealer.put("spotify-client", b"c:s"); sealer.put("spotify-token", b"r0")
clock, calls = [0.0], []
p = OAuthProxy(sealer, Audit(), clock=lambda: clock[0])
def send(method, host, url, body, headers):
    calls.append(url)
    if url == "/api/token":
        return 200, [], json.dumps({"access_token": f"a{len(calls)}", "expires_in": 3600}).encode()
    return 200, [], b"{}"
p.send = send
lease = types.SimpleNamespace(ticket="T1", agent="", ref="x")
go = lambda: p.handle(Request("GET", "/v1/me"), t, b"r0", lease).status
r = [go(), go()]; clock[0] = 3600 - 60 - 1; r.append(go()); clock[0] = 3600 - 60 + 1; r.append(go())
print(*r, calls.count("/api/token"))
EOF
)
is "routes: /v1/ api, /api/token and /authorize accounts; a one-host row keeps its host" "$(sed -n 1p <<<"$unit")" \
   "api.spotify.com accounts.spotify.com accounts.spotify.com openrouter.ai"
is "spotify-token: GET,POST,PUT, client spotify-client; no lease for the client, free lease for the token" \
   "$(sed -n 2p <<<"$unit")" "GET,POST,PUT spotify-client True None"
is "rows: route to an unpinned host, bad prefix, bad method, oauth path not allowed, oauth incomplete: all refused" \
   "$(sed -n 3p <<<"$unit")" "5 5"
is "expiry: the cached access token serves until expires_in - 60 s, then one refresh (2 in all)" \
   "$(sed -n 4p <<<"$unit")" "200 200 200 200 2"

# 2. Fake Spotify: token endpoint (Basic client) rotates the refresh token; API wants the current access token.
printf '%s\n' "$REFRESH" >"$W/refresh0"
printf '%s:%s' "$CID" "$CSEC" >"$W/client"
cat >"$W/up.py" <<'PY'
import base64, http.server, json, sys, urllib.parse
w = sys.argv[1]; st = {"n": 0, "refresh": open(f"{w}/refresh0").read().strip(), "access": "", "stale": False}
basic = "Basic " + base64.b64encode(open(f"{w}/client", "rb").read()).decode()
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, obj=None):
        b = json.dumps(obj).encode() if obj is not None else b""; self.send_response(code)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def note(self, what):
        open(f"{w}/up.log", "a").write(f"{self.command} {self.path.split('?')[0]} {what}\n")
    def api(self):
        ok = self.headers.get("Authorization") == "Bearer " + st["access"] and st["access"] and not st["stale"]
        self.note(f"bearer={ok}")
        if not ok:
            st["stale"] = False; return self.reply(401, {"error": {"status": 401}})
        if self.path.startswith("/v1/echo"): return self.reply(200, {"auth": self.headers.get("Authorization")})
        if self.command == "PUT": return self.reply(204)
        self.reply(200, {"items": [{"name": "Mine", "tracks": {"total": 3}, "uri": "spotify:playlist:9"}]})
    def do_GET(self):
        if self.path == "/stale": st["stale"] = True; return self.reply(200, {})
        self.api()
    do_PUT = do_DELETE = do_GET
    def do_POST(self):
        if not self.path.startswith("/api/token"): return self.api()
        f = dict(urllib.parse.parse_qsl(self.rfile.read(int(self.headers["Content-Length"])).decode()))
        good = self.headers.get("Authorization") == basic
        if f.get("grant_type") == "refresh_token":
            good = good and f.get("refresh_token") == st["refresh"]
        elif f.get("grant_type") == "authorization_code":
            good = good and f.get("code") == "fixture-code"
        self.note(f"{f.get('grant_type')} basic={self.headers.get('Authorization') == basic} good={good}")
        if not good: return self.reply(400, {"error": "invalid_grant"})
        st["n"] += 1; st["access"] = f"fixture-access-{st['n']}"; st["refresh"] = f"{st['refresh']}-r{st['n']}"
        open(f"{w}/up.tokens", "a").write(st["access"] + "\n" + st["refresh"] + "\n")
        self.reply(200, {"access_token": st["access"], "token_type": "Bearer", "expires_in": 3600, "scope": "s",
                         "refresh_token": st["refresh"]})
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H); open(f"{w}/up.port", "w").write(str(s.server_port)); s.serve_forever()
PY
python3 -I "$W/up.py" "$W" & PIDS+=($!)
cat >"$W/fake-creds" <<'EOF'
#!/bin/sh
cat >"$W_SEALED.$(echo "${3#--name=}")"
printf 'FAKESEAL %s\n' "${3#--name=}" >"$5"
EOF
chmod +x "$W/fake-creds"
W_SEALED="$W/sealed" systemd-socket-activate -l "$W/seal.sock" --inetd -a -E W_SEALED \
  python3 -I "$A/vault/fleet-vault-seal" --store "$W/store" --creds-bin "$W/fake-creds" --peer "$me" 2>/dev/null &
PIDS+=($!)
cp "$A/vault/registry.toml" "$W/registry.toml"
wait-for --label vault-spotify-up --every 0.1 --until "test -s '$W/up.port' && test -S '$W/seal.sock'" >/dev/null
python3 -I "$A/vault/fleet-vaultd" --registry "$W/registry.toml" --state "$W/state" --socket "$FLEET_VAULT_SOCKET" \
  --seal-socket "$W/seal.sock" --cred-dir "$W/creds" --clients "$me" --upstream "http://127.0.0.1:$(cat "$W/up.port")" \
  --cgroup-root "$W/cg" >"$W/d.out" 2>&1 &
PIDS+=($!)
wait-for --label vault-spotify-broker --every 0.1 --until "test -S '$FLEET_VAULT_SOCKET' && test -s '$W/state/port'" >/dev/null
export FLEET_VAULT_URL="http://127.0.0.1:$(cat "$W/state/port")"
code() { curl -s -o "$W/body" -w '%{http_code}' --noproxy '*' "$@"; }
UP="http://127.0.0.1:$(cat "$W/up.port")"

# 3. Leases: the token is free, the client has none.
L=$("$S" grant spotify-token --ticket T9101 2>"$W/g1"); r1=$?
"$S" grant spotify-client --ticket T9101 >"$W/g2" 2>&1; r2=$?
is "grant: spotify-token 0, spotify-client refused 1" "$r1 $r2" "0 1"
B="$FLEET_VAULT_URL/$L/spotify-token"

# 4. Nothing sealed: not signed in (503, pc spotify auth); then a token but no client: 503 naming spotify-client and the
#    helper's setup steps; nothing reaches the token endpoint.
H="$W/home"; mkdir -p "$H"
helper() { HOME="$H" PATH="$A/bin:$PATH" python3 "$A/bin/spotify_api.py" "$@" 2>&1; }
is "no token sealed: 503 saying pc spotify auth" "$(code "$B/v1/me/playlists") $(grep -c 'not signed in.*pc spotify auth' "$W/body")" "503 1"
out=$(FLEET_LEASE_SPOTIFY_TOKEN="$L" helper library); r=$?
is "no token sealed: the helper exits 2 and says pc spotify auth" "$r $(grep -c 'pc spotify auth' <<<"$out")" "2 1"
"$S" add spotify-token <"$W/refresh0" >"$W/a0" 2>&1
is "secret add spotify-token: sealed through the helper" "$? $(cat "$W/sealed.fleet.spotify-token")" "0 $REFRESH"
is "no client sealed: 503 naming spotify-client, no upstream call" \
   "$(code "$B/v1/me/playlists") $(grep -c 'spotify-client is not in the vault' "$W/body") $(cat "$W/up.log" 2>/dev/null | wc -l)" "503 1 0"
out=$(FLEET_LEASE_SPOTIFY_TOKEN="$L" helper library); r=$?
is "no client sealed: the helper exits 2 with the setup steps" "$r $(grep -c 'developer.spotify.com/dashboard' <<<"$out")" "2 1"
"$S" add spotify-client <"$W/client" >"$W/a1" 2>&1
is "secret add spotify-client: sealed through the helper" "$? $(cat "$W/sealed.fleet.spotify-client" | head -c 10)" "0 ${CID:0:10}"

# 5. Refresh inside the broker, cached, routed; the caller never holds a token.
c1=$(code "$B/v1/me/playlists"); cp "$W/body" "$W/b1"
c2=$(code "$B/v1/me/playlists")
is "playlists twice: 200 200, one refresh (Basic client, sealed refresh token), two bearer calls" \
   "$c1 $c2 $(tr '\n' '|' <"$W/up.log")" \
   "200 200 POST /api/token refresh_token basic=True good=True|GET /v1/me/playlists bearer=True|GET /v1/me/playlists bearer=True|"
ev "answer: the playlist, no token in it" 'grep -q "\"Mine\"" "$W/b1" && ! grep -q "fixture-access\|fixture-refresh" "$W/b1"'
is "rotated refresh token sealed by the broker" "$(cat "$W/sealed.fleet.spotify-token")" "$(sed -n 2p "$W/up.tokens")"
code "$B/v1/echo" >/dev/null
ev "an answer that repeats the access token comes back redacted" 'grep -q "Bearer \[redacted\]" "$W/body" && ! grep -q fixture-access "$W/body"'

# 6. Methods and paths: PUT (play) passes with 204, DELETE 405, /v2/ 403; 401 refreshes once with the rotated token.
is "PUT play 204, DELETE 405, outside path 403" \
   "$(code -X PUT -H 'Content-Type: application/json' -d '{}' "$B/v1/me/player/play") $(code -X DELETE "$B/v1/me/x") $(code "$B/v2/x")" \
   "204 405 403"
curl -s --noproxy '*' "$UP/stale" >/dev/null; : >"$W/up.log"
is "401 from the API: one refresh with the rotated token, then 200" "$(code "$B/v1/me/playlists") $(tr '\n' '|' <"$W/up.log")" \
   "200 GET /v1/me/playlists bearer=False|POST /api/token refresh_token basic=True good=True|GET /v1/me/playlists bearer=True|"

# 7. Sign-in: authorize redirect with the client id only; code exchange sealed, answer without tokens.
loc=$(curl -s -D - -o /dev/null --noproxy '*' "$B/authorize?redirect_uri=http%3A%2F%2F127.0.0.1%3A8899%2Fcallback&scope=s" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p')
ev "authorize: 302 to accounts.spotify.com/authorize with client_id and redirect, no client secret" \
   '[[ $loc == "https://accounts.spotify.com/authorize?client_id=$CID&response_type=code&redirect_uri="* ]] && [[ $loc != *"$CSEC"* ]]'
: >"$W/up.log"
c3=$(code -X POST -d 'grant_type=authorization_code&code=fixture-code&redirect_uri=http%3A%2F%2F127.0.0.1%3A8899%2Fcallback' "$B/api/token")
is "sign-in: 200, the answer names the sealed secret only, upstream got the code with the client" \
   "$c3 $(jq -c '[.ok, .sealed, (keys|sort)]' "$W/body") $(tr '\n' '|' <"$W/up.log")" \
   '200 [true,"spotify-token",["ok","scope","sealed"]] POST /api/token authorization_code basic=True good=True|'
is "sign-in: the new refresh token is sealed" "$(cat "$W/sealed.fleet.spotify-token")" "$(tail -1 "$W/up.tokens")"
is "token path refuses a refresh grant from a caller (400) and calls nothing" \
   "$(code -X POST -d "grant_type=refresh_token&refresh_token=x" "$B/api/token") $(wc -l <"$W/up.log")" "400 1"

# 8. pc spotify's helper against the broker: a lease from `secret grant`, a library listing, no secret file read.
out=$(helper library)
is "spotify_api.py library through the broker (own lease)" "$? $out" "0 playlist: Mine (3 tracks)  spotify:playlist:9"
ev "log: a pc-spotify grant, a token use and a client use at accounts.spotify.com" \
   'lg=$("$S" log -n 200 2>&1); grep -qE "grant +spotify-token +ok +ticket=pc-spotify" <<<"$lg" && grep -qE "use +spotify-token +ok" <<<"$lg" && grep -qE "use +spotify-client +ok.*accounts.spotify.com/api/token" <<<"$lg"'
last=$("$S" list --json | python3 -c 'import json,sys; r={x["name"]: x for x in json.load(sys.stdin)}; print(*(r[n]["last_used"] is not None for n in ("spotify-token", "spotify-client")))')
is "list: last use set for spotify-token and spotify-client" "$last" "True True"

# 9. No value anywhere the caller or a log can see.
all="$(cat "$W"/g? "$W"/a0 "$W"/a1 "$W"/b1 "$W/d.out" "$W/state/uses.jsonl"; "$S" log -n 200 2>&1; echo "$out $loc")"
ev "values: client secret, refresh and access tokens never in an output, a log or an answer" \
   '! grep -qF -e "$CSEC" -e "$REFRESH" -e fixture-access -e fixture-refresh <<<"$all"'
exit $bad
