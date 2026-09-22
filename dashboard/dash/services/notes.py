"""The Obsidian vault: listing, link index, rendered notes, today's view and the audio-notes day."""
import json, os, re, time, urllib.parse
from datetime import datetime
from dash.cache import TTL, cached, swr
from dash.env import HOME, run
from dash.routes import route

VAULT = os.path.realpath(os.path.expanduser(os.environ.get("NOTES_VAULT_DIR") or os.path.join(HOME, "obsidian-vault")))
AUDIO = "audio notes"
NOTE_EXT = (".md", ".txt")


def note_title(path, rel):
    """First H1 of the file, else the file name."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f.read(4096).splitlines():
                if line.startswith("# "):
                    return line[2:].strip()
    except OSError:
        pass
    return os.path.splitext(os.path.basename(rel))[0]


def vault():
    """Every .md/.txt note in the vault: rel path, title, folder, mtime, size."""
    out = []
    for root, dirs, files in os.walk(VAULT):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for n in sorted(files):
            if n.startswith(".") or os.path.splitext(n)[1].lower() not in NOTE_EXT:
                continue
            full = os.path.join(root, n)
            if not os.path.realpath(full).startswith(VAULT + os.sep):
                continue
            rel = os.path.relpath(full, VAULT)
            st = os.stat(full)
            out.append({"path": rel, "name": n, "title": note_title(full, rel), "folder": os.path.dirname(rel) or "/",
                        "mtime": st.st_mtime, "ctime": st.st_ctime, "bytes": st.st_size})
    out.sort(key=lambda n: n["mtime"], reverse=True)
    return {"notes": out, "count": len(out), "bytes": sum(n["bytes"] for n in out),
            "latest": [n for n in out if n["folder"] == AUDIO][:6], "audio": AUDIO}


def note_path(raw):
    """Confine a requested note to the vault: no traversal, no dotfiles, .md/.txt only; None if refused."""
    rel = urllib.parse.unquote(raw)
    parts = rel.split("/")
    if not rel or "\\" in rel or "\x00" in rel or any(not p or p.startswith(".") for p in parts):
        return None
    if os.path.splitext(rel)[1].lower() not in NOTE_EXT:
        return None
    full = os.path.realpath(os.path.join(VAULT, rel))
    if not full.startswith(VAULT + os.sep) or not os.path.isfile(full):
        return None
    return full


def frontmatter(text):
    """Split a leading YAML block off; returns (dict, body)."""
    m = re.match(r"^---\n(.*?)\n---\n?", text, re.S)
    if not m:
        return {}, text
    import yaml
    try:
        fm = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
        fm = {}
    return (fm if isinstance(fm, dict) else {}), text[m.end():]


WIKILINK = re.compile(r"!?\[\[([^\]|]+)(?:\|([^\]]*))?\]\]")


def link_maps(notes):
    """(by_path, by_name) lookups for resolving [[wikilinks]]: full path first, then bare basename."""
    by_path = {os.path.splitext(n["path"])[0].lower(): n["path"] for n in notes}
    by_name = {}
    for n in notes:
        by_name.setdefault(os.path.splitext(n["name"])[0].lower(), n["path"])
    return by_path, by_name


def resolve_link(target, maps):
    """[[Note#Heading|alias]] target -> vault path or None."""
    key = target.split("#")[0].strip().lower()
    return maps[0].get(key) or maps[1].get(key.split("/")[-1])


def note_tags(fm, body):
    tags = fm.get("tags") or []
    if isinstance(tags, str):
        tags = [t.strip() for t in tags.split(",") if t.strip()]
    tags = [str(t) for t in tags] + re.findall(r"(?:^|\s)#([A-Za-z][\w/-]+)", body)
    return sorted(set(tags), key=str.lower)


_index = (None, None)


def vault_index(v=None):
    """Per-note links, status, tags, headings, tasks and words; rebuilt only when the tree's newest mtime moves."""
    global _index
    v = v or cached("vault", TTL, vault)
    key = (v["count"], max([n["mtime"] for n in v["notes"]] or [0]))
    if _index[0] == key:
        return _index[1]
    maps = link_maps(v["notes"])
    idx = {}
    for n in v["notes"]:
        try:
            text = open(os.path.join(VAULT, n["path"]), encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        fm, body = frontmatter(text)
        off = text.count("\n") - body.count("\n")
        links = []
        for line in body.splitlines():
            for m in WIKILINK.finditer(line):
                if not m.group(1).split("#")[0].strip():
                    continue
                links.append({"target": m.group(1).split("#")[0].strip(), "path": resolve_link(m.group(1), maps),
                              "line": line.strip()[:200]})
        idx[n["path"]] = {
            "path": n["path"], "title": n["title"], "folder": n["folder"], "mtime": n["mtime"], "ctime": n["ctime"],
            "status": str(fm.get("status")) if fm.get("status") is not None else "",
            "tags": note_tags(fm, body),
            "headings": [h.strip() for h in re.findall(r"^#{1,6}[ \t]+(.+?)\s*$", body, re.M)],
            "links_out": links, "links_in": [],
            "tasks": [{"line": off + i + 1, "text": m.group(1).strip().replace("**", "")[:200]} for i, l in enumerate(body.splitlines())
                      for m in [re.match(r"^\s*[-*] \[ \]\s*(.*)$", l)] if m],
            "tasks_done": len(re.findall(r"^\s*[-*] \[[xX]\]", body, re.M)),
            "words": len(body.split()), "lines": body.count("\n") + 1, "body": body,
        }
        idx[n["path"]]["tasks_open"] = len(idx[n["path"]]["tasks"])
    for src in idx.values():
        seen = set()
        for l in src["links_out"]:
            if l["path"] in idx and (l["path"], l["line"]) not in seen:
                seen.add((l["path"], l["line"]))
                idx[l["path"]]["links_in"].append({"path": src["path"], "title": src["title"], "line": l["line"]})
    facets = {"folders": {}, "status": {}, "tags": {}}
    for e in idx.values():
        facets["folders"][e["folder"]] = facets["folders"].get(e["folder"], 0) + 1
        if e["status"]:
            facets["status"][e["status"]] = facets["status"].get(e["status"], 0) + 1
        for t in e["tags"]:
            facets["tags"][t] = facets["tags"].get(t, 0) + 1
    unresolved = sorted({(l["target"], e["path"]) for e in idx.values() for l in e["links_out"] if not l["path"]})
    out = {"notes": idx, "facets": facets, "unresolved": [{"target": t, "from": f} for t, f in unresolved]}
    _index = (key, out)
    return out


def notes_api():
    """/api/notes: the vault listing plus per-note status, tags, link counts and the facet counts."""
    v = cached("vault", TTL, vault)
    idx = vault_index()
    notes = []
    for n in v["notes"]:
        e = idx["notes"].get(n["path"], {})
        notes.append(dict(n, status=e.get("status", ""), tags=e.get("tags", []),
                          links_in=len(e.get("links_in", [])), links_out=len(e.get("links_out", []))))
    return dict(v, notes=notes, index=True, facets=idx["facets"], unresolved=idx["unresolved"])


def render_note(full):
    """Rendered note: frontmatter, tags, html with [[wikilinks]] resolved, plus what links here and where it links."""
    text = open(full, encoding="utf-8", errors="replace").read()
    fm, body = frontmatter(text)
    maps = link_maps(cached("vault", TTL, vault)["notes"])

    def link(m):
        target, alias = m.group(1), m.group(2)
        hit = resolve_link(target, maps)
        label = (alias or target).replace("&", "&amp;").replace("<", "&lt;")
        if hit:
            return '<a class="wl" href="#notes" data-note="%s">%s</a>' % (hit.replace('"', "&quot;"), label)
        return '<a class="wl miss" title="no such note">%s</a>' % label

    headings = []
    if full.endswith(".txt"):
        html = "<pre>%s</pre>" % body.replace("&", "&amp;").replace("<", "&lt;")
    else:
        import markdown
        body = re.sub(r"!\[\[([^\]|]+)(?:\|([^\]]*))?\]\]", lambda m: "[[%s]]" % m.group(1), body)
        from markdown.extensions.toc import slugify
        md = markdown.Markdown(extensions=["extra", "sane_lists", "toc"], output_format="html5",
                               extension_configs={"toc": {"slugify": lambda v, sep: "h-" + slugify(v, sep)}})
        html = re.sub(r"\[\[([^\]|]+)(?:\|([^\]]*))?\]\]", link, md.convert(body))
        stack = list(md.toc_tokens)
        while stack:
            t = stack.pop(0)
            headings.append({"level": t["level"], "text": t["name"], "id": t["id"]})
            stack = t["children"] + stack
    idx = vault_index()["notes"]
    e = idx.get(os.path.relpath(full, VAULT), {})
    out, seen = [], set()
    for l in e.get("links_out", []):
        if l["path"] and l["path"] not in seen:
            seen.add(l["path"])
            out.append({"path": l["path"], "title": idx[l["path"]]["title"], "line": l["line"]})
    near = {l["path"]: "in" for l in e.get("links_in", [])}
    for l in out:
        near[l["path"]] = "both" if l["path"] in near else "out"
    return {"frontmatter": {str(k): (", ".join(map(str, v)) if isinstance(v, list) else str(v)) for k, v in fm.items()},
            "tags": note_tags(fm, body), "html": html, "links_in": e.get("links_in", []), "links_out": out,
            "unresolved": sorted({l["target"] for l in e.get("links_out", []) if not l["path"]}, key=str.lower),
            "headings": headings,
            "neighbours": [{"path": p, "title": idx[p]["title"], "dir": d} for p, d in sorted(near.items())]}


def today_str():
    return datetime.now().strftime("%Y-%m-%d")


def first_para(body):
    """First paragraph of a note body that is not a heading, comment or list."""
    for block in re.split(r"\n\s*\n", body):
        t = re.sub(r"\*\*|^>\s*", "", " ".join(block.split()))
        if t and not t.startswith(("#", "<!--", "- ", "* ", "|", "```")):
            return t[:200]
    return ""


def notes_today():
    """/api/notes/today: today's daily note, the 5 newest files, open tasks from active or recently edited notes."""
    idx = vault_index()["notes"]
    day = today_str()
    daily, template = "Daily/%s.md" % day, "Process/daily-note-template.md"
    cut = time.time() - 30 * 86400
    recent = [{"path": e["path"], "title": e["title"], "mtime": e["mtime"], "ctime": e["ctime"], "line": first_para(e["body"])}
              for e in sorted(idx.values(), key=lambda e: -e["ctime"])[:5]]
    live = [e for e in sorted(idx.values(), key=lambda e: -e["mtime"])
            if "template" not in e["path"].lower() and (e["status"] == "active" or e["mtime"] >= cut)]
    tasks = [{"path": e["path"], "title": e["title"], "line": t["line"], "text": t["text"]} for e in live for t in e["tasks"]]
    return {"date": day, "daily": daily if daily in idx else None, "template": template if template in idx else None,
            "recent": recent, "tasks": tasks}


AUDIO_LINE = re.compile(r"^- (\d\d:\d\d)\s*[—→-]?\s*(.*)$")


def brain_state():
    """Is the notes brain connected to the Eye, and when did notes-file last write."""
    connected = None
    try:
        b = json.loads(run(["eye", "brains"], timeout=8))
        connected = any(x.get("name") == "notes" and x.get("connected") for x in b.get("brains", []))
    except Exception:
        pass
    last = ""
    try:
        for line in open(os.path.join(HOME, "agents/notes/logs/notes-file.log")):
            if " raw ok" in line or " apply ok" in line:
                last = line.split()[0]
    except OSError:
        pass
    return {"connected": connected, "last_filed": last}


def notes_audio():
    """/api/notes/audio: today's audio-notes day split into raw and refined, the ideas folder, the brain's state."""
    s = swr({"vault": (vault,), "brain": (brain_state,)})
    idx = vault_index(s["vault"])["notes"]
    maps = link_maps(s["vault"]["notes"])
    day = today_str()
    rel = "%s/%s.md" % (AUDIO, day)
    today = None
    if rel in idx:
        today, section = {"path": rel, "raw": [], "refined": []}, None
        for line in idx[rel]["body"].splitlines():
            if line.startswith("## "):
                section = line[3:].strip().lower()
                continue
            m = AUDIO_LINE.match(line)
            if not m or section not in ("raw", "refined"):
                continue
            if section == "raw":
                today["raw"].append({"at": m.group(1), "text": m.group(2)})
                continue
            wl = WIKILINK.search(m.group(2))
            target = wl.group(1) if wl else ""
            today["refined"].append({"at": m.group(1), "file": target.split("#")[0], "heading": target.partition("#")[2],
                                     "path": resolve_link(target, maps) if wl else None,
                                     "gist": WIKILINK.sub("", m.group(2)).replace("(?)", "").strip(),
                                     "sure": not m.group(2).rstrip().endswith("(?)")})
    ideas = [{"path": e["path"], "title": e["title"], "mtime": e["mtime"], "tags": e["tags"]}
             for e in sorted(idx.values(), key=lambda e: -e["mtime"]) if e["folder"] == AUDIO + "/ideas"]
    return {"date": day, "folder": AUDIO, "today": today, "ideas": ideas, "brain": s["brain"]}


@route("GET", "/api/notes")
def notes_route(h, path):
    h.json(notes_api())


@route("GET", "/api/notes/today")
def today_route(h, path):
    h.json(notes_today())


@route("GET", "/api/notes/audio")
def audio_route(h, path):
    h.json(notes_audio())


@route("GET", "/notes/", prefix=True)
def note_route(h, path):
    full = note_path(h.path.partition("?")[0][7:])
    if not full:
        return h.send(404, b"not found\n", "text/plain")
    h.json(render_note(full))
