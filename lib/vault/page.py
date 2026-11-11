"""The owner's write-only Vault page: add or replace a value through a masked field; served by the broker, never shows one."""
import base64
import html
import http.server
import ipaddress
import os
import socket
import socketserver
import sys
import threading
import time
import urllib.parse

from . import registry, wire

PREFIX = "/vault"
MAX_FORM = 80 * 1024
CSP = "default-src 'none'; style-src 'self'; img-src 'self' data:; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
CLASSES = {"free": "any agent may use it; every use is logged",
           "ruled": "allowed inside its rules; outside them the agent asks the orchestrator or you",
           "critical": "each use waits for the orchestrator's or your approval"}
HERE_NOTE = ("This page was opened from the laptop itself, where the agents run, so it takes no value here. "
             "Open the vault from your phone or another device on your tailnet, or type `secret add <name>` in a terminal.")
CSS = """
:root { color-scheme: dark; --bg: #000; --bg1: #030503; --line: rgba(77,255,160,.14); --line2: rgba(77,255,160,.2);
  --g: #4dffa0; --g2: #9fffc8; --hi: #eafff2; --w04: rgba(77,255,160,.04); --w08: rgba(77,255,160,.08);
  --w22: rgba(77,255,160,.22); --gold: #ffd166; --gold-w: rgba(255,209,102,.14); --mute: #6a8a7a; --mid: #83a08f;
  --txt: #c2d3c8; --mono: ui-monospace, "SF Mono", "DejaVu Sans Mono", "Cascadia Mono", Menlo, Consolas, monospace; }
* { box-sizing: border-box; margin: 0; }
html { background: var(--bg); color: var(--txt); font: 400 clamp(14px, .55rem + .45vw, 19px)/1.5 var(--mono); }
body { min-height: 100svh; padding: clamp(1rem, 4vw, 3rem) clamp(.9rem, 4vw, 3rem); }
.v { width: min(100%, 44rem); margin-inline: auto; display: grid; gap: 1.1rem; }
a { color: var(--g); text-decoration: none; overflow-wrap: anywhere; }
a:hover, a:focus-visible { text-decoration: underline; }
.back { justify-self: start; display: inline-flex; align-items: center; min-height: 44px; color: var(--mid); letter-spacing: .14em; text-transform: uppercase; font-size: .78em; }
header { display: grid; gap: .3rem; padding-bottom: .9rem; border-bottom: 1px solid var(--line2); }
.k { color: var(--g); font-size: .72em; letter-spacing: .2em; text-transform: uppercase; }
h1 { color: var(--hi); font-size: clamp(1.6rem, 1rem + 2.4vw, 2.8rem); font-weight: 600; line-height: 1.1; letter-spacing: -.01em; overflow-wrap: anywhere; }
.sub { color: var(--mid); overflow-wrap: anywhere; }
form { display: grid; gap: 1rem; padding: clamp(.9rem, 2.5vw, 1.4rem); border: 1px solid var(--line2); background: var(--bg1); }
.f { display: grid; gap: .35rem; }
.f > span, legend { color: var(--g); font-size: .72em; letter-spacing: .2em; text-transform: uppercase; }
small { color: var(--mute); font-size: .8em; }
input, textarea { width: 100%; min-height: 44px; padding: .55rem .7rem; font: inherit; color: var(--hi); background: var(--w04); border: 1px solid var(--w22); border-radius: 0; }
textarea { resize: vertical; }
input:focus-visible, textarea:focus-visible { outline: 2px solid var(--g); outline-offset: 1px; }
.val input { letter-spacing: .12em; }
fieldset { border: 0; padding: 0; display: grid; gap: .5rem; min-width: 0; }
.c { display: grid; grid-template-columns: auto 1fr; gap: .1rem .7rem; align-items: center; padding: .6rem .7rem; min-height: 44px; border: 1px solid var(--line); cursor: pointer; }
.c input { width: 1.1rem; min-height: 1.1rem; grid-row: span 2; accent-color: var(--g); }
.c b { color: var(--hi); font-weight: 600; letter-spacing: .08em; }
.c small { grid-column: 2; }
.c:has(input:checked) { border-color: var(--g); background: var(--w08); }
.c-critical:has(input:checked) { border-color: var(--gold); background: var(--gold-w); }
.c-critical:has(input:checked) b { color: var(--gold); }
form:has(.c input[value=ruled]) .rules { display: none; }
form:has(.c input[value=ruled]:checked) .rules { display: grid; }
.go { display: flex; flex-wrap: wrap; gap: .7rem; align-items: center; }
button, .btn { display: inline-flex; align-items: center; justify-content: center; min-height: 44px; padding: 0 1.2rem; font: inherit; font-size: .8em; letter-spacing: .16em; text-transform: uppercase; color: var(--g2); background: var(--w04); border: 1px solid var(--g); border-radius: 0; cursor: pointer; }
button:hover, .btn:hover { background: var(--w08); text-decoration: none; }
.btn.ghost { color: var(--mid); border-color: var(--line2); background: transparent; }
.note { padding: .7rem .9rem; border: 1px solid rgba(255,209,102,.35); background: var(--gold-w); color: var(--gold); overflow-wrap: anywhere; }
.facts { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 11rem), 1fr)); gap: .6rem 1rem; }
.facts div { display: grid; gap: .15rem; padding: .5rem 0; border-top: 1px solid var(--line); min-width: 0; }
.facts dt { color: var(--mute); font-size: .72em; letter-spacing: .16em; text-transform: uppercase; }
.facts dd { color: var(--hi); overflow-wrap: anywhere; }
@media (prefers-reduced-motion: no-preference) { form, header { animation: in .35s ease-out both; } @keyframes in { from { opacity: 0; transform: translateY(6px); } } }
"""


