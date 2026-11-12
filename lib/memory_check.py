"""The memory gate: a registry of small checkers, each check(store, before) -> [Finding] (T1599, stdlib + fleet libs)."""
import json
import os
import re
import subprocess
import sys
from collections import namedtuple
from functools import lru_cache

BIN = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "bin")
sys.path.insert(0, BIN)
import memory_store  # noqa: E402
import protectedlib  # noqa: E402
import redact  # noqa: E402
from memory_transcript import _norm, owner_words  # noqa: E402

Finding = namedtuple("Finding", "checker file line what")
RAW = "archive/2026-11-auto-memory/"
EXTRA_BUDGETS = {"INDEX.md": 3072}
LINE_MAX = 200
NMV_TEST = os.path.join(BIN, "tests", "no-machine-values.test.sh")
IMPERATIVE = re.compile(r"^\W*(always|never|must|do not|don't|ignore|run|push|delete|remove|use|stop|disable|enable"
                        r"|allow|grant|commit|send|execute|install|give|set|add)\b|\b(always|never|must)\b", re.I)
URL = re.compile(r"\b[a-z][a-z0-9+.-]*://\S+|\bwww\.\S+", re.I)
EMAIL = re.compile(r"[\w.+-]+@[\w-]+(\.[\w-]+)+")
PATHLIKE = re.compile(r"(?<![\w.~/-])(~?/[\w.@+-]+(?:/[\w.@+-]+)*)")


def fmt(f):
    """One report line: checker · file:line · what (line 0 = the whole file)."""
    return f"{f.checker} · {f.file}:{f.line} · {f.what}"


def _read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (UnicodeDecodeError, OSError):
        return None


def lint_files(store):
    """(relative path, text) of every text file under the store except .git/ and the raw originals."""
    out = []
    for r, ds, fs in os.walk(store.root):
        ds[:] = sorted(d for d in ds if d != ".git")
        for name in sorted(fs):
            rel = os.path.relpath(os.path.join(r, name), store.root)
            text = None if rel.startswith((RAW, "net/graph")) else _read(os.path.join(r, name))
            if text is not None:
                out.append((rel, text))
    return out


def is_note(rel):
    return "inbox" in rel.split("/")[:-1]


def note_fields(text):
    """A note's `key: value` lines as a dict; quote decoded from its JSON string."""
    d = dict(l.split(": ", 1) for l in text.splitlines() if ": " in l)
    try:
        d["quote"] = json.loads(d["quote"]) if "quote" in d else None
    except ValueError:
        pass
    return d


def notes(store):
    return [(rel, note_fields(t)) for rel, t in lint_files(store) if is_note(rel)]


def fact_pages(pages):
    """Cards and topic files: the ledgers (append-only evidence) left out."""
    return [p for p in pages if not p.endswith("/ledger.md")]


def budgets(store, before):
    """Each page, INDEX.md and note within its byte budget (COMMON-RULES Always 4)."""
    out, pages = [], set(store.pages())
    for rel, text in lint_files(store):
        cap = (memory_store.NOTE_MAX if is_note(rel) else EXTRA_BUDGETS.get(rel)
               or (store.budget(rel) if rel in pages else None))
        size = len(text.encode("utf-8"))
        if cap and size > cap:
            out.append(Finding("budgets", rel, 0, f"{size} B over the {cap} B budget: rewrite denser or move detail down"))
    return out


def ids(store, before):
    """No id twice; every id live before is live, merged into a live id, or retired with a reason (checks/ids.tsv)."""
    out, live = [], {}
    for page in fact_pages(store.pages()):
        for n, line in enumerate(store.lines(page), 1):
            if line.id in live:
                out.append(Finding("ids", page, n, f"duplicate id ^{line.id} (first at {live[line.id]})"))
            elif line.id:
                live[line.id] = f"{page}:{n}"
    states = {}
    for row in (_read(store.path("checks/ids.tsv")) or "").splitlines()[1:]:
        cols = row.split("\t")
        if len(cols) >= 3:
            states[cols[0]] = cols[2]
    for page in fact_pages(sorted(before)):
        for raw in before[page].splitlines():
            i = memory_store.parse(raw).id
            st = states.get(i or "", "")
            if not i or i in live or (st.startswith("merged:") and st[7:].strip() in live) \
                    or (st.startswith("retired:") and st[8:].strip()):
                continue
            out.append(Finding("ids", page, 0, f"id ^{i} lost: not live, not merged into a live id, not retired with a reason"))
    return out


