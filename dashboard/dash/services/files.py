"""The ~/drop file browser, drop files served with Range, and the published plan pages."""
import html, json, os, re, subprocess, sys, threading, urllib.parse, zipfile
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
PREVIEW_MAX = 2 << 20
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
    val = (text if len(text) <= 320 else text[:319] + "…", outline)
    if len(_EXCERPTS) >= 200:
        _EXCERPTS.clear()
    _EXCERPTS[key] = val
    return val


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


TRASH_CAP = 120
MAX_BATCH = 2000


def trash(*paths):
    """Move paths (a link itself, not its target) to the freedesktop trash within TRASH_CAP s; the error text, or None."""
    t = min(TRASH_CAP, 25 + 2 * len(paths))
    try:
        r = subprocess.run(["gio", "trash", "--", *paths], capture_output=True, text=True, timeout=t)
    except subprocess.TimeoutExpired:
        return "trash timed out after %d s" % t
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


PROTECTED = [os.path.join(HOME, p) for p in ("agent-work/owner", "Documents", "moodle-envs", "agents/backups", "agents/secrets")]


def entry_path(raw):
    """A drop-relative name as (rel, absolute path with the parent resolved, the link itself kept), or None."""
    rel = raw.rstrip("/") if isinstance(raw, str) else ""
    parts = rel.split("/")
    if not rel or any(not p or p.startswith(".") or "\\" in p or "\x00" in p for p in parts):
        return None
    root = os.path.realpath(DROP)
    parent = os.path.realpath(os.path.join(root, *parts[:-1]))
    if parent != root and not parent.startswith(root + os.sep):
        return None
    return rel, os.path.join(parent, parts[-1])


def drop_entry(raw):
    """One requested drop entry as (rel, path to trash, None), or (raw, None, reason) when it is refused."""
    hit = entry_path(raw)
    if not hit:
        return raw, None, "outside the drop or hidden"
    rel, path = hit
    if not os.path.lexists(path):
        return rel, None, "missing"
    real = os.path.realpath(path)
    if os.path.islink(path) and not real.startswith(os.path.realpath(DROP) + os.sep):
        return rel, None, "symlink out of the drop"
    if any(real == p or real.startswith(p + os.sep) for p in map(os.path.realpath, PROTECTED)):
        return rel, None, "owner data"
    return rel, path, None


def tree_bytes(path):
    """Bytes under a drop entry, links not followed."""
    if os.path.islink(path) or not os.path.isdir(path):
        return os.lstat(path).st_size
    total = 0
    for d, _, names in os.walk(path):
        for n in names:
            try:
                total += os.lstat(os.path.join(d, n)).st_size
            except OSError:
                pass
    return total


def delete_many(paths, dry=False):
    """Trash several drop entries, all validated first: (status, payload); 207 when only some went; dry only counts them."""
    if not isinstance(paths, list) or not paths:
        return 400, {"error": "paths: a non-empty list"}
    if len(paths) > MAX_BATCH:
        return 400, {"error": "too many: %d items, at most %d per request" % (len(paths), MAX_BATCH), "count": len(paths)}
    picked = {}
    for raw in paths:
        rel, path, why = drop_entry(raw)
        if why:
            return 400, {"error": "refused %s: %s" % (rel, why), "path": rel}
        picked[rel] = path
    rels = [r for r in picked if not any(r.startswith(o + "/") for o in picked)]
    if dry:
        return 200, {"count": len(rels), "bytes": sum(tree_bytes(picked[r]) for r in rels)}
    err = trash(*[picked[r] for r in rels])
    done = [r for r in rels if not os.path.lexists(picked[r])]
    forget("drop")
    failed = [r for r in rels if r not in done]
    if err or failed:
        err = err or "trash left %d of %d in the drop" % (len(failed), len(rels))
        return (207 if done else 500), {"error": err, "trashed": done, "failed": failed}
    return 200, {"ok": True, "trashed": done}


def trash_dir():
    """The home trash that gio uses for drop entries (freedesktop spec)."""
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(os.environ.get("HOME", HOME), ".local", "share")
    return os.path.join(data, "Trash")


