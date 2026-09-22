"""The ~/drop file browser, drop files served with Range, and the published plan pages."""
import html, json, os, re, subprocess, threading, urllib.parse
from dash.cache import forget
from dash.env import HERE, HOME, PUBLIC_HOST
from dash.routes import route

PLANS = os.path.join(HERE, "plans")
DROP = os.path.join(HOME, "drop")
KINDS = {".png": "image", ".jpg": "image", ".jpeg": "image", ".gif": "image", ".webp": "image", ".svg": "image",
         ".md": "markdown", ".txt": "text", ".log": "text", ".csv": "text", ".json": "text", ".yml": "text", ".yaml": "text",
         ".pdf": "pdf", ".mp4": "video", ".webm": "video", ".mp3": "audio", ".ogg": "audio", ".wav": "audio"}
for _e in (".py", ".sh", ".js", ".ts", ".css", ".html", ".xml", ".toml", ".ini", ".conf", ".cfg", ".php", ".sql", ".env"):
    KINDS[_e] = "code"
TEXT_EXT = tuple(e for e, k in KINDS.items() if k in ("markdown", "text", "code"))
MIME = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp",
        ".svg": "image/svg+xml", ".md": "text/plain; charset=utf-8", ".txt": "text/plain; charset=utf-8",
        ".log": "text/plain; charset=utf-8", ".csv": "text/plain; charset=utf-8", ".json": "application/json",
        ".yml": "text/plain; charset=utf-8", ".yaml": "text/plain; charset=utf-8", ".pdf": "application/pdf",
        ".mp4": "video/mp4", ".webm": "video/webm", ".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".wav": "audio/wav",
        ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "text/javascript"}


def fs_path(raw):
    """Confine a requested drop path: no traversal, no dotfiles, realpath inside ~/drop; None if refused."""
    rel = urllib.parse.unquote(raw)
    if rel.startswith("/"):
        return None
    rel = rel.rstrip("/")
    parts = rel.split("/") if rel else []
    if "\\" in rel or "\x00" in rel or any(not p or p.startswith(".") for p in parts):
        return None
    root = os.path.realpath(DROP)
    full = os.path.realpath(os.path.join(root, rel))
    if full != root and not full.startswith(root + os.sep):
        return None
    return full, rel


def ls_dir(raw):
    """One folder of ~/drop: (status, payload) — entries with name, dir, bytes, mtime, kind, mime."""
    hit = fs_path(raw)
    if not hit or not os.path.isdir(hit[0]):
        return 404, {"error": "not found"}
    full, rel = hit
    try:
        names = [n for n in os.listdir(full) if not n.startswith(".")]
    except OSError as e:
        return 200, {"path": rel, "items": [], "count": 0, "bytes": 0, "error": e.strerror or str(e)}
    items, total = [], 0
    for n in sorted(names, key=str.lower):
        p = os.path.join(full, n)
        try:
            st = os.stat(p)
        except OSError:
            continue
        isdir = os.path.isdir(p)
        if not isdir and not os.path.isfile(p):
            continue
        if os.path.islink(p) and not os.path.realpath(p).startswith(os.path.realpath(DROP) + os.sep):
            continue
        ext = os.path.splitext(n)[1].lower()
        total += 0 if isdir else st.st_size
        items.append({"name": n, "dir": isdir, "bytes": None if isdir else st.st_size, "mtime": st.st_mtime,
                      "kind": "folder" if isdir else KINDS.get(ext, "file"),
                      "mime": "" if isdir else MIME.get(ext, "application/octet-stream")})
    return 200, {"path": rel, "items": items, "count": len(items), "bytes": total}


def drop():
    """The drop folder's contents, newest first."""
    out = []
    total = 0
    if os.path.isdir(DROP):
        for n in os.listdir(DROP):
            p = os.path.join(DROP, n)
            if os.path.isfile(p) and not n.startswith("."):
                st = os.stat(p)
                total += st.st_size
                out.append({"name": n, "bytes": st.st_size, "mtime": st.st_mtime,
                            "kind": KINDS.get(os.path.splitext(n)[1].lower(), "file")})
    out.sort(key=lambda f: f["mtime"], reverse=True)
    return {"url": "http://%s:8070/" % PUBLIC_HOST, "files": out, "count": len(out), "bytes": total}


_EXCERPTS = {}


def plan_excerpt(src, updated):
    """First prose paragraph and the ## headings of a published page's source markdown."""
    key = (src, updated)
    if key in _EXCERPTS:
        return _EXCERPTS[key]
    try:
        with open(src, encoding="utf-8", errors="replace") as f:
            head = f.read(65536)
    except OSError:
        head = ""
    fence = done = False
    para, outline = [], []
    for line in head.splitlines():
        line = line.strip()
        if line.startswith("```"):
            fence = not fence
            continue
        if fence:
            continue
        if line.startswith("## ") and len(outline) < 12:
            outline.append(re.sub(r"[*_`]", "", line[3:]).strip())
        if done or not line or line.startswith(("#", ">", "---", "|", "!", "<")):
            done = done or bool(para)
            continue
        line = re.sub(r"^[-*+]\s+|^\d+[.)]\s+", "", line)
        line = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", line)
        line = re.sub(r"[*_`]", "", line).strip()
        if len(line) > 3 or para:
            para.append(line)
    text = " ".join(para)
    if src.endswith(".html"):
        tags = lambda m: html.unescape(" ".join(re.sub(r"<[^>]+>", " ", m).split()))
        outline = [tags(m) for m in re.findall(r"<h2[^>]*>(.*?)</h2>", head, re.S)][:12]
        text = next((tags(m) for m in re.findall(r"<p[^>]*>(.*?)</p>", head, re.S) if len(tags(m)) > 3), "")
    _EXCERPTS[key] = (text if len(text) <= 320 else text[:319] + "…", outline)
    if len(_EXCERPTS) > 200:
        _EXCERPTS.clear()
    return _EXCERPTS[key]


