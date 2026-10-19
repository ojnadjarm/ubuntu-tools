"""Project tiles: one registry row per long-running project, its environment read live and read-only."""
import html, os, re, shutil, threading
from datetime import datetime
from dash.cache import TTL, cached, forget
from dash.env import HOME, PUBLIC_HOST, run
from dash.routes import route
from dash.services import sites

PROJECTS = {
    "vass": {"name": "vass (Moodle 4.5)", "what": "customer Moodle 4.5 site, many custom plugins",
             "folder": "projects/moodle/vass", "repo": "moodle-envs/vass/moodle", "containers": ("moodle45-", "vass-services-"),
             "port": 8045, "tls": 8445, "mailhog": 8025, "frontend": 8446, "login": "admin",
             "db": "localhost:5445 · pgsql 13"},
}
HEADING = re.compile(r"^(#+)\s+(.*)$")
ITEM = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(?!\[[xX]\])")
STATE = re.compile(r"^\s*[-*+]?\s*\**state\**\s*:\s*\**\s*(.*)$", re.I)
SECTION = re.compile(r"^#{1,2} ")
H2 = re.compile(r'(<h2 id="[^"]*">(.*?)</h2>)', re.S)
BACKUPS = 20
_tickets_lock = threading.Lock()
PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="dark">
<title>%(name)s tickets</title>
<link rel="stylesheet" href="/static/eye.css">
<script type="module" src="/static/js/tickets.js"></script>
</head><body><main class="page" data-project="%(key)s">
<nav><a href="/#sites">&larr; panel · sites</a><span>tickets</span></nav>
<div class="meta">%(open)s<ol class="toc">%(toc)s</ol></div>
<article class="prose">
%(body)s
</article>
</main></body></html>
"""


def todo_count(path):
    """Open list items under a "Todo" heading of the notes file; None when the file or the section is missing."""
    try:
        lines = open(path).read().splitlines()
    except OSError:
        return None
    level, n = None, 0
    for line in lines:
        h = HEADING.match(line)
        if h and level is not None and len(h.group(1)) <= level:
            break
        if h and level is None and re.match(r"to-?dos?\b", h.group(2).strip(), re.I):
            level = len(h.group(1))
        elif level is not None and ITEM.match(line):
            n += 1
    return n if level is not None else None


def fenced(lines):
    """Per line, True when it sits inside or on a ``` / ~~~ code fence."""
    out, inside = [], False
    for line in lines:
        fence = line.lstrip().startswith(("```", "~~~"))
        out.append(inside or fence)
        inside ^= fence
    return out


def open_tickets(path):
    """Tickets ("## " sections) whose state is not just "done"; None when the file is missing."""
    try:
        lines = open(path).read().splitlines()
    except OSError:
        return None
    states = []
    for line, code in zip(lines, fenced(lines)):
        if code:
            continue
        if line.startswith("## "):
            states.append("")
        elif states and not states[-1] and STATE.match(line):
            states[-1] = STATE.match(line).group(1).strip("` ").lower()
    return sum(s != "done" for s in states)


def ticket_sections(lines):
    """(id, start, end, done) per "## " ticket of lines; id is the heading's first word, end the next h1/h2 or EOF."""
    heads = [i for i, (line, code) in enumerate(zip(lines, fenced(lines))) if not code and SECTION.match(line)] + [len(lines)]
    out = []
    for i, end in zip(heads, heads[1:]):
        if lines[i].startswith("## "):
            st = next((STATE.match(l) for l in lines[i + 1:end] if STATE.match(l)), None)
            out.append((lines[i][3:].split()[0] if lines[i][3:].split() else "", i, end,
                        bool(st) and st.group(1).strip("` ").lower() == "done"))
    return out


def tickets_file(key):
    """Path of the project's TICKETS.md, or None for an unknown project."""
    p = PROJECTS.get(key) if isinstance(key, str) else None
    return p and os.path.join(HOME, p["folder"], "TICKETS.md")


def backup(path):
    """Copy path into .tickets-backup/ beside it with a timestamp; keep the newest BACKUPS copies."""
    d = os.path.join(os.path.dirname(path), ".tickets-backup")
    os.makedirs(d, exist_ok=True)
    shutil.copy2(path, os.path.join(d, "TICKETS-%s.md" % datetime.now().strftime("%Y%m%d-%H%M%S-%f")))
    for old in sorted(f for f in os.listdir(d) if f.startswith("TICKETS-"))[:-BACKUPS]:
        os.unlink(os.path.join(d, old))


def edit_ticket(key, tid, action):
    """Close (state -> done) or delete (done only) one ticket after a backup, written via temp file + rename."""
    path = tickets_file(key)
    if not path or not os.path.isfile(path) or action not in ("close", "delete"):
        return 400, {"error": "unknown project"}
    with _tickets_lock:
        lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
        hits = [t for t in ticket_sections(lines) if isinstance(tid, str) and tid and t[0] == tid]
        if len(hits) != 1:
            return 400, {"error": "unknown ticket"}
        _, start, end, done = hits[0]
        if action == "close" and done or action == "delete" and not done:
            return 400, {"error": "ticket is done" if done else "ticket is not done"}
        if action == "delete":
            del lines[start:end]
            if start == len(lines):
                while lines and not lines[-1].strip():
                    lines.pop()
                if lines and not lines[-1].endswith("\n"):
                    lines[-1] += "\n"
        else:
            i = next((j for j in range(start + 1, end) if STATE.match(lines[j])), None)
            if i is None:
                gap = [] if start + 1 < len(lines) and not lines[start + 1].strip() else ["\n"]
                lines[start + 1:start + 1] = ["\n", "- **State:** done\n"] + gap
            else:
                m = STATE.match(lines[i])
                lines[i] = lines[i][:m.start(1)] + "done" + lines[i][m.end(1):]
        backup(path)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("".join(lines))
        os.replace(tmp, path)
    forget("projects")
    return 200, {"ok": True, "id": tid, "action": action}