def is_local(addr):
    """True when addr is one of this machine's own addresses (or not an address at all: fail closed)."""
    try:
        ip = ipaddress.ip_address(addr)
    except ValueError:
        return True
    if ip.is_loopback or ip.is_unspecified:
        return True
    with socket.socket(socket.AF_INET6 if ip.version == 6 else socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.bind((str(ip), 0))
        except OSError:
            return False
    return True


def source(headers):
    """The caller's address as tailscale serve reports it (last X-Forwarded-For entry), or ''."""
    return (headers.get("X-Forwarded-For") or "").split(",")[-1].strip()


def refusal(peer_uid, headers, owner_login, peers, local=is_local):
    """(status, why) when this caller may not use the page, else None; ("here", why) when it may only look."""
    if peer_uid not in peers:
        return 403, "this page is reached through the tailnet front only"
    if not owner_login:
        return 403, "no owner login is set (FLEET_VAULT_OWNER_LOGIN): the vault page is off"
    if headers.get("Tailscale-User-Login") != owner_login:
        return 403, "only the owner's tailnet login may use this page"
    src = source(headers)
    if not src or local(src):
        return "here", HERE_NOTE
    return None


def cross_site(headers):
    """True when a POST comes from another origin."""
    if (headers.get("Sec-Fetch-Site") or "same-origin") not in ("same-origin", "none"):
        return True
    origin = headers.get("Origin")
    return origin is not None and origin != "https://" + (headers.get("Host") or "")


def e(s):
    return html.escape(str(s if s is not None else ""), quote=True)


def ago(ts, now):
    if not ts:
        return "never"
    s = max(0, now - ts)
    return f"{int(s // 86400)} d" if s >= 86400 else f"{int(s // 3600)} h" if s >= 3600 else f"{int(s // 60)} min"


def shell(title, body):
    """One page: dashboard look, no script."""
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, '
            f'initial-scale=1"><meta name="referrer" content="same-origin"><title>{e(title)} · Vault</title>'
            f'<link rel="stylesheet" href="{PREFIX}/page.css"></head><body><main class="v">'
            f'<a class="back" href="/#vault">← vault</a>{body}</main></body></html>')


def head(kicker, title, sub):
    return f'<header><p class="k">{e(kicker)}</p><h1>{e(title)}</h1><p class="sub">{sub}</p></header>'


def notice(text, cls="warn"):
    return f'<p class="note {cls}" role="alert">{e(text)}</p>'


def value_field():
    return ('<label class="f val"><span>value</span><input type="password" name="value" required autocomplete="off" '
            'autocapitalize="off" spellcheck="false" maxlength="65536"><small>masked; sealed to this laptop\'s TPM chip; '
            'never shown again, to you or to an agent; spaces around it are dropped</small></label>')


