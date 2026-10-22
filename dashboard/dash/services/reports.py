"""Read-only /report/agents/<path>: the fleet reports and logs a need names, allowlisted, loopback or tailnet only."""
import fnmatch, html, os, urllib.parse
from dash.env import HOME
from dash.routes import route
from dash.services.files import PREVIEW_MAX, md_html
from dash.services.sites import trusted

REPORT_ROOT = os.path.join(HOME, "agents")
REPORT_ALLOW = (("state", "ci-fix", "*.md"), ("*", "REPORT.md"), ("log", "*.log"), ("*", "logs", "*.log"))
REPORT_DENY = ("secrets", "backups")
LOG_LINES = 400
PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="dark">
<title>%(name)s</title>
<link rel="stylesheet" href="/static/eye.css">
</head><body><main class="page">
<nav><a href="/">&larr; panel</a><span>%(note)s</span></nav>
<article class="prose">
%(body)s
</article>
</main></body></html>
"""


def allowed(rel):
    """True when a path relative to ~/agents matches the allowlist and holds no dotfile, secrets or backups part."""
    parts = rel.split("/")
    if any(not p or p.startswith(".") or p in REPORT_DENY for p in parts):
        return False
    return any(len(a) == len(parts) and all(fnmatch.fnmatchcase(p, g) for p, g in zip(parts, a)) for a in REPORT_ALLOW)


def report_path(raw):
    """The real file for a requested ~/agents path when it and its realpath are allowlisted files inside ~/agents; else None."""
    rel = urllib.parse.unquote(raw)
    if "\\" in rel or "\x00" in rel or not allowed(rel):
        return None
    root = os.path.realpath(REPORT_ROOT)
    full = os.path.realpath(os.path.join(root, rel))
    if not full.startswith(root + os.sep) or not allowed(full[len(root) + 1:]) or not os.path.isfile(full):
        return None
    return full


def tail(full, n):
    """The last n lines of a text file, read from at most PREVIEW_MAX bytes before its end."""
    with open(full, "rb") as f:
        f.seek(max(0, os.fstat(f.fileno()).st_size - PREVIEW_MAX))
        data = f.read()
    return "\n".join(data.decode("utf-8", errors="replace").splitlines()[-n:])


def render(full, rel):
    """One report as an HTML page: markdown rendered, a log as its last LOG_LINES lines."""
    if rel.endswith(".md"):
        with open(full, "rb") as f:
            body = md_html(f.read(PREVIEW_MAX).decode("utf-8", errors="replace"))
        note = "~/agents/" + html.escape(rel)
    else:
        body = "<pre>%s</pre>" % html.escape(tail(full, LOG_LINES))
        note = "~/agents/%s · last %d lines" % (html.escape(rel), LOG_LINES)
    return (PAGE % {"name": html.escape(os.path.basename(rel)), "note": note, "body": body}).encode()


@route("GET", "/report/", prefix=True)
def report_route(h, path):
    if not trusted(h.client_address[0]):
        return h.send(403, b"tailnet only\n", "text/plain")
    raw = path[len("/report/"):]
    full = raw.startswith("agents/") and report_path(raw[len("agents/"):])
    if not full:
        return h.send(404, b"not found\n", "text/plain")
    h.send(200, render(full, os.path.relpath(full, os.path.realpath(REPORT_ROOT))), "text/html; charset=utf-8", cache="no-store")
