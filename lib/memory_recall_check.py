"""`memory check --recall`: the recall network against the control arm (plain word match) on the same cues, as the table
and ship gate of the T1624 plan section 6 (T1624-R3)."""
import math
import os
import re
import time
from collections import namedtuple

import memory_cue
import memory_hint
import memory_net
import memory_recall
import memory_route
import memory_store
from memory_quiz import _tsv

CUES_D = "checks/cues.d"
HARD = ("paraphrase", "spanish", "typo")
TAU, RARE_N, RARE_SHARE, K1, B = 8.0, 2, 0.03, 1.2, 0.75
GATE = {"hit": 0.80, "hard": 0.70, "false": 1 / 30, "wrong": 0.10, "bytes": 300, "ms": 80.0}
Cue = namedtuple("Cue", "key kind id text")


def public_lines(store):
    """{id: (page, place, body)} of every id line on a public card or topic file (ledgers carry none)."""
    out = {}
    for page in store.pages():
        if page.endswith("/ledger.md") or memory_route.seats_of(store, page) is not None:
            continue
        for l in store.lines(page):
            if l.id:
                topic = l.topic and page.endswith(("/CORE.md", "/DOMAIN.md"))
                out[l.id] = (page, f"{os.path.dirname(page)}/{l.topic}.md" if topic else page,
                             memory_store.TOPIC_RX.sub("", memory_store.DATES.sub("", memory_store.ID.sub("", l.raw))))
    return out


def cues(store, lines):
    """The quiz questions whose target id is live on a public page, then checks/cues.d/*.tsv (kind, id, cue; private-* left out)."""
    out = [Cue(r["key"], "quiz", r["id"], r["question"]) for r in _tsv(store.path("checks/questions.tsv"))
           if r.get("id") in lines]
    d = store.path(CUES_D)
    for name in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if name.endswith(".tsv") and not name.startswith("private-"):
            for n, r in enumerate(_tsv(os.path.join(d, name)), 2):
                if r.get("cue") and (r.get("kind") == "quiet" or r.get("id") in lines):
                    out.append(Cue(f"{name[:-4]}:{n}", r["kind"], r.get("id") or "", r["cue"]))
    return out


def network(store, graph=None):
    """The product arm: the public graph (built, else born), no card muted, no session; text -> the first 3 firings."""
    graph = graph or memory_net.load(store) or memory_net.born(store, private=False)[0]
    pages = {p: False for p in store.pages() if memory_route.seats_of(store, p) is None}
    g = memory_recall.scope(graph, pages, set())
    return lambda text: memory_net.fire(g, memory_cue.cues(text, g))[:memory_hint.MAX_HINTS]


def control(lines):
    """The control arm: BM25 over the lines, top 3, fires only at score >= TAU with RARE_N rare words (plan section 3)."""
    words = {i: re.findall(r"[a-z0-9]+", b.lower()) for i, (_, _, b) in lines.items()}
    docs = {i: [w for w in ws if w not in memory_cue.STOP and len(w) > 1] for i, ws in words.items()}
    n, df = len(docs), {}
    for t in docs.values():
        for w in set(t):
            df[w] = df.get(w, 0) + 1
    avg = sum(map(len, docs.values())) / max(n, 1)

    def arm(text):
        q = {w for w in re.findall(r"[a-z0-9]+", text.lower()) if w not in memory_cue.STOP and len(w) > 1}
        out = []
        for i, t in docs.items():
            hit = [w for w in q if w in t]
            sc = sum(math.log(1 + (n - df[w] + .5) / (df[w] + .5)) * t.count(w) * (K1 + 1)
                     / (t.count(w) + K1 * (1 - B + B * len(t) / avg)) for w in hit)
            if sc >= TAU and sum(df[w] <= n * RARE_SHARE for w in hit) >= RARE_N:
                out.append((-sc, i))
        return [memory_net.Firing(i, lines[i][1], round(-s, 3), ()) for s, i in sorted(out)[:memory_hint.MAX_HINTS]]
    return arm


