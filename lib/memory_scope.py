"""Scope checkers of the memory gate (T2054): card lines keep his words out of the rule; a new core line needs a warrant."""
import os
import re

import memory_store
import memory_check as mc  # partly loaded here: attributes are read at call time

CARD_QUOTE = re.compile(r'"([^"]+)"|“([^”]+)”|«([^»]+)»')
QUOTE_WORDS = 4
GENERAL = re.compile(r"\bgeneral\b")


def _cards(store):
    return [p for p in store.pages() if p == "core/CORE.md" or p.endswith("/DOMAIN.md")]


def card_quotes(store, before):
    """A new or changed card line quotes no 4+ words of his: the rule is in plain words, his words stay on the topic page or ledger."""
    if not before:  # no before side: nothing to call new
        return []
    out = []
    for page in _cards(store):
        if page not in before and store.private_seats(page) is not None:  # git-ignored: no before side to compare
            continue
        old = {l.strip() for l in before.get(page, "").splitlines()}
        for n, line in enumerate(store.lines(page), 1):
            if line.raw.strip() in old:
                continue
            if any(len(next(g for g in m.groups() if g).split()) >= QUOTE_WORDS for m in CARD_QUOTE.finditer(line.raw)):
                out.append(mc.Finding("card-quotes", page, n, "his words in a card line: write the rule plainly, keep the quote on its topic page or ledger"))
    return out


def core_reach(store, before):
    """A new core id (once checks/ids.d exists) has a warrant: source `general` (his general word), a core id superseded
    by it (his newer word on a core line), or ids of 3 domains merged into it; else it belongs on its domain card."""
    d = store.path("checks/ids.d")
    if not os.path.isdir(d) or "core/CORE.md" not in store.pages() or "core/CORE.md" not in before:
        return []
    rows = [l.rstrip("\n").split("\t") for f in sorted(os.listdir(d)) if f.endswith(".tsv")
            for l in (mc._read(os.path.join(d, f)) or "").splitlines()[1:] if l.strip()]
    source = {r[0]: r[3] if len(r) > 3 else "" for r in rows if len(r) > 2 and r[1] == "core/CORE.md"}
    by = {x for r in rows if len(r) > 2 and r[1] == "core/CORE.md" for x in re.findall(r"by \^?([\w-]+)", r[2])}
    merged = {}
    for r in rows:
        if len(r) > 2 and r[2].startswith("merged:") and r[1].startswith("domains/"):
            merged.setdefault(r[2][7:].strip(), set()).add(r[1].split("/")[1])
    old = {memory_store.parse(l).id for l in before.get("core/CORE.md", "").splitlines()}
    out = []
    for n, line in enumerate(store.lines("core/CORE.md"), 1):
        i = line.id
        if not i or i in old or i in by or GENERAL.search(source.get(i, "")) or len(merged.get(i, ())) >= 3:
            continue
        out.append(mc.Finding("core-reach", "core/CORE.md", n, f"^{i}: the core takes his general word (source `general`), "
                           "his newer word on a core line (supersedes one) or a lesson merged from 3 domains; else its domain card"))
    return out


CHECKERS = [card_quotes, core_reach]
