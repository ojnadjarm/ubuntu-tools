"""Full-text search over the vault index: FTS5 in memory, facet prefixes, snippets."""
import os, re, threading, urllib.parse
from dash.routes import route
from dash.services import notes

_fts = (None, None)
_fts_lock = threading.Lock()


def fts():
    """In-memory FTS5 table over the index; rebuilt with it. None when sqlite has no FTS5."""
    global _fts
    import sqlite3
    idx = notes.vault_index()
    if _fts[0] == notes._index[0]:
        return _fts[1]
    conn = sqlite3.connect(":memory:", check_same_thread=False)
    try:
        conn.execute("create virtual table notes using fts5(title, headings, body, path, tokenize='unicode61 remove_diacritics 2')")
    except sqlite3.OperationalError:
        conn = None
    else:
        conn.executemany("insert into notes values (?,?,?,?)",
                         [(e["title"], "\n".join(e["headings"]), e["body"], os.path.splitext(e["path"])[0].replace("/", " "))
                          for e in idx["notes"].values()])
    _fts = (notes._index[0], conn)
    return conn


def parse_query(q):
    """'status:idea "exact phrase" gnn' -> ({status: idea}, ['"exact phrase"', 'gnn'])."""
    filters, terms = {}, []
    for tok in re.findall(r'"[^"]*"|\S+', q):
        m = re.match(r"^(status|folder|tag):(.+)$", tok, re.I)
        if m:
            filters[m.group(1).lower()] = m.group(2).strip('"').lower()
        elif tok.strip('"').strip():
            terms.append(tok)
    return filters, terms


def facet_ok(e, filters):
    f = filters.get("folder")
    if f and not (e["folder"].lower() == f or e["folder"].lower().startswith(f + "/")):
        return False
    if filters.get("status") and e["status"].lower() != filters["status"]:
        return False
    if filters.get("tag") and filters["tag"] not in [t.lower() for t in e["tags"]]:
        return False
    return True


def snippets(e, terms, limit=3):
    """Up to `limit` body lines that contain a term, escaped, the term wrapped in <mark>."""
    words = [t.strip('"').lower() for t in terms]
    out = []
    for line in e["body"].splitlines():
        low = line.lower()
        if line.strip().startswith("#") or not any(w in low for w in words):
            continue
        i = min(low.find(w) for w in words if w in low)
        s = line.strip()[max(0, i - 60):][:180]
        s = s.replace("&", "&amp;").replace("<", "&lt;")
        for w in sorted(words, key=len, reverse=True):
            s = re.sub("(%s)" % re.escape(w), r"<mark>\1</mark>", s, flags=re.I)
        out.append(s)
        if len(out) >= limit:
            break
    return out


def search_notes(q):
    """Ranked search: title hit > heading hit > body, bm25 within a tier; facet prefixes; snippets."""
    filters, terms = parse_query(q)
    if not filters and not terms:
        return {"count": 0, "hits": []}
    idx = notes.vault_index()["notes"]
    conn = fts()
    if not terms:
        paths = sorted(idx, key=lambda p: -idx[p]["mtime"])
    elif conn is None:
        words = [t.strip('"').lower() for t in terms]
        paths = [p for p, e in idx.items() if all(w in (e["title"] + "\n" + e["body"]).lower() for w in words)]
    else:
        match = " ".join('"%s"' % t.strip('"').replace('"', '""') + ("" if t.startswith('"') else "*") for t in terms)
        with _fts_lock:
            try:
                rows = conn.execute("select path, bm25(notes, 8, 3, 1, 6) from notes where notes match ? order by 2", (match,)).fetchall()
            except Exception:
                rows = []
        byname = {os.path.splitext(p)[0].replace("/", " "): p for p in idx}
        words = [t.strip('"').lower() for t in terms]
        score = {byname[r[0]]: round(-r[1], 4) for r in rows if r[0] in byname}

        def tier(p):
            e = idx[p]
            if any(w in (e["title"] + " " + os.path.basename(p)).lower() for w in words):
                return 0
            return 1 if any(w in h.lower() for h in e["headings"] for w in words) else 2
        paths = sorted(score, key=lambda p: (tier(p), -score[p]))
    hits = []
    for p in paths:
        e = idx[p]
        if not facet_ok(e, filters):
            continue
        hits.append({"path": p, "title": e["title"], "folder": e["folder"], "status": e["status"], "mtime": e["mtime"],
                     "score": score.get(p, 0) if terms and conn else 0, "snippets": snippets(e, terms) if terms else []})
        if len(hits) >= 60:
            break
    return {"count": len(hits), "hits": hits}


@route("GET", "/api/notes/search")
def search_route(h, path):
    h.json(search_notes(urllib.parse.parse_qs(h.path.partition("?")[2]).get("q", [""])[0]))
