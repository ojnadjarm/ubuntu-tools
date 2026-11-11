"""The recall network for eyes: `export` (the public graph, PRIVATE pages by name only) and `trial` (one dry recall as the
owner's own session sees it) for `memory net export --json` and the dashboard's Network tab (T1624)."""
import os

import memory_fold
import memory_hint
import memory_net
import memory_recall
import memory_route


def private_pages(store):
    """Pages a PRIVATE line (their own or their card's) keeps from anyone but their seats."""
    return sorted(p for p in store.pages() if memory_route.seats_of(store, p) is not None)


def public(store):
    """(mem, links, fan, hidden pages, built): the public graph (built, else compiled in memory; never the private file) with
    every memory on a PRIVATE page cut out, and every concept left with no memory."""
    g = memory_net.load(store)
    built = g is not None
    g = g or memory_net.born(store, private=False)[0]
    hidden = set(private_pages(store))
    mem = {m: v for m, v in g.mem.items() if v[0] not in hidden}
    keep = {"m:" + m for m in mem}
    links = [[a, b, w] for a, row in g.links.items() for b, w in row.items()
             if not (a.startswith("m:") and a not in keep) and not (b.startswith("m:") and b not in keep)]
    fan = {}
    for a, b, _ in links:
        if a.startswith("c:") and b.startswith("m:"):
            fan[a] = fan.get(a, 0) + 1
    links = [l for l in links if all(n in keep or n in fan for n in l[:2])]
    return memory_net.Graph(mem, {}, g.places, [r for r in g.rivals if set(r) <= mem.keys()]), links, fan, hidden, built


def fresh(store, keep):
    """Learned links the last fold touched (their day is the fold's day) whose memories are all in keep."""
    links, cursor = memory_fold.read(store, memory_fold.LINKS)
    day = cursor and cursor.strftime("%Y-%m-%d")
    return [[a, b] for (a, b), l in sorted(links.items())
            if day and l.last == day and all(n.startswith("c:") or n[2:] in keep for n in (a, b))]


def export(store):
    """{built, memories [id, place, base, theta], places, concepts [word, fan], links [from, to, w], rivals, fresh, stats}."""
    g, links, fan, hidden, built = public(store)
    places = [{"place": p, "domain": memory_hint.place(p).split("/")[0], "n": sum(m in g.mem for m in ms)}
              for p, ms in sorted(g.places.items()) if p not in hidden]
    places += [{"place": p, "domain": memory_hint.place(p).split("/")[0], "private": True} for p in sorted(hidden)]
    return {"v": 1, "built": built, "memories": [[m, p, b, t] for m, (p, b, t) in sorted(g.mem.items())],
            "places": places, "concepts": sorted([c[2:], n] for c, n in fan.items()), "links": links,
            "rivals": g.rivals, "fresh": fresh(store, g.mem.keys()),
            "stats": {"memories": len(g.mem), "concepts": len(fan), "links": len(links), "places": len(places) - len(hidden),
                      "private places": len(hidden), "rivals": len(g.rivals)}}


def owner_seat(store):
    """The seat domains.map flags `owner` ("" when none)."""
    return next((w[5:] for w, _, fl in store.map() if w.startswith("seat:") and "owner" in fl), "")


def trial(store, text, home=None):
    """`memory recall --json` for text as the owner's own session in ~ (not a worker, no session, nothing written);
    cues limited to words a public page holds, a PRIVATE hint is id and place only."""
    if memory_recall.off():
        return {"off": True, "block": "", "cues": [], "hints": []}
    ctx = memory_recall.Context(home or os.path.expanduser("~"), owner_seat(store), False, None)
    r = memory_recall.recall(store, text, ctx, write=False)
    fan = public(store)[2]
    return {"off": False, "block": r.block, "cues": [c for c, _ in r.cues if c in fan], "hints": [
        {"id": f.id, "place": f.place, "activation": f.activation, "why": None if f.id in r.private else list(f.path)}
        for f in r.firings]}