def ticket_buttons(body, done):
    """Insert Close (open tickets) or Delete (done tickets) after each ticket's <h2> in the rendered body."""
    def add(m):
        words = html.unescape(re.sub(r"<[^>]+>", "", m.group(2))).split()
        tid = words[0] if words else ""
        if tid not in done:
            return m.group(1)
        act, cls, label = ("delete", "btn danger", "Delete") if done[tid] else ("close", "btn", "Close")
        return '%s<div class="tk-acts"><button class="%s" type="button" data-tk="%s" data-id="%s">%s</button></div>' % (
            m.group(1), cls, act, html.escape(tid), label)
    return H2.sub(add, body)


def tickets_page(key):
    """The project's TICKETS.md rendered in the plan-page shell, one toc link per ticket; None when missing."""
    p = PROJECTS.get(key)
    path = p and os.path.join(HOME, p["folder"], "TICKETS.md")
    if not path or not os.path.isfile(path):
        return None
    import markdown
    md = markdown.Markdown(extensions=["extra", "sane_lists", "toc"], output_format="html5")
    text = open(path, encoding="utf-8").read()
    body = md.convert(text)
    done = {t[0]: t[3] for t in ticket_sections(text.splitlines(keepends=True))}
    body = ticket_buttons(body, done)
    heads = [t for top in md.toc_tokens for t in ([top] if top["level"] == 2 else top["children"])]
    toc = "".join('<li><a href="#%s">%s</a></li>' % (t["id"], t["name"]) for t in heads)
    return PAGE % {"key": html.escape(key), "name": html.escape(p["name"]), "open": "%d open" % open_tickets(path), "toc": toc, "body": body}


@route("GET", "/projects/", prefix=True)
def tickets_route(h, path):
    parts = path.strip("/").split("/")
    page = tickets_page(parts[1]) if len(parts) == 3 and parts[2] == "tickets" else None
    if page is None:
        return h.send(404, b"not found\n", "text/plain")
    h.send(200, page.encode(), "text/html; charset=utf-8")


@route("POST", "/api/projects/tickets/close")
def tickets_close_route(h, path):
    body = h.body_json(4096, {})
    body = body if isinstance(body, dict) else {}
    code, out = edit_ticket(body.get("project"), body.get("id"), "close")
    h.json(out, code)


@route("POST", "/api/projects/tickets/delete")
def tickets_delete_route(h, path):
    body = h.body_json(4096, {})
    body = body if isinstance(body, dict) else {}
    code, out = edit_ticket(body.get("project"), body.get("id"), "delete")
    h.json(out, code)


def git_facts(repo):
    """Last commit (iso date, subject) and the count of changed paths; Nones when git cannot read the repo."""
    log = run(["git", "-C", repo, "log", "-1", "--format=%cI%x09%s"], 10).strip()
    if not log:
        return {"commit_at": None, "commit": None, "dirty": None}
    at, _, subject = log.partition("\t")
    changed = run(["git", "-C", repo, "--no-optional-locks", "status", "--porcelain"], 10)
    return {"commit_at": at, "commit": subject, "dirty": len(changed.splitlines())}


def project(key, p, docker):
    """One tile record: containers up, site HTTP code, links, git state, open todos and open tickets."""
    mine = [c for c in docker if c["name"].startswith(p["containers"])]
    up = sum(c["state"] == "running" for c in mine)
    code = sites.http_code("http://127.0.0.1:%d/" % p["port"], "GET")
    folder = os.path.join(HOME, p["folder"])
    state = "down" if not up else "up" if up == len(mine) and code == 200 else "warn"
    return dict({"key": key, "name": p["name"], "what": p["what"], "state": state,
                 "containers": [{"name": c["name"], "state": c["state"], "status": c["status"]} for c in mine],
                 "up": up, "site_code": code,
                 "https": "https://%s:%d/" % (PUBLIC_HOST, p["tls"]), "http": "http://%s:%d/" % (PUBLIC_HOST, p["port"]),
                 "mailhog": "http://%s:%d/" % (PUBLIC_HOST, p["mailhog"]),
                 "frontend": "https://%s:%d/" % (PUBLIC_HOST, p["frontend"]) if "frontend" in p else None,
                 "folder": "~/" + p["folder"], "repo": "~/" + p["repo"], "login": p["login"], "db": p["db"],
                 "todo": todo_count(os.path.join(folder, "NOTES.md")),
                 "tickets": open_tickets(os.path.join(folder, "TICKETS.md")), "tickets_url": "/projects/%s/tickets" % key},
                **git_facts(os.path.join(HOME, p["repo"])))


def projects():
    """Every registered project as a tile record; docker comes from the status cycle's cached block."""
    docker = cached("docker", TTL, sites.docker_ps, [])
    return [project(k, p, docker) for k, p in PROJECTS.items()]
