"""Per-project owner-decision ledgers: which project a text names, where its ledger lives, a short digest (T396, stdlib only)."""
import os
import re

from agent_work import agent_work

PROJECTS = {
    "fleet": re.compile(r"\bfleet\b|\bubuntu-tools\b|~/agents/(?:bin|lib|KB|adapters)/", re.I),
    "ailearning": re.compile(r"\bai[- ]?learning\b|\blessons?\b|\bsheets? \d+\b|\bU\d\d\b", re.I),
    "portfolio": re.compile(r"\bportfolio\b", re.I),
    "vass": re.compile(r"\bvass\b", re.I),
}
DIGEST_CHARS = 1200


def ref(name):
    """The path fragment a brief must contain to count as naming the project's ledger."""
    return "KB/DECISIONS.md" if name == "fleet" else f"decisions/{name}.md"


def path(name):
    """Absolute path of the project's ledger."""
    if name == "fleet":
        return os.path.expanduser("~/agents/KB/DECISIONS.md")
    return os.path.join(agent_work(), "decisions", f"{name}.md")


def named(text):
    """Projects the text names, in PROJECTS order."""
    return [n for n, rx in PROJECTS.items() if rx.search(text or "")]


def unreferenced(text):
    """Projects the text names without naming their ledger."""
    return [n for n in named(text) if ref(n) not in text]


def digest(name, limit=DIGEST_CHARS):
    """The ledger's decision lines without their quotes, cut to `limit` chars with a pointer to the rest; "" when there is none."""
    try:
        with open(path(name), encoding="utf-8") as f:
            rows = [l.rstrip() for l in f if l.startswith("- ")]
    except OSError:
        return ""
    if not rows:
        return ""
    head = f"Owner decisions for {name} (standing; never re-break them):"
    lines = [re.sub(r' · (?:"[^"]*"|\([^)]*\))(?: / "[^"]*")*$', "", r) for r in rows]
    out, left = [head], len(lines)
    for l in lines:
        tail = f"(+{left} more in {path(name)})"
        if sum(len(x) + 1 for x in out) + len(l) + 1 + len(tail) > limit:
            break
        out.append(l)
        left -= 1
    if left:
        out.append(f"(+{left} more in {path(name)})")
    return "\n".join(out)
