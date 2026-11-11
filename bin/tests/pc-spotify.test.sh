#!/usr/bin/env bash
# T472: `pc spotify` and spotify_api.py on stubs — fake playerctl/pactl/sleep/secret on PATH, a fake $HOME, a patched
# urlopen inside bwrap --unshare-net, a fixture vault socket and URL; no live player, sink, vault or Web API is touched
# (selftest proves the stubs resolve first). T1634-V7: the helper holds a lease only; the broker side is vault-spotify.test.sh.
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
if [ -z "${SP_SANDBOXED:-}" ] && bwrap --dev-bind / / --unshare-net true 2>/dev/null; then
  exec bwrap --dev-bind / / --unshare-net --setenv SP_SANDBOXED 1 -- bash "$SELF"
fi
PC="$BIN/pc-spotify" API="$BIN/spotify_api.py"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
STUB="$WORK/stub" FH="$WORK/home" LOG="$WORK/calls.log"
mkdir -p "$STUB" "$FH/agents/secrets"; : >"$LOG"
export FLEET_VAULT_SOCKET="$WORK/vault.sock" FLEET_VAULT_URL="http://127.0.0.1:9"
unset FLEET_LEASE_SPOTIFY_TOKEN
. "$HOME/agents/bin/tests/lib/assert.sh"
has() { grep -qF -- "$2" <<<"$3" && ok "$1" || nok "$1" "no '$2' in: $3"; }
sp()  { PATH="$STUB:$PATH" HOME="$FH" HARNESS_CONFIG=/dev/null SP_LOG="$LOG" SP_SINK="$WORK/sink" \
        BUDS_MAC=00:00:5E:00:53:01 PC_LEDGER="$WORK/ledger.jsonl" "$PC" "$@"; }

cat >"$STUB/playerctl" <<'EOF'
#!/bin/bash
echo "playerctl $*" >>"$SP_LOG"
[ "$1" = -l ] && { [ -n "${SP_DOWN:-}" ] || echo spotify; exit 0; }
shift 2
case "$1 ${2:-}" in
  "status ") echo Playing;;
  "metadata xesam:artist") echo 'Fake Artist';;
  "metadata xesam:title") echo 'Fake Title';;
  "metadata xesam:album") echo 'Fake Album';;
  "metadata xesam:url") echo 'https://open.spotify.com/track/FAKE';;
  "metadata mpris:length") echo 210000000;;
  "position ") echo 75.3;;
  "volume ") echo 0.42;;
esac
exit 0
EOF
cat >"$STUB/pactl" <<'EOF'
#!/bin/bash
echo "pactl $*" >>"$SP_LOG"
cur=$(cat "$SP_SINK" 2>/dev/null || echo 5)
case "$*" in
  'list sink-inputs') printf 'Sink Input #42\n\tSink: %s\n\tProperties:\n\t\tapplication.name = "Spotify"\n' "$cur";;
  '-f json list sink-inputs') printf '[{"index":42,"sink":%s,"properties":{"application.name":"Spotify"}}]\n' "$cur";;
  'list sinks short') printf '5\talsa_output.pci-0000_00_1f.3.analog-stereo\tPipeWire\n7\tbluez_output.00_00_5E_00_53_01.1\tPipeWire\n';;
  get-default-sink) echo alsa_output.pci-0000_00_1f.3.analog-stereo;;
  'move-sink-input 42 alsa_output.pci-0000_00_1f.3.analog-stereo') echo 5 >"$SP_SINK";;
  'move-sink-input 42 bluez_output.00_00_5E_00_53_01.1') echo 7 >"$SP_SINK";;
  move-sink-input*) exit 1;;
