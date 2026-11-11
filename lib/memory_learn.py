"""Learning from use: fold hint events and opens into learned link weights (Hebb, habituation, decay), lay them on a graph (T1624)."""
from collections import namedtuple

ETA, IGNORE, DECAY, W_MIN, CUT, LEARN_W = 0.6, 0.25, 0.98, 0.05, 0.5, 1.0
Link = namedtuple("Link", "weight last count")
Hint = namedtuple("Hint", "time session cues ids")
Open = namedtuple("Open", "time session id")


def _put(out, key, rule, day, opened):
    old = out.get(key, Link(0.0, day, 0))
    out[key] = Link(round(rule(old.weight), 4), day, old.count + opened)


def fold(links, events, nights=1, day=""):
    """{(from, to): Link} after events and `nights` of decay; a weight w is in (-1, 1), |w| under W_MIN drops the row.

    An opened hint strengthens its cue links (w += ETA (1 - w)), an ignored one weakens them (w -= ETA/4 (1 + w)): five
    ignores in a row take a born link's gain 1 + w under CUT. Memories opened in one session link both ways.
    """
    out = dict(links)
    opens = {}
    for e in events:
        if isinstance(e, Open):
            opens.setdefault(e.session, []).append(e)
    for e in sorted((e for e in events if isinstance(e, Hint)), key=lambda e: e.time):
        for m in e.ids:
            hit = any(o.id == m and o.time >= e.time for o in opens.get(e.session, ()))
            rule = (lambda w: w + ETA * (1 - w)) if hit else (lambda w: w - ETA * IGNORE * (1 + w))
            for c in e.cues:
                _put(out, (c, "m:" + m), rule, day, int(hit))
    for got in opens.values():
        ids = sorted({o.id for o in got})
        for a in ids:
            for b in ids:
                if a != b:
                    _put(out, ("m:" + a, "m:" + b), lambda w: w + ETA * (1 - w), day, 1)
    k = DECAY ** nights
    return {key: l._replace(weight=round(l.weight * k, 4)) for key, l in out.items() if abs(l.weight * k) >= W_MIN}


def lay(graph, links):
    """The graph with learned weights: a born link times its gain 1 + w (cut under CUT), a learned-only link LEARN_W * w."""
    for (a, b), l in links.items():
        row = graph.links.setdefault(a, {})
        born = row.get(b)
        w = LEARN_W * l.weight if born is None else (born * (1 + l.weight) if 1 + l.weight >= CUT else 0.0)
        if w >= W_MIN:
            row[b] = round(w, 3)
        else:
            row.pop(b, None)
        if not row:
            del graph.links[a]
    return graph
