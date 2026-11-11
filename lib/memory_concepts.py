"""The keeper's night concepts: `net/concepts.d/<domain>.tsv`, one row per memory line (gist, concepts, situations, Spanish aliases) (T1624-R5)."""
import os
from collections import namedtuple

DIR = "net/concepts.d"
COLS = ("id", "gist", "concepts", "when", "es")
HEADER = "\t".join(COLS)
ROW_MAX, GIST_WORDS = 200, 6
PRIVATE_PREFIX = "private-"
Row = namedtuple("Row", "file line raw " + " ".join(COLS))


def files(store, private=False):
    """Store-relative paths of the concepts files, sorted; `private-<d>.tsv` (git-ignored) only when asked."""
    d = store.path(DIR)
    names = sorted(n for n in os.listdir(d) if n.endswith(".tsv")) if os.path.isdir(d) else []
    return [f"{DIR}/{n}" for n in names if private or not n.startswith(PRIVATE_PREFIX)]


def rows(store, rel):
    """(header line, [Row]) of one file; a row with the wrong column count keeps empty fields (the lint flags it)."""
    with open(store.path(rel), encoding="utf-8") as f:
        text = f.read().splitlines()
    out = []
    for n, raw in enumerate(text[1:], 2):
        if raw.strip():
            cols = raw.split("\t")
            out.append(Row(rel, n, raw, *(cols + [""] * len(COLS))[:len(COLS)]))
    return (text[0] if text else ""), out


def read(store, private=False):
    """{id: Row} over every concepts file (later files win on a duplicate id: the lint flags duplicates)."""
    return {r.id: r for rel in files(store, private) for r in rows(store, rel)[1]}


def phrases(row):
    """The row's trigger phrases for the network: gist, concepts, situations and Spanish aliases."""
    return [row.gist] + [p.strip() for col in (row.concepts, row.when, row.es) for p in col.split(",") if p.strip()]
