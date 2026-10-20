"""Snapshot agent-session-like filler (tool output, briefs, code) into corpus.jsonl."""
import json
import os
import re
from pathlib import Path

HOME = Path.home()
AGENT_WORK = Path(os.environ.get("AGENT_WORK", HOME / "agent-work"))
SOURCES = [
    ("Read", HOME / "agents/KB", "**/*.md"),
    ("Read", AGENT_WORK / "briefs", "*.md"),
    ("Read", AGENT_WORK / "research", "**/*.md"),
    ("Read", HOME / ".claude/skills", "*/SKILL.md"),
    ("Bash", HOME / "agents/bin", "*"),
]
EXCLUDE = ("secrets", "context-rot", "T129", ".env", "config.env", "__pycache__", "FILE-CLAIMS")
SECRET = re.compile(r"sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|xox[bp]-|Bearer\s+[A-Za-z0-9._-]{20,}"
                    r"|(?i:password|passwd|api[_-]?key|token)\s*[:=]\s*['\"]?[A-Za-z0-9_\-]{12,}")
RANDOM_RUN = re.compile(r"[A-Za-z0-9_\-]{32,}")
MAX_BLOCKS_PER_SOURCE = 400
MAX_CHARS = 8000


def _looks_secret(text):
    if SECRET.search(text):
        return True
    return any(re.search(r"\d", m) and re.search(r"[a-z]", m) and re.search(r"[A-Z]", m)
               for m in RANDOM_RUN.findall(text))


def _as_block(kind, path, text):
    shown = str(path).replace(str(HOME), "~")
    head = f"● Read({shown})" if kind == "Read" else f"● Bash(sed -n '1,200p' {shown})"
    body = "\n".join("  ⎿ " + ln if i == 0 else "    " + ln for i, ln in enumerate(text.splitlines()))
    return f"{head}\n{body}\n"


def build(out: Path) -> dict:
    """Write one JSON line per source file that is text, small and has no secret-looking string."""
    n, chars, skipped = 0, 0, 0
    with out.open("w") as fh:
        for kind, root, pattern in SOURCES:
            files = sorted(root.glob(pattern))
            step = max(1, len(files) // MAX_BLOCKS_PER_SOURCE)
            for p in files[::step]:
                if not p.is_file() or any(x in str(p) for x in EXCLUDE):
                    continue
                try:
                    text = p.read_text(encoding="utf-8")
                except (UnicodeDecodeError, OSError):
                    continue
                text = text.strip()[:MAX_CHARS]
                if len(text) < 200 or _looks_secret(text):
                    skipped += 1
                    continue
                block = _as_block(kind, p, text)
                fh.write(json.dumps({"src": str(p), "text": block}) + "\n")
                n, chars = n + 1, chars + len(block)
    return {"blocks": n, "chars": chars, "skipped_secret_or_short": skipped}


def load(path: Path) -> list[str]:
    """Return the corpus blocks in file order."""
    return [json.loads(ln)["text"] for ln in path.open()]