def restore_many(paths):
    """Put trashed drop entries back where they were, newest trash entry per path: (status, payload)."""
    if not isinstance(paths, list) or not paths:
        return 400, {"error": "paths: a non-empty list"}
    if len(paths) > MAX_BATCH:
        return 400, {"error": "too many: %d items, at most %d per request" % (len(paths), MAX_BATCH), "count": len(paths)}
    info, want = os.path.join(trash_dir(), "info"), {}
    for raw in paths:
        hit = entry_path(raw)
        if not hit:
            return 400, {"error": "refused %s: outside the drop or hidden" % raw, "path": raw}
        want[hit[1]] = hit[0]
    found = {}
    for n in os.listdir(info) if os.path.isdir(info) else []:
        if not n.endswith(".trashinfo"):
            continue
        try:
            with open(os.path.join(info, n), encoding="utf-8") as f:
                meta = dict(l.strip().split("=", 1) for l in f if "=" in l)
        except (OSError, ValueError):
            continue
        orig = urllib.parse.unquote(meta.get("Path", ""))
        if orig in want:
            when = (meta.get("DeletionDate", ""), os.stat(os.path.join(info, n)).st_mtime_ns)
            if orig not in found or when > found[orig][0]:
                found[orig] = (when, n[:-10])
    done, failed = [], []
    for orig, rel in want.items():
        if orig not in found or os.path.lexists(orig) or not os.path.isdir(os.path.dirname(orig)):
            failed.append(rel)
            continue
        name = found[orig][1]
        try:
            os.rename(os.path.join(trash_dir(), "files", name), orig)
        except OSError:
            failed.append(rel)
            continue
        os.remove(os.path.join(info, name + ".trashinfo"))
        done.append(rel)
    forget("drop")
    if not done:
        return 409, {"error": "nothing to restore", "restored": [], "failed": failed}
    return 200, {"restored": done, "failed": failed}


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


def journal(h, verb, paths, done):
    """One stderr (journal) line per delete or restore: count, first paths and who sent it."""
    paths = paths if isinstance(paths, list) else [paths]
    fwd = h.headers.get("X-Forwarded-For", "").split(",")[0].strip()
    print("files %s n=%d %s=%d first=%s ip=%s ua=%s ts-user=%s" % (
        verb, len(paths), "restored" if verb == "restore" else "trashed", len(done), json.dumps(paths[:3])[:300],
        json.dumps(fwd or h.client_address[0]), json.dumps(h.headers.get("User-Agent", "")[:80]),
        json.dumps(h.headers.get("Tailscale-User-Login") or "-")), file=sys.stderr, flush=True)


@route("POST", "/api/files/delete")
def files_delete_route(h, path):
    body = h.body_json(4096, {})
    raw = body.get("path") if isinstance(body, dict) else None
    code, out = delete_drop(raw)
    if isinstance(raw, str):
        journal(h, "delete", raw, [out["trashed"]] if code == 200 else [])
    h.json(out, code)


@route("POST", "/api/files/delete-many")
def files_delete_many_route(h, path):
    body = h.body_json(1 << 20, {})
    body = body if isinstance(body, dict) else {}
    code, out = delete_many(body.get("paths"), body.get("dry") is True)
    if body.get("dry") is not True:
        journal(h, "delete-many", body.get("paths"), out.get("trashed", []))
    h.json(out, code)


@route("POST", "/api/files/restore")
def files_restore_route(h, path):
    body = h.body_json(1 << 20, {})
    raw = body.get("paths") if isinstance(body, dict) else None
    code, out = restore_many(raw)
    journal(h, "restore", raw, out.get("restored", []))
    h.json(out, code)


@route("POST", "/api/docs/delete")
def docs_delete_route(h, path):
    body = h.body_json(4096, {})
    code, out = delete_doc(body.get("slug") if isinstance(body, dict) else None)
    h.json(out, code)


@route("GET", "/api/ls")
def ls_route(h, path):
    code, out = ls_dir(urllib.parse.quote(urllib.parse.parse_qs(h.path.partition("?")[2]).get("p", [""])[0]))
    h.json(out, code)


_md = None
_md_lock = threading.Lock()


def md_html(text):
    """Markdown to HTML on one reused converter; a new converter per call grew RSS ~140 KB a preview."""
    global _md
    with _md_lock:
        if _md is None:
            import markdown
            _md = markdown.Markdown(extensions=["extra", "sane_lists"], output_format="html5")
        return _md.reset().convert(text)


