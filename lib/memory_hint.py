"""The hint block: at most 3 fired memories as `~ ^id place · gist · why` lines under one header, at most 300 B (T1624)."""
import re

HEADER = "memory stirs (hints, not orders; open: memory show <id>)"
MAX_HINTS, LINE_MAX, BLOCK_MAX, GIST_WORDS, WHY_MAX = 3, 80, 300, 6, 3


def place(page):
    """A page path as its short place: core, core/<topic>, <domain> or <domain>/<topic>."""
    parts = re.sub(r"\.md$", "", page).split("/")
    parts = [p for p in (parts[1:] if parts[0] == "domains" else parts) if p not in ("CORE", "DOMAIN")]
    return "/".join(parts) or "core"


def gist(body):
    """The first GIST_WORDS words of a line body, list dash and end punctuation off."""
    return " ".join(re.sub(r"^\s*[-*]\s+", "", body).split()[:GIST_WORDS]).rstrip(".,;:")


def why(path):
    """At most WHY_MAX path labels, this prompt's before primed ones (`~`); `a>b` is one hop."""
    labels = sorted(path, key=lambda l: (l.startswith("~"), l))[:WHY_MAX]
    return " + ".join(l.replace(">", " > ") for l in labels)


def _fit(head, words, tail, limit):
    """head + gist + tail within limit bytes: gist words dropped from the end first, then a hard byte cut."""
    while True:
        s = head + " · ".join(x for x in (" ".join(words), tail) if x)
        if len(s.encode()) <= limit or not words:
            return s.encode()[:limit].decode(errors="ignore")
        words = words[:-1]


def render(firings, gists):
    """The block for the first MAX_HINTS firings, "" when none; a firing without a gist (PRIVATE) shows id and place only."""
    lines = [HEADER]
    for f in firings[:MAX_HINTS]:
        head = f"~ ^{f.id} {place(f.place)}"
        lines.append(_fit(head + " · ", gists[f.id].split(), why(f.path), LINE_MAX) if f.id in gists else head[:LINE_MAX])
    return "\n".join(lines) + "\n" if len(lines) > 1 else ""