def line_format(store, before):
    """Cards and topic files: at most 200 characters a line (id left out), every fact line carries a ^id."""
    out = []
    for page in fact_pages(store.pages()):
        for n, line in enumerate(store.lines(page), 1):
            body = memory_store.strip_ids(line.raw).rstrip()
            if not body.strip() or body.startswith("#") or (n == 1 and body.startswith("PRIVATE:")):
                continue
            if len(body) > LINE_MAX:
                out.append(Finding("format", page, n, f"{len(body)} characters, the limit is {LINE_MAX}: one fact per line"))
            if body.lstrip().startswith("- ") and not line.id:
                out.append(Finding("format", page, n, "fact line without a permanent ^id"))
    return out


def secrets(store, before):
    """No line a redaction pattern (lib/redact.py) would change; the hit is masked, never printed."""
    return [Finding("secrets", rel, n, "secret-like text (masked): name the config key, never the value")
            for rel, text in lint_files(store) for n, l in enumerate(text.splitlines(), 1) if redact.redact(l) != l]


@lru_cache(maxsize=1)
def machine_patterns():
    """Bounded patterns for this machine's values, from the same sources as no-machine-values.test.sh (no second list)."""
    src = _read(NMV_TEST) or ""
    head = "\n".join(re.findall(r"^(?:CONF|PRIV)=.*$", src, re.M))
    fn = re.search(r"^values\(\) \{.*?^\} 2>/dev/null$", src, re.S | re.M)
    if not fn:
        raise RuntimeError(f"values() not found in {NMV_TEST}")
    got = subprocess.run(["bash", "-c", f"{head}\n{fn.group(0)}\nvalues"], capture_output=True, text=True, timeout=30).stdout
    out = []
    for v in sorted({v.strip() for v in got.splitlines() if len(v.strip()) >= 4}):
        e = re.escape(v)
        if re.fullmatch(r"([0-9a-f]{2}:){5}[0-9a-f]{2}", v, re.I):
            e = e.replace(":", "[:_-]")
        out.append(re.compile(rf"(?<![A-Za-z0-9]){e}(?![A-Za-z0-9])", re.I))
    return out


def machine_values(store, before):
    """No host, IP, MAC, home path, identity or private-values entry; the value is never printed."""
    pats = machine_patterns()
    return [Finding("machine-values", rel, n, "machine value (masked): name the config key, never the value")
            for rel, text in lint_files(store) for n, l in enumerate(text.splitlines(), 1) if any(p.search(l) for p in pats)]


def untrusted(store, before):
    """An untrusted note keeps the outside words in its quote: its text is no imperative and no copy of the quote."""
    out = []
    for rel, d in notes(store):
        if d.get("source") != "untrusted":
            continue
        text, quote = d.get("text", ""), d.get("quote") or ""
        if IMPERATIVE.search(text) or (quote.strip() and _norm(quote) in _norm(text)):
            out.append(Finding("untrusted", rel, 0, "untrusted text outside the quote reads as an order: hold it as quoted data"))
    return out


def provenance(store, before):
    """A note stamped `owner` carries a quote found in the owner's turns of the transcript its session names."""
    out = []
    for rel, d in notes(store):
        if d.get("source") != "owner":
            continue
        quote, said = d.get("quote"), owner_words(d.get("session", ""))
        if not quote or not quote.strip():
            out.append(Finding("provenance", rel, 0, "source owner without a quote"))
        elif said is None:
            out.append(Finding("provenance", rel, 0, "source owner: no transcript for its session"))
        elif _norm(quote) not in said:
            out.append(Finding("provenance", rel, 0, "source owner: the quote is not in the owner's turns of its transcript"))
    return out


def experience_only(store, before):
    """In a protected domain: no URL, e-mail, fenced code or path under a `protected list` path."""
    domains = {d for _, d, fl in store.map() if "protected" in fl}
    if not domains:
        return []
    roots = [os.path.normpath(p) for p in protectedlib.lexical_paths()]
    out = []
    for rel, text in lint_files(store):
        parts = rel.split("/")
        in_domain = len(parts) > 2 and parts[0] == "domains" and parts[1] in domains
        if not (in_domain or (is_note(rel) and note_fields(text).get("domain") in domains)):
            continue
        for n, l in enumerate(text.splitlines(), 1):
            paths = [os.path.normpath(os.path.expanduser(p)) for p in PATHLIKE.findall(URL.sub(" ", l))]
            what = ("a URL" if URL.search(l) else "an e-mail address" if EMAIL.search(l)
                    else "fenced code" if l.lstrip().startswith(("```", "~~~"))
                    else "a protected project path" if any(p == r or p.startswith(r + "/") for p in paths for r in roots)
                    else None)
            if what:
                out.append(Finding("experience-only", rel, n, f"{what} in protected domain: keep experience only"))
    return out


