"""Build a seeded session-like haystack of a target size and plant facts at spread depths.

Adapted from chroma-core/context-rot niah_extension/create_haystacks.py (MIT): sequential haystack build and
needle insertion snapped to a boundary; extended to 8 needles as in RULER niah_multikey.
"""
import random

SYSTEM = "You are an orchestrator agent. You read session transcripts carefully and answer only from them."


def build_filler(blocks: list[str], target_chars: int, rng: random.Random) -> list[str]:
    """Return shuffled corpus blocks whose total length is just under target_chars (no block repeats first)."""
    order = blocks[:]
    rng.shuffle(order)
    out, size, i = [], 0, 0
    while size < target_chars:
        b = order[i % len(order)]
        if size + len(b) > target_chars:
            out.append(b[: target_chars - size])
            break
        out.append(b)
        size, i = size + len(b), i + 1
    return out


def slot_depths(n: int, rng: random.Random) -> list[float]:
    """Return n depths spread evenly over (0, 1) with a small seeded jitter."""
    return [min(0.97, max(0.03, (i + 0.5) / n + rng.uniform(-0.03, 0.03))) for i in range(n)]


def _placements(facts, depths, rng):
    """Return (depth, text, fact key or None) for every fact and, in hard mode, its distractors."""
    items = [(d, f.text, f.key) for f, d in zip(facts, depths)]
    for f, d in zip(facts, depths):
        for where, text in f.distractors:
            items.append((rng.uniform(0.01, max(0.015, d - 0.05)) if where == "before" else rng.uniform(0.02, 0.98),
                          text, None))
    return sorted(items, key=lambda it: it[0])


def _bury(block: str, texts: list[str]) -> str:
    """Put the texts, in order, as lines in the middle of a tool-output block."""
    lines = block.split("\n")
    mid = max(1, len(lines) // 2)
    return "\n".join(lines[:mid] + [f"    {t}" for t in texts] + lines[mid:])


def plant(filler: list[str], facts, depths: list[float], rng: random.Random, hard: bool = False):
    """Insert facts (user turns, or lines buried in tool output when hard) near their depths; return text, depths."""
    total = sum(len(b) for b in filler)
    bounds, acc = [], 0
    for b in filler:
        bounds.append(acc)
        acc += len(b)
    at = {}
    for d, text, key in _placements(facts, depths, rng):
        idx = min(range(len(bounds)), key=lambda k: abs(bounds[k] - d * total))
        at.setdefault(idx, []).append((text, key))
    parts, real = [], {}
    for k, b in enumerate(filler):
        here = at.get(k, [])
        for text, key in here:
            if key:
                real[key] = bounds[k] / total
            if not hard:
                parts.append(f"\n> user: {text}\n\n")
        parts.append(_bury(b, [text for text, _ in here]) if hard and here else b)
    return "".join(parts), [real[f.key] for f in facts]


# variant: (text before the questions, reply instruction prefix); control is the T129 prompt
VARIANTS = {
    "control": ("", "Reply with one JSON object and nothing else"),
    "rest": ("Pause. You are rested and focused; reread the material calmly before answering.\n\n",
             "Reply with one JSON object and nothing else"),
    "quote": ("", "First copy, verbatim inside <quotes></quotes>, every sentence of the session that holds an answer "
                  "(for a changed value, the latest statement). After </quotes>, reply with one JSON object"),
    "pad": ("\n" * 1000, "Reply with one JSON object and nothing else"),
    "checkpoint": ("", "Pause for a moment. Briefly restate, in your own words with short quotes, the facts you will need. "
                       "Then continue and answer with one JSON object"),
}


def prompt(session: str, facts, join_q: str, variant: str = "control") -> str:
    """Return the user message: the session, the variant's preamble, all 9 questions and the answer format."""
    pre, reply = VARIANTS[variant]
    qs = "\n".join(f"q{i + 1}. {f.question}" for i, f in enumerate(facts))
    keys = ", ".join(f'"q{i + 1}": "..."' for i in range(len(facts)))
    return (f"<session>\n{session}\n</session>\n\n{pre}Several facts were stated during the session above. "
            f"Answer from the session only; where a value changed, give the latest one.\n{qs}\njoin. {join_q}\n\n"
            f'{reply}: {{{keys}, "join": "..."}}. Use null when not found.')