def add_form(f=None, error=""):
    """The Add form; f holds the fields to keep after an error (never the value)."""
    f = f or {}
    cls = f.get("class") or "critical"
    radios = "".join(
        f'<label class="c c-{c}"><input type="radio" name="class" value="{c}"{" checked" if c == cls else ""}>'
        f'<b>{c}</b><small>{e(why)}</small></label>' for c, why in CLASSES.items())
    return (head("vault · add", "Add a secret", "a name, where it is used, who may use it, then the value") +
            (notice(error) if error else "") +
            f'<form method="post" action="{PREFIX}/put" autocomplete="off"><input type="hidden" name="mode" value="add">'
            f'<label class="f"><span>name</span><input name="name" required pattern="[a-z0-9][a-z0-9\\-]{{0,62}}" '
            f'maxlength="63" autocapitalize="off" spellcheck="false" value="{e(f.get("name"))}" '
            f'placeholder="e.g. salesforce-sandbox"><small>lowercase letters, digits and -</small></label>'
            f'<label class="f"><span>used in</span><input name="used_in" required maxlength="200" value="{e(f.get("used_in"))}" '
            f'placeholder="what it is for and which tool uses it"></label>'
            f'<fieldset class="cls"><legend>class</legend>{radios}</fieldset>'
            f'<label class="f rules"><span>rules (class ruled)</span><textarea name="rules" rows="2" maxlength="400" '
            f'placeholder="when an agent may use it without asking">{e(f.get("rules"))}</textarea></label>'
            f'{value_field()}<div class="go"><button type="submit">seal it</button>'
            f'<a class="btn ghost" href="/#vault">cancel</a></div></form>')


def replace_form(row, now, error=""):
    """The Replace (or first value) form for one known name."""
    sealed = row["sealed"]
    mode = "replace" if sealed else "add"
    facts = (f'<dl class="facts"><div><dt>class</dt><dd>{e(row["class"])}</dd></div>'
             f'<div><dt>state</dt><dd>{"sealed " + ago(row.get("sealed_at"), now) + " ago" if sealed else "no sealed value yet"}</dd></div>'
             f'<div><dt>used in</dt><dd>{e(row["used_in"])}</dd></div></dl>')
    link = (f'<p class="sub">make a new one first: <a href="{e(row["reissue"])}" target="_blank" rel="noopener noreferrer">'
            f'{e(row["reissue"])} ↗</a></p>' if row.get("reissue") else "")
    return (head(f"vault · {mode}", row["name"],
                 "the old value is never shown; the new one takes over at once" if sealed else
                 "the first sealed value for this name") + facts + link +
            (notice(error) if error else "") +
            f'<form method="post" action="{PREFIX}/put" autocomplete="off"><input type="hidden" name="mode" value="{mode}">'
            f'<input type="hidden" name="name" value="{e(row["name"])}">{value_field()}'
            f'<div class="go"><button type="submit">{"replace it" if sealed else "seal it"}</button>'
            f'<a class="btn ghost" href="/#vault">cancel</a></div></form>')


class PageServer(socketserver.UnixStreamServer):
    """One request at a time on a Unix socket; errors print their type only (a form body never reaches a log)."""

    def handle_error(self, request, client_address):
        print(f"vault page: request failed ({sys.exc_info()[0].__name__})", file=sys.stderr, flush=True)