def zip_members(raws):
    """(archive name, absolute file) pairs under the requested drop entries, or None when one is refused by fs_path."""
    hits = [fs_path(urllib.parse.quote(r)) for r in raws if isinstance(r, str)]
    if not hits or len(hits) != len(raws) or any(not h or not h[1] or not os.path.exists(h[0]) for h in hits):
        return None
    rels = sorted({h[1] for h in hits})
    rels = [r for r in rels if not any(r.startswith(o + "/") for o in rels)]
    base = os.path.dirname(rels[0]) if len(rels) == 1 else os.path.commonpath(rels)
    root = os.path.realpath(DROP) + os.sep
    out = []
    for rel in rels:
        full = fs_path(urllib.parse.quote(rel))[0]
        arc = os.path.relpath(os.path.join(DROP, rel), os.path.join(DROP, base))
        if os.path.isfile(full):
            out.append((arc, full))
            continue
        for d, dirs, names in os.walk(full):
            dirs[:] = sorted(n for n in dirs if not n.startswith(".") and not os.path.islink(os.path.join(d, n)))
            for n in sorted(names):
                p = os.path.join(d, n)
                if n.startswith(".") or not os.path.isfile(p) or not os.path.realpath(p).startswith(root):
                    continue
                out.append((os.path.join(arc, os.path.relpath(p, full)), p))
    return out


def zip_name(raws):
    """`<folder>.zip` for one entry, `<parent>-selection.zip` for several."""
    rels = [r.strip("/") for r in raws]
    if len(rels) == 1:
        return os.path.splitext(os.path.basename(rels[0]))[0] + ".zip"
    parent = os.path.basename(os.path.commonpath(rels)) or "drop"
    return parent + "-selection.zip"


def write_zip(stream, members):
    """Stream a stored zip64 archive of members to a write-only stream; unreadable files are skipped."""
    with zipfile.ZipFile(stream, "w", zipfile.ZIP_STORED, allowZip64=True) as zf:
        for arc, full in members:
            try:
                zf.write(full, arc)
            except OSError:
                continue


@route("GET", "/api/files/zip")
def files_zip_route(h, path):
    raws = urllib.parse.parse_qs(h.path.partition("?")[2]).get("p", [])
    members = zip_members(raws) if 0 < len(raws) <= MAX_BATCH else None
    if members is None:
        return h.send(400, b"bad path\n", "text/plain")
    name = zip_name(raws)
    ascii_name = re.sub(r"[^ -~]+", "_", name.replace('"', ""))
    h.send_response(200)
    h.send_header("Content-Type", "application/zip")
    h.send_header("Content-Disposition", "attachment; filename=\"%s\"; filename*=UTF-8''%s"
                  % (ascii_name, urllib.parse.quote(name, safe="")))
    h.send_header("Cache-Control", "no-store")
    h.send_header("Connection", "close")
    h.end_headers()
    h.close_connection = True
    if not getattr(h, "head_only", False):
        write_zip(h.wfile, members)


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
            with open(full, "rb") as f:
                data = f.read(PREVIEW_MAX + 1)
            text = data[:PREVIEW_MAX].decode("utf-8", errors="replace")
            if ext == ".md":
                body = md_html(text)
            else:
                body = "<pre>%s</pre>" % (text.replace("&", "&amp;").replace("<", "&lt;"))
            if len(data) > PREVIEW_MAX:
                body += '<p><em>Truncated at %d MB; <a href="/files/%s?dl=1">download</a> for the rest.</em></p>' % (
                    PREVIEW_MAX >> 20, urllib.parse.quote(rel))
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
            ascii_name = re.sub(r"[^ -~]+", "_", name.replace('"', ""))
            h.send_header("Content-Disposition", "attachment; filename=\"%s\"; filename*=UTF-8''%s"
                          % (ascii_name, urllib.parse.quote(name, safe="")))
        else:
            h.send_header("Content-Disposition", "inline")
        h.send_header("ETag", etag)
        h.send_header("Cache-Control", "no-cache")
        h.end_headers()
        if getattr(h, "head_only", False):
            return
        h.wfile.flush()
        with open(full, "rb") as f:
            h.request.sendfile(f, start, end - start + 1)