esac
exit 0
EOF
cat >"$STUB/pw-dump" <<'EOF'
#!/bin/bash
n() { printf '{"id":%s,"type":"PipeWire:Interface:Node","info":{"props":{"object.serial":%s,"node.name":"%s","media.class":"Audio/Sink"}}}' "$1" "$1" "$2"; }
echo "[$(n 5 alsa_output.pci-0000_00_1f.3.analog-stereo),$(n 7 bluez_output.00_00_5E_00_53_01.1)]"
EOF
printf '#!/bin/sh\nexit 0\n' >"$STUB/sleep"
cat >"$STUB/secret" <<'EOF'
#!/bin/bash
echo "secret $*" >>"$SP_LOG"
[ -n "${SP_LEASE:-}" ] || { echo 'secret: spotify-token is not in the vault' >&2; exit 1; }
echo "$SP_LEASE"
EOF
chmod +x "$STUB"/*

# 0. selftest: the stubs win on PATH, the fake HOME has no Web API secrets, the sandbox has no route out.
for c in playerctl pactl pw-dump sleep secret; do
  is "selftest: $c resolves to the stub" "$(PATH="$STUB:$PATH" command -v $c)" "$STUB/$c"
done
[ -e "$FH/agents/secrets/spotify.env" ] && nok 'selftest: fake HOME has no spotify.env' present || ok 'selftest: fake HOME has no spotify.env'
case "$FLEET_VAULT_SOCKET $FLEET_VAULT_URL" in "$WORK/vault.sock http://127.0.0.1:9") ok 'selftest: vault socket and URL are fixtures';;
  *) nok 'selftest: vault socket and URL are fixtures' "$FLEET_VAULT_SOCKET $FLEET_VAULT_URL";; esac
if [ -n "${SP_SANDBOXED:-}" ]; then
  python3 -c 'import socket; socket.create_connection(("1.1.1.1", 443), 2)' 2>/dev/null \
    && nok 'selftest: sandbox has no network' reachable || ok 'selftest: sandbox has no network'
fi

# 1. --help and argument errors.
out=$(sp --help); is '--help exits 0' "$?" 0; has '--help lists the verbs' 'status [--json]' "$out"
sp nosuchverb >/dev/null 2>&1; is 'an unknown verb exits 2' "$?" 2
sp vol 101 >/dev/null 2>&1; is 'vol 101 exits 2' "$?" 2
sp vol abc >/dev/null 2>&1; is 'vol abc exits 2' "$?" 2
sp seek xyz >/dev/null 2>&1; is 'seek xyz exits 2' "$?" 2
sp open https://example.com/x >/dev/null 2>&1; is 'open of a non-Spotify URL exits 2' "$?" 2
: >"$LOG"; sp output nosuchsink >/dev/null 2>&1; is 'output to an unknown sink exits 1' "$?" 1
grep -q move-sink-input "$LOG" && nok 'output to an unknown sink moves nothing' moved || ok 'output to an unknown sink moves nothing'
sp search >/dev/null 2>&1; is 'search with no query exits 2' "$?" 2

# 2. the app is not on the bus: every player verb refuses with 1.
out=$(SP_DOWN=1 sp play 2>&1); is 'play with no app exits 1' "$?" 1; has 'play says not running' 'not running' "$out"
SP_DOWN=1 sp status >/dev/null 2>&1; is 'status with no app exits 1' "$?" 1

# 3. happy path on the stubbed player.
out=$(sp status)
has 'status prints the state' 'state: Playing' "$out"
has 'status prints position / length as m:ss' 'position: 1:15 / 3:30' "$out"
has 'status prints volume as a percentage' 'volume: 42' "$out"
has 'status names the stream sink by alias' 'output: speakers (alsa_output.pci-0000_00_1f.3.analog-stereo)' "$out"
j=$(sp status --json)
is 'status --json types and values' "$(jq -r '[.state,.artist,.position==75.3,.length==210,.volume,.output]|map(tostring)|join(",")' <<<"$j")" \
  'Playing,Fake Artist,true,true,42,speakers'
: >"$LOG"; is 'vol 55 prints the new volume' "$(sp vol 55)" 'volume: 55'
has 'vol 55 sets 0.55 on the player' 'playerctl -p spotify volume 0.55' "$(cat "$LOG")"
: >"$LOG"; sp toggle; has 'toggle sends play-pause' 'playerctl -p spotify play-pause' "$(cat "$LOG")"
: >"$LOG"; sp seek +10 >/dev/null; has 'seek +10 is relative' 'playerctl -p spotify position 10+' "$(cat "$LOG")"
: >"$LOG"; sp next; has 'next sends next' 'playerctl -p spotify next' "$(cat "$LOG")"
is 'output with no argument prints the current sink' "$(sp output)" 'output: speakers (alsa_output.pci-0000_00_1f.3.analog-stereo)'
: >"$LOG"; out=$(sp output earbuds)
has 'output earbuds moves stream 42 to the bluez sink' 'pactl move-sink-input 42 bluez_output.00_00_5E_00_53_01.1' "$(cat "$LOG")"
has 'output earbuds prints the undo' 'rollback: pc undo ' "$out"
has 'output earbuds prints the new sink' 'output: earbuds (bluez_output.00_00_5E_00_53_01.1)' "$out"
is 'output earbuds is ledgered and verified' \
  "$(jq -sr '[.[0].target, .[0].after, .[1].verified] | map(tostring) | join(" ")' "$WORK/ledger.jsonl" 2>/dev/null)" \
  'stream.Spotify bluez_output.00_00_5E_00_53_01.1 true'
: >"$LOG"; sp output speakers >/dev/null
has 'output speakers moves stream 42 to the analog sink' 'pactl move-sink-input 42 alsa_output.pci-0000_00_1f.3.analog-stereo' "$(cat "$LOG")"

# 4. the Web API without credentials prints the setup steps and exits 2.
out=$(sp search 'x' 2>&1); is 'search with no credentials exits 2' "$?" 2
has 'search with no credentials explains the setup' 'developer.spotify.com/dashboard' "$out"

# 5. spotify_api.py with a patched urlopen (no socket is ever opened).
api() {  # api <http-status> <args...> — runs spotify_api.py under the fake HOME; requests go to $WORK/req.jsonl
  local code=$1; shift
  PATH="$STUB:$PATH" SP_LOG="$LOG" HOME="$FH" WORK="$WORK" CODE="$code" python3 - "$API" "$@" <<'PY'
import io, json, os, runpy, sys, urllib.error, urllib.request
work, code = os.environ["WORK"], int(os.environ["CODE"])
R = {"me/player/devices": {"devices": [{"id": "ph", "type": "Smartphone", "name": "Phone"},
                                       {"id": "pc", "type": "Computer", "name": "Laptop"}]},
     "search": {"tracks": {"items": [{"artists": [{"name": "A"}], "name": "T", "uri": "spotify:track:1"}]},
                "albums": {"items": []}, "playlists": {"items": [None, {"name": "P", "uri": "spotify:playlist:2"}]}},
     "me/playlists": {"items": [{"name": "Mine", "tracks": {"total": 3}, "uri": "spotify:playlist:9"}]},
     "api/token": {"access_token": "NEW", "expires_in": 3600}}
class Resp(io.BytesIO):
    def __enter__(self): return self
    def __exit__(self, *a): pass
def fake(req, timeout=None):
    url = req.full_url
    with open(os.path.join(work, "req.jsonl"), "a") as f:
        f.write(json.dumps({"method": req.get_method(), "url": url, "auth": req.get_header("Authorization"),
                            "body": (req.data or b"").decode()}) + "\n")
    if code == 503:
        raise urllib.error.HTTPError(url, code, "x", {}, io.BytesIO(
            b'{"error": "not signed in: run the sign-in once (pc spotify auth)"}'))
    if code != 200 and "/spotify-token/v1/" in url:
        raise urllib.error.HTTPError(url, code, "x", {}, None)
    path = url.split("/v1/")[-1].split("?")[0] if "/v1/" in url else "api/token"
    return Resp(json.dumps(R.get(path, {})).encode() if path in R else b"")
urllib.request.urlopen = fake
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
PY
}
out=$(api 200 search q 2>&1); is 'api: no lease from the vault exits 2' "$?" 2
has 'api: no lease from the vault explains the setup' 'developer.spotify.com/dashboard' "$out"
export SP_LEASE=FIXTURELEASE
out=$(api 503 search q 2>&1); is 'api: no token exits 2' "$?" 2; has 'api: no token says run auth' 'pc spotify auth' "$out"
api 200 bogus >/dev/null 2>&1; is 'api: unknown command exits 2' "$?" 2
out=$(api 200 search q); is 'api search exits 0' "$?" 0
has 'api search prints the track' 'track: A — T  spotify:track:1' "$out"
has 'api search skips null playlists' 'playlist: P  spotify:playlist:2' "$out"
is 'api library prints playlists' "$(api 200 library)" 'playlist: Mine (3 tracks)  spotify:playlist:9'
: >"$WORK/req.jsonl"; out=$(api 200 play spotify:album:7)
is 'api play picks the Computer device' "$out" 'play: spotify:album:7 on Laptop'
is 'api play PUTs an album as context_uri' \
  "$(jq -sr '.[-1]|.method + " " + (.url|test("device_id=pc")|tostring) + " " + .body' "$WORK/req.jsonl")" \
  'PUT true {"context_uri": "spotify:album:7"}'
out=$(api 401 library 2>&1); is 'api: an HTTP error exits 1' "$?" 1; has 'api: an HTTP error names the code' 'Web API 401' "$out"
is 'api: every call goes to the vault with the lease, never with an Authorization header' \
  "$(jq -sr '[.[] | select((.url | startswith("http://127.0.0.1:9/FIXTURELEASE/spotify-token/v1/") | not) or .auth != null)] | length' "$WORK/req.jsonl")" 0
: >"$LOG"; api 200 play spotify:album:7 >/dev/null
is 'api: one lease asked per run (spotify-token, ticket pc-spotify)' "$(grep -c '^secret grant spotify-token --ticket pc-spotify' "$LOG") $(grep -c '^secret' "$LOG")" '1 1'
: >"$LOG"; FLEET_LEASE_SPOTIFY_TOKEN=ENVLEASE api 200 library >/dev/null
is 'api: a lease in FLEET_LEASE_SPOTIFY_TOKEN is used as is' "$(grep -c '^secret' "$LOG") $(jq -sr '.[-1].url | contains("/ENVLEASE/spotify-token/v1/me/playlists")' "$WORK/req.jsonl")" '0 true'
is 'no secret file: the helper and pc spotify name none' "$(grep -c 'agents/secrets\|spotify.env\|spotify-token.json' "$API" "$PC" | cut -d: -f2 | tr '\n' ' ')" '0 0 '

: >"$LOG"
for c in play pause toggle next prev vol seek; do sp $c -h >/dev/null 2>&1; sp $c --help >/dev/null 2>&1; done
is '-h after a player command acts on nothing' "$(grep -cE 'playerctl .* (play|pause|play-pause|next|previous|volume|position)' "$LOG")" 0
is 'play -h prints the usage' "$(sp play -h | head -1)" 'usage: pc spotify <command> [args]'

[ $bad -eq 0 ] && echo PASS || echo FAIL
exit $bad
