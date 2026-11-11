#!/usr/bin/env python3
"""Spotify Web API helper for `pc spotify search|library|play|auth`, through the fleet vault (T1634-V7): the broker holds
the client secret and the refresh token; this helper holds only a lease."""
import functools
import http.server
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

REDIRECT = "http://127.0.0.1:8899/callback"
SCOPES = "playlist-read-private user-library-read user-read-playback-state user-modify-playback-state"
SETUP = """spotify: the Web API needs the Spotify app in the vault. The owner opens https://developer.spotify.com/dashboard,
clicks Create app (any name), sets the Redirect URI to exactly http://127.0.0.1:8899/callback, ticks Web API and saves;
then adds <client id>:<client secret> as spotify-client on the dashboard's Vault page (or `secret add spotify-client`
in a terminal) and runs `pc spotify auth` once from the desktop: it opens a browser to approve, and the broker keeps
the sign-in and refreshes it from then on."""
urllib.request.install_opener(urllib.request.build_opener(urllib.request.ProxyHandler({})))


def die(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)


@functools.cache
def base():
    """http://127.0.0.1:<port>/<lease>/spotify-token: a lease from the env, else one asked with `secret grant`."""
    lease = os.environ.get("FLEET_LEASE_SPOTIFY_TOKEN", "")
    if not lease:
        try:
            cli = shutil.which("secret") or os.path.join(os.path.dirname(os.path.realpath(__file__)), "secret")
            r = subprocess.run([cli, "grant", "spotify-token", "--ticket", "pc-spotify", "--ttl", "600"],
                               capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.SubprocessError) as e:
            die(f"spotify: no vault client ({type(e).__name__})\n{SETUP}")
        lease, why = r.stdout.strip(), r.stderr.strip()
        if r.returncode or not lease:
            die(f"spotify: the vault gave no lease on spotify-token ({why or r.returncode})"
                + (f"\n{SETUP}" if "not in the vault" in why else ""))
    vault = os.environ.get("FLEET_VAULT_URL") or f"http://127.0.0.1:{os.environ.get('FLEET_VAULT_PORT') or 18480}"
    return f"{vault}/{lease}/spotify-token"


def refusal(e):
    """Exit with the vault's own words for an HTTPError when it sent them (exit 2 when the vault lacks a value)."""
    try:
        why = json.loads(e.read()).get("error")
    except (ValueError, AttributeError, OSError, TypeError):
        why = None
    if isinstance(why, str):
        die(f"spotify: vault: {why}" + (f"\n{SETUP}" if e.code == 503 and "not in the vault" in why else ""),
            2 if e.code == 503 else 1)


def call(path, method="GET", body=None, **params):
    url = f"{base()}/v1/{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(
        url, method=method, data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        refusal(e)
        die(f"spotify: Web API {e.code} on {path}", 1)
    except urllib.error.URLError as e:
        die(f"spotify: the vault broker is unreachable ({e.reason}); is fleet-vault.service running?", 1)


def get(path, **params):
    return call(path, **params)


def play(uri):
    """Start URI on the running desktop app, found among the account's Connect devices."""
    devices = get("me/player/devices").get("devices", [])
    dev = next((d for d in devices if d["type"] == "Computer"), None) or (devices[0] if devices else None)
    if not dev:
        die("spotify: no Spotify Connect device is available (is the app running and logged in?)", 1)
    body = {"uris": [uri]} if uri.startswith("spotify:track:") else {"context_uri": uri}
    call("me/player/play", "PUT", body, device_id=dev["id"])
    print(f"play: {uri} on {dev['name']}")


def auth():
    """Sign in once: the browser goes through the broker to Spotify; the broker exchanges the code and keeps the token."""
    b, code = base(), {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            code.update({k: v[0] for k, v in q.items()})
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Spotify authorised. You can close this tab.")

        def log_message(self, *a):
            pass

    print("open: the Spotify sign-in page in the desktop browser (through the vault)")
    url = f"{b}/authorize?" + urllib.parse.urlencode({"redirect_uri": REDIRECT, "scope": SCOPES})
    subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    srv = http.server.HTTPServer(("127.0.0.1", 8899), Handler)
    srv.timeout = 180
    srv.handle_request()
    if "code" not in code:
        die("spotify: no authorisation code received (" + code.get("error", "timed out") + ")", 1)
    form = {"grant_type": "authorization_code", "code": code["code"], "redirect_uri": REDIRECT}
    req = urllib.request.Request(f"{b}/api/token", data=urllib.parse.urlencode(form).encode(),
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            json.load(r)
    except urllib.error.HTTPError as e:
        refusal(e)
        die(f"spotify: sign-in refused ({e.code})", 1)
    print("auth: the sign-in is sealed in the vault (spotify-token)")


def search(query):
    d = get("search", q=query, type="track,album,playlist", limit=5)
    for t in d.get("tracks", {}).get("items", []):
        print(f"track: {', '.join(a['name'] for a in t['artists'])} — {t['name']}  {t['uri']}")
    for a in d.get("albums", {}).get("items", []):
        print(f"album: {', '.join(x['name'] for x in a['artists'])} — {a['name']}  {a['uri']}")
    for p in (d.get("playlists", {}).get("items", []) or []):
        if p:
            print(f"playlist: {p['name']}  {p['uri']}")


def library():
    for p in get("me/playlists", limit=50).get("items", []) or []:
        if not p:
            continue
        n = (p.get("items") or p.get("tracks") or {}).get("total", "?")
        print(f"playlist: {p.get('name', '?')} ({n} tracks)  {p.get('uri', '?')}")


cmd = sys.argv[1] if len(sys.argv) > 1 else ""
if cmd == "auth":
    auth()
elif cmd == "search":
    search(sys.argv[2])
elif cmd == "play":
    play(sys.argv[2])
elif cmd == "library":
    library()
else:
    die("usage: spotify_api.py auth|search <q>|library|play <uri>")
