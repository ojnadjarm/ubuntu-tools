"""The recall network N1 Constellation: a concept and memory graph born from the store, and the dynamic that fires it (T1624)."""
import datetime
import json
import math
import os
import re
from collections import namedtuple

import memory_concepts
import memory_route
import memory_store
from memory_cue import tokens

SPREAD, STEPS, PRIME, PLACE_W, CC_W = 0.6, 2, 0.5, 0.5, 0.0
BASE_W, DEFAULT_AGE, THETA, MIN_PATHS, S_ASSOC, W_MIN = 0.1, 365, 0.5, 2, 6.5, 0.05
FAN_SHARE, FAN_FLOOR = 0.05, 8
RESIDUAL_N, RESIDUAL_MIN = 10, 0.05
NET, PUBLIC, PRIVATE = "net", "net/graph.json", "net/graph.private.json"
IGNORED = ("graph.json", "graph.private.json", "links.private.tsv", "concepts.d/private-*.tsv")
RIVAL = re.compile(r"\^([A-Za-z0-9-]+)\s*(?:→|->)\s*\^([A-Za-z0-9-]+)")
Firing = namedtuple("Firing", "id place activation path")


class Graph:
    """mem: id -> [place, base level, threshold]; links: node -> {node: weight} ("c:" concept, "m:" memory); places; rivals; keeper gists."""

    def __init__(self, mem=None, links=None, places=None, rivals=None, gists=None):
        self.mem, self.links = mem or {}, links or {}
        self.places, self.rivals, self.gists = places or {}, rivals or [], gists or {}

    def fan(self, node):
        return sum(n.startswith("m:") for n in self.links.get(node, ()))

    def to_json(self):
        return json.dumps({"v": 1, "mem": self.mem, "links": self.links, "places": self.places, "rivals": self.rivals,
                           "gists": self.gists},
                          separators=(",", ":"), sort_keys=True)

    @classmethod
    def from_json(cls, text):
        d = json.loads(text)
        return cls(d["mem"], d["links"], d["places"], d["rivals"], d.get("gists"))


def merge(a, b):
    """One graph holding both: the owner's session merges the public and the private part."""
    links = {k: dict(v) for k, v in a.links.items()}
    for k, v in b.links.items():
        links.setdefault(k, {}).update(v)
    places = {k: list(v) for k, v in a.places.items()}
    for k, v in b.places.items():
        places.setdefault(k, []).extend(v)
    return Graph({**a.mem, **b.mem}, links, places, a.rivals + b.rivals, {**a.gists, **b.gists})


def base_level(dates, today):
    """ACT-R base level B = ln(sum of age_days^-0.5) over the owner's (yy-mm-dd) dates, scaled by BASE_W."""
    ages = []
    for d in dates:
        try:
            ages.append(max(1, (today - datetime.date(2000 + int(d[:2]), int(d[3:5]), int(d[6:8]))).days))
        except ValueError:
            pass
    return BASE_W * math.log(sum(a ** -0.5 for a in ages or [DEFAULT_AGE]))


def _memories(store, concepts, private):
    """([(id, place, words, dates, keeper words, is private)], rival id pairs) from cards, topic files and ledgers."""
    out, rivals = [], []
    for page in store.pages():
        priv = memory_route.seats_of(store, page) is not None
        if priv and not private:
            continue
        if page.endswith("/ledger.md"):
            rivals += RIVAL.findall(store.text(page))
            continue
        for l in store.lines(page):
            if not l.id:
                continue
            body = memory_store.TOPIC_RX.sub("", memory_store.DATES.sub("", memory_store.ID.sub("", l.raw)))
            topic = l.topic and page.endswith(("/CORE.md", "/DOMAIN.md"))
            kw = [w for c in concepts.get(l.id, ()) for w in tokens(c)]
            out.append((l.id, f"{os.path.dirname(page)}/{l.topic}.md" if topic else page,
                        set(tokens(body)) | set(kw), l.dates, kw, priv))
    return out, rivals


def _links(nodes, keep):
    """Concept -> memory links S - ln(fan) over nodes (fan effect), only towards ids in keep; concept <-> concept from keeper words."""
    fan = {}
    for mid, _, words, *_ in nodes:
        for w in words:
            fan.setdefault(w, []).append(mid)
    cap = max(FAN_FLOOR, FAN_SHARE * len(nodes))
    links = {"c:" + w: {"m:" + m: round(max(W_MIN, S_ASSOC - math.log(len(ms))), 3) for m in ms if m in keep}
             for w, ms in fan.items() if len(ms) <= cap}
    for mid, _, _, _, kw, _ in nodes:
        kw = [w for w in dict.fromkeys(kw) if "c:" + w in links]
        for a in kw if mid in keep and CC_W else ():
            for b in kw:
                if a != b:
                    row = links["c:" + a]
                    row["c:" + b] = round(row.get("c:" + b, 0.0) + CC_W / (len(kw) - 1), 3)
    return {k: v for k, v in links.items() if v}


def _part(nodes, keep, rivals, today, gists):
    mem = {m: [p, round(base_level(d, today), 3), THETA] for m, p, _, d, _, _ in nodes if m in keep}
    places = {}
    for m, (p, _, _) in mem.items():
        places.setdefault(p, []).append(m)
    return Graph(mem, _links(nodes, keep), places, [list(r) for r in rivals if keep & set(r)],
                 {m: g for m, g in gists.items() if m in keep})