def quiz(store, before):
    """The closed-book quiz (lib/memory_quiz.py): a question green in the baseline that turns red."""
    import memory_quiz
    return memory_quiz.check(store, before)


def quiz_changed(store, before):
    """The quiz on the questions of pages that changed since before."""
    import memory_quiz
    return memory_quiz.check(store, before, only_changed=True)


def concepts(store, before):
    """net/concepts.d (once it exists): header, 5 columns, row <= 200 characters, gist <= 6 words, a live id once, in its
    domain's file, a PRIVATE page's id only in a git-ignored private-<d>.tsv, a row for every live public id."""
    import memory_concepts as mc
    import memory_route
    if not os.path.isdir(store.path(mc.DIR)):
        return []
    live = {}
    for page in fact_pages(store.pages()):
        dom = "core" if page.startswith("core/") else page.split("/")[1]
        live.update({l.id: (dom, memory_route.seats_of(store, page) is not None) for l in store.lines(page) if l.id})
    out, seen = [], set()
    for rel in mc.files(store, private=True):
        name = os.path.basename(rel)[:-4]
        priv_file, dom = name.startswith(mc.PRIVATE_PREFIX), name.removeprefix(mc.PRIVATE_PREFIX)
        head, rows = mc.rows(store, rel)
        if head != mc.HEADER:
            out.append(Finding("concepts", rel, 1, "header is not: " + mc.HEADER.replace("\t", " <tab> ")))
        for r in rows:
            what = ("not 5 tab-separated columns" if r.raw.count("\t") != len(mc.COLS) - 1
                    else f"{len(r.raw)} characters, the limit is {mc.ROW_MAX}" if len(r.raw) > mc.ROW_MAX
                    else f"gist over {mc.GIST_WORDS} words" if not 0 < len(r.gist.split()) <= mc.GIST_WORDS
                    else "no concepts or no Spanish aliases" if not (r.concepts.strip() and r.es.strip())
                    else f"^{r.id} is not a live id" if r.id not in live
                    else f"^{r.id} has a row already" if r.id in seen
                    else f"^{r.id} lives in domain {live[r.id][0]}, not {dom}" if live[r.id][0] != dom
                    else f"^{r.id} is on a PRIVATE page: its row goes in {mc.DIR}/{mc.PRIVATE_PREFIX}{dom}.tsv"
                    if live[r.id][1] and not priv_file else None)
            seen.add(r.id)
            if what:
                out.append(Finding("concepts", rel, r.line, what))
    out += [Finding("concepts", f"{mc.DIR}/{d}.tsv", 0, f"^{i} has no concepts row")
            for i, (d, priv) in sorted(live.items()) if not priv and i not in seen]
    return out


CHECKERS = [budgets, ids, line_format, secrets, machine_values, untrusted, provenance, experience_only, concepts]
ON_DEMAND = {"quiz": quiz, "quiz-changed": quiz_changed}


def before_git(store):
    """{page: text} of the store's git HEAD (empty without a repo or a commit)."""
    def git(*a):
        return subprocess.run(["git", "-C", store.root, *a], capture_output=True, text=True)
    ls = git("ls-tree", "-r", "--name-only", "HEAD")
    if ls.returncode:
        return {}
    pages = [p for p in ls.stdout.splitlines() if p.endswith(".md") and p.split("/")[0] in ("core", "domains")
             and "inbox" not in p.split("/")]
    return {p: git("show", f"HEAD:{p}").stdout for p in pages}


def before_dir(path):
    """{page: text} of a store folder (the live side of a staging pair)."""
    prev = memory_store.Store(path)
    return {p: prev.text(p) for p in prev.pages()}


def run(store, before, folders=(), also=()):
    """Every checker's findings plus the named ON_DEMAND ones, kept to files under the given store-relative folders (none = all)."""
    scope = [f.rstrip("/") + "/" for f in folders if f not in ("", ".")]
    found = [f for c in CHECKERS + [ON_DEMAND[n] for n in also] for f in c(store, before)]
    return [f for f in found if not scope or any((f.file + "/").startswith(s) for s in scope)]
