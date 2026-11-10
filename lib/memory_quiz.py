"""The quiz checker: closed-book questions a small model answers from `memory load` plus the topic files (T1599-M07)."""
import hashlib
import importlib.machinery
import importlib.util
import os
import re
import sys
from collections import namedtuple

from memory_check import Finding
import memory_store  # noqa: E402 (memory_check puts bin/ on the path)

ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
QD, IDD = "checks/questions.d", "checks/ids.d"
VIEW_Q, VIEW_IDS, BASELINE = "checks/questions.tsv", "checks/ids.tsv", "checks/quiz-baseline.tsv"
QHEAD = ["key", "domain", "page", "id", "question", "must", "source"]
CHUNK = 25
Q = namedtuple("Q", "key domain page id question must")


def _tsv(path):
    """Rows of a tab-separated file with a header line, as dicts; [] when missing."""
    try:
        with open(path, encoding="utf-8") as f:
            rows = [l.rstrip("\n").split("\t") for l in f if l.strip()]
    except FileNotFoundError:
        return []
    return [dict(zip(rows[0], r)) for r in rows[1:]] if rows else []


def _files(store, folder, private):
    d = store.path(folder)
    names = sorted(os.listdir(d)) if os.path.isdir(d) else []
    return [os.path.join(d, n) for n in names if n.endswith(".tsv") and n.startswith("private-") == private]


def domain_of(page):
    parts = page.split("/")
    return "core" if parts[0] == "core" else parts[1] if parts[0] == "domains" and len(parts) > 2 else ""


def rows(store, private=False):
    """The questions.d rows (public, or the private-* files) in the view's columns; page from ids.d when a row names an id."""
    pages = {r["id"]: r["page"] for f in _files(store, IDD, False) for r in _tsv(f) if r.get("id")}
    out = []
    for f in _files(store, QD, private):
        for r in _tsv(f):
            q, i = r.get("question", "").strip(), r.get("id", "").strip()
            page = r.get("page") or pages.get(i, "")
            must = "|".join(w.strip() for w in re.split(r"[|;]", r.get("must", "")) if w.strip())
            if q and must:
                key = hashlib.sha1(q.encode("utf-8")).hexdigest()[:10]
                out.append({"key": key, "domain": domain_of(page), "page": page, "id": i, "question": q,
                            "must": must, "source": r.get("source", "")})
    return out


def merge(store):
    """Write the generated views checks/questions.tsv (public questions) and checks/ids.tsv from questions.d/ and ids.d/."""
    qs = rows(store)
    memory_store._atomic(store.path(VIEW_Q), "".join("\t".join(r) + "\n" for r in [QHEAD] + [[q[k] for k in QHEAD] for q in qs]))
    ids = [r for f in _files(store, IDD, False) for r in [l.rstrip("\n").split("\t") for l in open(f, encoding="utf-8")][1:] if any(r)]
    memory_store._atomic(store.path(VIEW_IDS), "\t".join(["id", "page", "state", "source"]) + "\n"
                         + "".join("\t".join(r) + "\n" for r in ids))
    return len(qs), len(ids)


def questions(store):
    """Every question: the public view (checks/questions.tsv) plus the private-* files, read at quiz time."""
    return [Q(r["key"], r["domain"], r["page"], r["id"], r["question"], r["must"].split("|"))
            for r in _tsv(store.path(VIEW_Q)) + rows(store, private=True)]


def _carrier():
    path = os.path.join(ROOT, "adapters", os.environ.get("HARNESS_AGENT") or "claude", "memory-carrier")
    loader = importlib.machinery.SourceFileLoader("memory_carrier", path)
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(mod)
    return mod


def ask(prompt, domains):
    """The one model call: the carrier's seam (MEMORY_QUIZ_CMD, else haiku through agent-exec, closed-book)."""
    os.environ["PATH"] = os.path.join(ROOT, "bin") + os.pathsep + os.environ.get("PATH", "")
    return _carrier().ask(prompt, domains)