def make_handler(admin, owner_login, peers, local=is_local, clock=time.time):
    """A request handler class bound to the broker's Admin."""

    class Handler(http.server.BaseHTTPRequestHandler):
        timeout = 15

        def log_message(self, *a):
            pass

        def setup(self):
            super().setup()
            try:
                self.peer_uid = wire.peer(self.request)[1]
            except OSError:
                self.peer_uid = -1

        def _send(self, status, body, ctype="text/html; charset=utf-8", extra=None):
            data = body.encode()
            self.send_response(status)
            for k, v in {"Content-Type": ctype, "Content-Length": str(len(data)), "Cache-Control": "no-store",
                         "Content-Security-Policy": CSP, "X-Content-Type-Options": "nosniff",
                         "Referrer-Policy": "same-origin", **(extra or {})}.items():
                self.send_header(k, v)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(data)

        def _page(self, status, title, body):
            self._send(status, shell(title, body))

        def _path(self):
            u = urllib.parse.urlsplit(self.path)
            p = u.path[len(PREFIX):] if u.path == PREFIX or u.path.startswith(PREFIX + "/") else u.path
            return p, urllib.parse.parse_qs(u.query)

        def _rows(self):
            return {r["name"]: r for r in admin.handle({"op": "list"}, self.peer_uid)["secrets"]}

        def do_GET(self):
            p, q = self._path()
            if p == "/page.css":
                return self._send(200, CSS, "text/css; charset=utf-8", {"Cache-Control": "max-age=300"})
            why = refusal(self.peer_uid, self.headers, owner_login, peers, local)
            if why and why[0] != "here":
                return self._page(why[0], "refused", head("vault", "Refused", e(why[1])))
            here = notice(why[1]) if why else ""
            if p in ("", "/"):
                return self._send(303, "", extra={"Location": PREFIX + "/add"})
            if p == "/add":
                return self._page(200, "add", head("vault · add", "Add a secret", "") + here if here else add_form())
            if p == "/replace":
                name = (q.get("name") or [""])[0]
                row = self._rows().get(name) if registry.NAME.match(name) else None
                if row is None:
                    return self._page(404, "unknown", head("vault", "Not in the vault", e(name) or "no name given"))
                return self._page(200, name, head("vault · replace", name, "") + here if here else
                                  replace_form(row, clock()))
            if p == "/done":
                name, ev = (q.get("name") or [""])[0], (q.get("event") or [""])[0]
                return self._page(200, "sealed", head("vault · " + ("replaced" if ev == "replace" else "added"),
                                  f"{name} is sealed", "the value is never shown again; agents use it only through "
                                  "the broker, under its class") + '<p class="go"><a class="btn" href="/#vault">back to the vault</a></p>')
            return self._page(404, "not found", head("vault", "Not found", ""))

        do_HEAD = do_GET

        def do_POST(self):
            p, _q = self._path()
            why = refusal(self.peer_uid, self.headers, owner_login, peers, local)
            if why:
                return self._page(403, "refused", head("vault", "Refused", "") + notice(why[1]))
            if cross_site(self.headers):
                return self._page(403, "refused", head("vault", "Refused", "a form from another site may not write here"))
            if p != "/put":
                return self._page(404, "not found", head("vault", "Not found", ""))
            if (self.headers.get("Content-Type") or "").split(";")[0].strip() != "application/x-www-form-urlencoded":
                return self._page(415, "refused", head("vault", "Refused", "send the form"))
            n = int(self.headers.get("Content-Length") or 0)
            if not 0 < n <= MAX_FORM:
                return self._page(413, "refused", head("vault", "Refused", "the form is empty or too large"))
            try:
                form = urllib.parse.parse_qs(self.rfile.read(n).decode("utf-8"), max_num_fields=8, strict_parsing=False)
            except (UnicodeDecodeError, ValueError):
                return self._page(400, "refused", head("vault", "Refused", "the form could not be read"))
            f = {k: (v[0] if v else "").strip() for k, v in form.items()}
            del form
            value = f.pop("value", "")
            mode, name = f.get("mode"), f.get("name", "")
            req = {"op": "put", "name": name, "replace": mode == "replace", "agent": "vault page",
                   "value_b64": base64.b64encode(value.encode()).decode()}
            del value
            if mode == "add" and f.get("class"):
                req.update({k: f[k] for k in ("class", "used_in", "rules") if f.get(k)})
            r = admin.handle(req, self.peer_uid)
            del req
            if r.get("ok"):
                loc = f"{PREFIX}/done?" + urllib.parse.urlencode({"name": r["name"], "event": r["event"]})
                return self._send(303, "", extra={"Location": loc})
            row = self._rows().get(name) if f.get("class") is None and registry.NAME.match(name or "-") else None
            body = replace_form(row, clock(), r.get("error", "refused")) if row else add_form(f, r.get("error", "refused"))
            return self._page(400, "not sealed", body)

    return Handler


def serve(admin, path, owner_login, peers=frozenset({0}), local=is_local):
    """Start the page on a Unix socket only its owner (and root, that is tailscaled) can open; returns the server."""
    if os.path.exists(path):
        os.unlink(path)
    old = os.umask(0o177)
    try:
        server = PageServer(path, make_handler(admin, owner_login, set(peers), local))
    finally:
        os.umask(old)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