def score(arm, cue_list, lines):
    """{metric: value} for one arm, plus the keys of its red cues (a target missed, or a quiet prompt that fired)."""
    m = {k: 0 for k in ("cues", "fired", "hit", "hard_n", "hard", "quiet", "false")}
    sizes, ms, red = [], [], []
    for c in cue_list:
        t0 = time.perf_counter()
        fired = arm(c.text)
        ms.append((time.perf_counter() - t0) * 1000)
        block = memory_hint.render(fired, {f.id: memory_hint.gist(lines[f.id][2]) for f in fired})
        sizes.append(len(block.encode("utf-8")))
        if c.kind == "quiet":
            m["quiet"] += 1
            m["false"] += bool(fired)
            red += [c.key] if fired else []
            continue
        right = any({lines[f.id][0], lines[f.id][1]} & {lines[c.id][0], lines[c.id][1]} for f in fired)
        target = "hard" if c.kind in HARD else "cues"
        m[target if target == "cues" else "hard_n"] += 1
        m["fired"] += bool(fired) and target == "cues"
        m["hit" if target == "cues" else "hard"] += right
        red += [] if right else [c.key]
    ms.sort()
    m.update(bytes_mean=round(sum(sizes) / max(len(sizes), 1)), bytes_max=max(sizes, default=0),
             ms_p95=round(ms[int(0.95 * (len(ms) - 1))] if ms else 0.0, 2))
    return m, red


def gates(m):
    """{gate: passed} for the network's metrics against GATE."""
    wrong = (m["fired"] - m["hit"]) / m["fired"] if m["fired"] else 0.0
    return {"hit": m["hit"] >= GATE["hit"] * m["cues"], "hard": m["hard"] >= GATE["hard"] * m["hard_n"],
            "false": m["false"] <= GATE["false"] * m["quiet"], "wrong": wrong <= GATE["wrong"],
            "bytes": m["bytes_max"] <= GATE["bytes"], "ms": m["ms_p95"] <= GATE["ms"]}


def table(net, ctl, ok):
    """The section 6 table: metric, control, network, gate, pass."""
    def wrong(m):
        return f"{100 * (m['fired'] - m['hit']) / m['fired']:.0f} %" if m["fired"] else "-"
    rows = [("recall hit", "hit", lambda m: f"{m['hit']}/{m['cues']}", f">= {GATE['hit']:.0%}"),
            ("hard-cue hit", "hard", lambda m: f"{m['hard']}/{m['hard_n']}", f">= {GATE['hard']:.0%}"),
            ("false hints", "false", lambda m: f"{m['false']}/{m['quiet']}", "<= 1/30"),
            ("wrong hints", "wrong", wrong, f"<= {GATE['wrong']:.0%}"),
            ("bytes mean/max", "bytes", lambda m: f"{m['bytes_mean']}/{m['bytes_max']}", f"max {GATE['bytes']}"),
            ("ms p95 in process", "ms", lambda m: f"{m['ms_p95']}", f"<= {GATE['ms']:.0f}")]
    out = ["recall · metric · control · network · gate · pass"]
    out += [f"recall · {name} · {f(ctl)} · {f(net)} · {g} · {'yes' if ok[k] else 'NO'}" for name, k, f, g in rows]
    return out


def run(store, graph=None):
    """(report lines, network gates all met)."""
    lines = public_lines(store)
    cue_list = cues(store, lines)
    net, red = score(network(store, graph), cue_list, lines)
    ctl, _ = score(control(lines), cue_list, lines)
    ok = gates(net)
    out = table(net, ctl, ok) + [f"red · {k}" for k in red]
    out.append(f"recall · ship gate · {'met' if all(ok.values()) else 'NOT met'} · {len(cue_list)} cues")
    return out, all(ok.values())