def born(store, concepts=None, today=None, private=True):
    """(public graph, private graph) of the store; the public part never depends on a PRIVATE page.

    concepts: {id: [phrases]}; None reads the keeper's net/concepts.d (its private files only when private).
    """
    gists = {}
    if concepts is None:
        rows = memory_concepts.read(store, private)
        concepts = {i: memory_concepts.phrases(r) for i, r in rows.items()}
        gists = {i: r.gist for i, r in rows.items() if r.gist}
    nodes, rivals = _memories(store, concepts, private)
    today = today or datetime.date.today()
    pub = [n for n in nodes if not n[5]]
    pub_ids, priv_ids = {n[0] for n in pub}, {n[0] for n in nodes if n[5]}
    every = pub_ids | priv_ids
    rivals = [r for r in rivals if set(r) <= every]
    return (_part(pub, pub_ids, [r for r in rivals if set(r) <= pub_ids], today, gists),
            _part(nodes, priv_ids, [r for r in rivals if not set(r) <= pub_ids], today, gists))


def build(store, concepts=None, today=None):
    """Write net/graph.json and net/graph.private.json under the store (both ignored by net/.gitignore); returns the pair."""
    pub, priv = born(store, concepts, today)
    ign = store.path(f"{NET}/.gitignore")
    have = open(ign, encoding="utf-8").read().split() if os.path.isfile(ign) else []
    if not set(IGNORED) <= set(have):
        memory_store._atomic(ign, "".join(f"{n}\n" for n in dict.fromkeys(have + list(IGNORED))))
    memory_store._atomic(store.path(PUBLIC), pub.to_json())
    memory_store._atomic(store.path(PRIVATE), priv.to_json())
    return pub, priv


def load(store, private=False):
    """The built graph (public; merged with the private part only when asked), None when not built."""
    if not os.path.isfile(store.path(PUBLIC)):
        return None
    with open(store.path(PUBLIC), encoding="utf-8") as f:
        g = Graph.from_json(f.read())
    if private and os.path.isfile(store.path(PRIVATE)):
        with open(store.path(PRIVATE), encoding="utf-8") as f:
            g = merge(g, Graph.from_json(f.read()))
    return g


def _origins(labels):
    """The cue concepts behind the path labels; a firing needs MIN_PATHS of them, one from this prompt (no `~`)."""
    return {l.split(">")[0].lstrip("~") for l in labels} if any(not l.startswith("~") for l in labels) else set()


def _groups(rivals):
    """Rival sets: id -> the set's smallest id (union of the rival pairs)."""
    root = {}

    def find(x):
        while root.setdefault(x, x) != x:
            x = root[x]
        return x
    for a, b in rivals:
        ra, rb = find(a), find(b)
        root[max(ra, rb)] = min(ra, rb)
    return {x: find(x) for x in root}


def fire(graph, cues, session=None):
    """[Firing] above threshold with at least MIN_PATHS cue paths, one per place and rival set, strongest first.

    session: a dict whose "residual" (concepts and memories still lit) primes this prompt and is rewritten by it.
    """
    frontier, paths = {}, {}
    for c, w in cues:
        frontier[c] = frontier.get(c, 0.0) + w
        paths.setdefault(c, set()).add(c[2:])
    for n, a in (session or {}).get("residual", {}).items():
        if n in graph.links or n[2:] in graph.mem:
            frontier[n] = frontier.get(n, 0.0) + PRIME * a
            if n.startswith("c:"):
                paths.setdefault(n, set()).add("~" + n[2:])
    act = dict(frontier)
    for _ in range(STEPS):
        nxt = {}
        for m, a in frontier.items():
            for n, w in graph.links.get(m, {}).items():
                nxt[n] = nxt.get(n, 0.0) + SPREAD * a * w
                hop = m.startswith("c:") and n.startswith("c:")
                paths.setdefault(n, set()).update(l.split(">")[0] + ">" + n[2:] if hop else l for l in paths.get(m, ()))
            if m.startswith("m:") and m[2:] in graph.mem:
                mates = graph.places.get(graph.mem[m[2:]][0], [])
                for x in mates:
                    if x != m[2:]:
                        nxt["m:" + x] = nxt.get("m:" + x, 0.0) + SPREAD * a * PLACE_W / (len(mates) - 1)
        for n, v in nxt.items():
            act[n] = act.get(n, 0.0) + v
        frontier = nxt
    if session is not None:
        lit = sorted(((v, n) for n, v in act.items() if v >= RESIDUAL_MIN), reverse=True)
        session["residual"] = {n: round(v, 4) for kind in ("c:", "m:")
                               for v, n in [x for x in lit if x[1].startswith(kind)][:RESIDUAL_N]}
    total = {n[2:]: v + graph.mem[n[2:]][1] for n, v in act.items() if n.startswith("m:") and n[2:] in graph.mem}
    group, seen, out = _groups(graph.rivals), set(), []
    for m, v in sorted(total.items(), key=lambda x: (-x[1], x[0])):
        place = graph.mem[m][0]
        if v < graph.mem[m][2] or len(_origins(paths.get("m:" + m, ()))) < MIN_PATHS:
            continue
        keys = {("p", place), ("r", group.get(m, m))}
        if not keys & seen:
            out.append(Firing(m, place, round(v, 3), tuple(sorted(paths["m:" + m]))))
            seen |= keys
    return out


def stats(graph):
    """Counts of nodes and links by kind."""
    kinds = {"c:c": 0, "c:m": 0, "m:m": 0}
    for k, row in graph.links.items():
        for n in row:
            kinds.setdefault(k[:1] + ":" + n[:1], 0)
            kinds[k[:1] + ":" + n[:1]] += 1
    return {"concepts": sum(k.startswith("c:") for k in graph.links), "memories": len(graph.mem),
            "places": len(graph.places), "concept-memory": kinds["c:m"], "concept-concept": kinds["c:c"],
            "memory-memory": kinds["m:m"], "same-place": sum(len(v) * (len(v) - 1) for v in graph.places.values()),
            "rivals": len(graph.rivals)}