def pages_for(store, domain):
    """What `memory load` does not give a worker: the domain's topic files and its PRIVATE pages (ledgers left out)."""
    card = store.card(domain)
    top = "core/" if domain == "core" else f"domains/{domain}/"
    return [p for p in store.pages() if p.startswith(top) and not p.endswith("/ledger.md")
            and (p != card or store.private_seats(p) is not None)]


def prompt(store, domain, qs):
    mem = "\n\n".join(f"## {p}\n" + memory_store.strip_ids(store.text(p)).strip() for p in pages_for(store, domain))
    return ("Closed-book quiz about your own memory. Answer only from your system prompt and the memory pages below; "
            "use no tool.\nUse the memory's own key words (numbers, names, commands, paths) exactly as written.\n"
            f"Reply with exactly {len(qs)} lines, each `<number>: <short answer>`.\n\n"
            f"<memory-pages>\n{mem}\n</memory-pages>\n\n<questions>\n"
            + "\n".join(f"{i}: {q.question}" for i, q in enumerate(qs, 1)) + "\n</questions>\n")


def answers(text):
    out = {}
    for line in text.splitlines():
        m = re.match(r"\s*\**(\d+)\**\s*[:.)]\s*(.*)", line)
        if m:
            out.setdefault(int(m.group(1)), " ".join(m.group(2).lower().split()))
    return out


def quiz(store, qs):
    """{key: [missing must words]} for the questions, asked per domain in chunks of CHUNK."""
    out = {}
    for dom in sorted({q.domain for q in qs}):
        group = [q for q in qs if q.domain == dom]
        for c in range(0, len(group), CHUNK):
            part = group[c:c + CHUNK]
            got = answers(ask(prompt(store, dom, part), [] if dom == "core" else [dom]))
            for i, q in enumerate(part, 1):
                out[q.key] = [w for w in q.must if " ".join(w.lower().split()) not in got.get(i, "")]
    return out


def changed(store, before):
    """Pages whose text differs from before (added and removed ones included)."""
    now = set(store.pages())
    return {p for p in now | set(before) if p not in now or p not in before or store.text(p) != before[p]}


def check(store, before, only_changed=False):
    """A question green in the baseline that is red now is a finding; a green gate updates the baseline for the asked ones."""
    qs = questions(store)
    if only_changed:
        pages = changed(store, before)
        qs = [q for q in qs if q.page in pages]
    base = {r["key"]: r for r in _tsv(store.path(BASELINE))}
    miss = quiz(store, qs) if qs else {}
    out = [Finding("quiz", q.page, 0, f"{q.id or q.key}: green in the baseline, red now (missing: {', '.join(miss[q.key])})")
           for q in qs if miss[q.key] and base.get(q.key, {}).get("pass") == "1"]
    for q in qs:
        if miss[q.key] and not any(f.what.startswith(f"{q.id or q.key}:") and f.file == q.page for f in out):
            print(f"quiz · red · {q.page} · {q.id or q.key}", file=sys.stderr)
    print(f"quiz · {sum(not m for m in miss.values())}/{len(qs)} green", file=sys.stderr)
    if not out and qs:
        keep = {q.key for q in questions(store)}
        base = {k: r for k, r in base.items() if k in keep}
        base.update({q.key: {"key": q.key, "pass": "0" if miss[q.key] else "1", "page": q.page, "id": q.id} for q in qs})
        memory_store._atomic(store.path(BASELINE), "key\tpass\tpage\tid\n" + "".join(
            f"{r['key']}\t{r['pass']}\t{r['page']}\t{r['id']}\n" for r in sorted(base.values(), key=lambda r: (r["page"], r["key"]))))
    return out


if __name__ == "__main__":
    if sys.argv[1:] != ["merge"]:
        sys.exit("usage: memory_quiz.py merge   (regenerate checks/questions.tsv and checks/ids.tsv)")
    n_q, n_ids = merge(memory_store.Store(memory_store.home()))
    print(f"wrote {VIEW_Q} ({n_q} questions), {VIEW_IDS} ({n_ids} ids)")
