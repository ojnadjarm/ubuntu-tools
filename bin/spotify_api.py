#!/usr/bin/env python3
"""Spotify Web API helper for `pc spotify search|library|auth` (authorization code flow)."""
import base64
import http.server
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SECRETS = os.path.expanduser("~/agents/secrets")
ENV = os.path.join(SECRETS, "spotify.env")
TOKENS = os.path.join(SECRETS, "spotify-token.json")
REDIRECT = "http://127.0.0.1:8899/callback"
SCOPES = "playlist-read-private user-library-read user-read-playback-state user-modify-playback-state"


def die(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)


def creds():
    out = {}
    with open(ENV) as fh:
        for line in fh:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip("'\"")
    cid, sec = out.get("SPOTIFY_CLIENT_ID"), out.get("SPOTIFY_CLIENT_SECRET")
    if not cid or not sec:
        die(f"spotify: {ENV} needs SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET")
    return cid, sec


def token_request(data):
    cid, sec = creds()
    auth = base64.b64encode(f"{cid}:{sec}".encode()).decode()
    req = urllib.request.Request(
        "https://accounts.spotify.com/api/token",
        data=urllib.parse.urlencode(data).encode(),
        headers={"Authorization": f"Basic {auth}", "Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def save(tok):
    tok["expires_at"] = time.time() + tok.get("expires_in", 3600) - 60
    old = json.load(open(TOKENS)) if os.path.exists(TOKENS) else {}
    tok.setdefault("refresh_token", old.get("refresh_token", ""))
    fd = os.open(TOKENS, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump(tok, fh)
    return tok


def access_token():
    if not os.path.exists(TOKENS):
        die("spotify: not authorised yet — run `pc spotify auth` from the desktop")
    tok = json.load(open(TOKENS))
    if tok.get("expires_at", 0) < time.time():
        tok = save(token_request({"grant_type": "refresh_token", "refresh_token": tok["refresh_token"]}))
    return tok["access_token"]


def call(path, method="GET", body=None, **params):
    url = "https://api.spotify.com/v1/" + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(
        url, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + access_token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        die(f"spotify: Web API {e.code} on {path}", 1)


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
    cid, _ = creds()
    code = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            code.update({k: v[0] for k, v in q.items()})
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Spotify authorised. You can close this tab.")

        def log_message(self, *a):
            pass

    url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode(
        {"client_id": cid, "response_type": "code", "redirect_uri": REDIRECT, "scope": SCOPES})
    print("open: " + url)
    subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    srv = http.server.HTTPServer(("127.0.0.1", 8899), Handler)
    srv.timeout = 180
    srv.handle_request()
    if "code" not in code:
        die("spotify: no authorisation code received (" + code.get("error", "timed out") + ")", 1)
    save(token_request({"grant_type": "authorization_code", "code": code["code"], "redirect_uri": REDIRECT}))
    print("auth: tokens stored in " + TOKENS)


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