def plans():
    p = os.path.join(PLANS, "index.json")
    if not os.path.exists(p):
        return []
    try:
        idx = json.load(open(p))
    except ValueError:
        return []
    idx.sort(key=lambda e: e.get("updated", ""), reverse=True)
    idx = idx[:20]
    for e in idx:
        e["excerpt"], e["outline"] = plan_excerpt(e.get("source", ""), e.get("updated", ""))
    return idx


_index_lock = threading.Lock()


def trash(path):
    """Move path (a link itself, not its target) to the freedesktop trash; the error text, or None."""
    r = subprocess.run(["gio", "trash", path], capture_output=True, text=True, timeout=25)
    return (r.stderr.strip() or "trash failed") if r.returncode else None


def delete_drop(raw):
    """Trash one ~/drop file or folder: (status, payload); 400 for anything outside, hidden or missing."""
    hit = fs_path(urllib.parse.quote(raw)) if isinstance(raw, str) else None
    if not hit or not hit[1]:
        return 400, {"error": "bad path"}
    root = os.path.realpath(DROP)
    parent = os.path.realpath(os.path.join(root, os.path.dirname(hit[1])))
    path = os.path.join(parent, os.path.basename(hit[1]))
    if parent != root and not parent.startswith(root + os.sep) or not os.path.lexists(path):
        return 400, {"error": "not found"}
    err = trash(path)
    if err:
        return 500, {"error": err}
    forget("drop")
    return 200, {"ok": True, "trashed": hit[1]}


def delete_doc(slug):
    """Trash one published page's folder and drop its plans/index.json entry (temp file, then rename)."""
    p = os.path.join(PLANS, "index.json")
    with _index_lock:
        try:
            idx = json.load(open(p))
        except (OSError, ValueError):
            idx = []
        if not isinstance(slug, str) or not slug or slug[0] == "." or "/" in slug or "\\" in slug \
                or slug not in [e.get("slug") for e in idx]:
            return 400, {"error": "unknown doc"}
        folder = os.path.join(PLANS, slug)
        err = trash(folder) if os.path.lexists(folder) else None
        if err:
            return 500, {"error": err}
        tmp = p + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump([e for e in idx if e.get("slug") != slug], f, indent=1)
        os.replace(tmp, p)
    forget("plans")
    return 200, {"ok": True, "trashed": slug}


@route("POST", "/api/files/delete")
def files_delete_route(h, path):
    body = h.body_json(4096, {})
    code, out = delete_drop(body.get("path") if isinstance(body, dict) else None)
    h.json(out, code)


@route("POST", "/api/docs/delete")
def docs_delete_route(h, path):
    body = h.body_json(4096, {})
    code, out = delete_doc(body.get("slug") if isinstance(body, dict) else None)
    h.json(out, code)


@route("GET", "/api/ls")
def ls_route(h, path):
    code, out = ls_dir(urllib.parse.parse_qs(h.path.partition("?")[2]).get("p", [""])[0])
    h.json(out, code)


@route("GET", "/files/", prefix=True)
def files_route(h, path):
    drop_file(h, path[7:], h.path.partition("?")[2])


def drop_file(h, raw, query):
        """Serve one ~/drop file inline (or as a download with ?dl=1); confined by fs_path."""
        hit = fs_path(raw)
        if not hit:
            return h.send(400, b"bad name\n", "text/plain")
        full, rel = hit
        if not rel or not os.path.isfile(full):
            return h.send(404, b"not found\n", "text/plain")
        name = os.path.basename(rel)
        ext = os.path.splitext(name)[1].lower()
        if "md=1" in query and ext in TEXT_EXT:
            text = open(full, encoding="utf-8", errors="replace").read()
            if ext == ".md":
                import markdown
                body = markdown.markdown(text, extensions=["extra", "sane_lists"], output_format="html5")
            else:
                body = "<pre>%s</pre>" % (text.replace("&", "&amp;").replace("<", "&lt;"))
            return h.send(200, body.encode(), "text/html; charset=utf-8")
        st = os.stat(full)
        size, etag = st.st_size, '"%x-%x"' % (st.st_mtime_ns, st.st_size)
        ctype = MIME.get(ext, "application/octet-stream")
        start, end = 0, size - 1
        m = re.match(r"bytes=(\d*)-(\d*)$", h.headers.get("Range", ""))
        if not m and h.fresh(etag):
            h.send_response(304)
            h.send_header("ETag", etag)
            h.send_header("Cache-Control", "no-cache")
            return h.end_headers()
        if m and size and (m.group(1) or m.group(2)):
            start = int(m.group(1)) if m.group(1) else max(0, size - int(m.group(2)))
            end = min(int(m.group(2)), size - 1) if m.group(2) and m.group(1) else size - 1
            if start > end:
                return h.send(416, b"", "text/plain")
        h.send_response(206 if m else 200)
        h.send_header("Content-Type", ctype)
        h.send_header("Accept-Ranges", "bytes")
        h.send_header("Content-Length", str(end - start + 1))
        if m:
            h.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        if "dl=1" in query:
            h.send_header("Content-Disposition", 'attachment; filename="%s"' % name.replace('"', ""))
        else:
            h.send_header("Content-Disposition", "inline")
        h.send_header("ETag", etag)
        h.send_header("Cache-Control", "no-cache")
        h.end_headers()
        with open(full, "rb") as f:
            f.seek(start)
            left = end - start + 1
            while left > 0:
                chunk = f.read(min(1 << 16, left))
                if not chunk:
                    break
                h.wfile.write(chunk)
                left -= len(chunk)
