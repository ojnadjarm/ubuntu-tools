"""The memory store's layout and line format: pages, parsed lines, budgets, domains.map, inbox notes (T1599, stdlib only)."""
import os
import re
import tempfile
import time
from collections import namedtuple

from agent_work import _key

NOTE_MAX = 1024
BUDGETS = {"core/CORE.md": 4096, "domains/orchestrator/DOMAIN.md": 8192}
CARD, TOPIC = 6144, 8192
Line = namedtuple("Line", "raw id dates topic")
ID = re.compile(r"[ \t]+\^([A-Za-z0-9-]+)[ \t]*$")
TOPIC_RX = re.compile(r"→\s*([\w./-]+)\s*$")
DATES = re.compile(r"\(((?:\d\d-\d\d-\d\d)(?:,\s*\d\d-\d\d-\d\d)*)\)")


def home():
    """The store folder: MEMORY_HOME from the environment, else its config.env line, else the default."""
    return _key("MEMORY_HOME") or os.path.expanduser("~/memory")


def strip_ids(text):
    """The text with every line's trailing ^id removed."""
    return "\n".join(ID.sub("", l) for l in text.split("\n"))


def parse(raw):
    """One page line as a Line: its permanent id, the owner's dates (yy-mm-dd) and its → topic."""
    m = ID.search(raw)
    body = raw[:m.start()] if m else raw
    t = TOPIC_RX.search(body)
    return Line(raw, m.group(1) if m else None,
                [d.strip() for g in DATES.findall(body) for d in g.split(",")], t.group(1) if t else None)


def _atomic(path, data):
    """Write data to path through a temp file in the same folder and a rename."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(data)
    os.replace(tmp, path)


class Store:
    """One memory store rooted at home; every path is relative to it."""

    def __init__(self, root):
        self.root = os.path.abspath(os.path.expanduser(root))

    def path(self, page):
        return os.path.join(self.root, page)

    def pages(self):
        """Relative paths of the cards and topic files under core/ and domains/ (inboxes left out), sorted."""
        out = []
        for top in ("core", "domains"):
            for r, ds, fs in os.walk(self.path(top)):
                ds[:] = [d for d in ds if d != "inbox" and not d.startswith(".")]
                out += [os.path.relpath(os.path.join(r, f), self.root) for f in fs if f.endswith(".md")]
        return sorted(out)

    def text(self, page):
        with open(self.path(page), encoding="utf-8") as f:
            return f.read()

    def lines(self, page):
        """The page's lines, parsed."""
        return [parse(l) for l in self.text(page).splitlines()]

    def write_page(self, staging, page, lines):
        """Write lines (Line or str) as page under the staging folder, atomically; returns the written path."""
        out = os.path.join(staging, page)
        _atomic(out, "".join((l.raw if isinstance(l, Line) else l) + "\n" for l in lines))
        return out

    def card(self, domain):
        """The card a domain's agents load ("core" is the core card)."""
        return "core/CORE.md" if domain == "core" else f"domains/{domain}/DOMAIN.md"

    def private_seats(self, page):
        """The seats a `PRIVATE: <seats>` first line names, or None when the page is not private."""
        with open(self.path(page), encoding="utf-8") as f:
            first = f.readline()
        return set(re.split(r"[\s,]+", first.split(":", 1)[1].strip())) if first.startswith("PRIVATE:") else None

    def budget(self, page):
        """The page's byte budget; None for a ledger (append-only)."""
        if page in BUDGETS:
            return BUDGETS[page]
        if page.endswith("/ledger.md"):
            return None
        return CARD if page.endswith("/DOMAIN.md") else TOPIC

    def map(self):
        """domains.map rows as (where, domain, flags): where is `~/<folder>` or `seat:<id>`."""
        try:
            with open(self.path("domains.map"), encoding="utf-8") as f:
                rows = [l.split() for l in f if l.strip() and not l.lstrip().startswith("#")]
        except FileNotFoundError:
            return []
        return [(r[0], r[1], set(r[2:])) for r in rows if len(r) >= 2]

    def domains(self):
        """Every domain named in domains.map."""
        return {d for _, d, _ in self.map()}

    def add_note(self, fields):
        """One new inbox file from ordered (key, value) pairs; ValueError when over NOTE_MAX bytes. Returns its path."""
        data = "".join(f"{k}: {v}\n" for k, v in fields)
        if len(data.encode("utf-8")) > NOTE_MAX:
            raise ValueError(f"note is {len(data.encode('utf-8'))} B, the limit is {NOTE_MAX} B: say it shorter")
        inbox = self.path("inbox")
        os.makedirs(inbox, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=inbox, prefix=".tmp-")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(data)
        out = os.path.join(inbox, f"{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}-{os.path.basename(tmp)[5:]}.md")
        os.rename(tmp, out)
        return out
