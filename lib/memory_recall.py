"""`memory recall`: cut the network to what the session may read, fire it on a prompt, render the hints, keep the session's
residual and shown ids, log an ids-only event (T1624)."""
import hashlib
import json
import os
import tempfile
import time
from collections import namedtuple

import memory_cue
import memory_hint
import memory_net
import memory_route
import memory_store
from agent_work import _key, agent_work

Context = namedtuple("Context", "cwd seat worker session")
SESSION_MAX, SHOWN_MAX = 4096, 200
Result = namedtuple("Result", "block firings cues private")


def off():
    """The kill switch: MEMORY_RECALL=off in the environment or in config.env."""
    return _key("MEMORY_RECALL").lower() in ("off", "0", "no", "false")


def session_hash(session):
    return hashlib.sha256(session.encode()).hexdigest()[:12] if session else "-"


def session_file(session):
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir(), "memory-recall",
                        session_hash(session) + ".json")


def read_session(session):
    try:
        with open(session_file(session), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_session(session, state):
    """Write the session state (at most SESSION_MAX bytes: the oldest shown ids go first)."""
    state["shown"] = state.get("shown", [])[-SHOWN_MAX:]
    data = json.dumps(state, separators=(",", ":"))
    while len(data) > SESSION_MAX and state["shown"]:
        state["shown"] = state["shown"][1:]
        data = json.dumps(state, separators=(",", ":"))
    path = session_file(session)
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    memory_store._atomic(path, data)


def protected(store, ctx):
    """True when a routed domain is flagged `protected` in domains.map."""
    doms = set(memory_route.domains_for(ctx.cwd, ctx.seat, os.environ, store))
    return any(d in doms and "protected" in fl for _, d, fl in store.map())


def loaded(store, ctx, pages):
    """Ids on the cards the session starts with (core and its routed domains): they conduct but never hint (D4)."""
    out = set()
    for d in ["core"] + memory_route.domains_for(ctx.cwd, ctx.seat, os.environ, store):
        if store.card(d) in pages:
            out |= {l.id for l in store.lines(store.card(d)) if l.id}
    return out


def scope(graph, pages, mute):
    """The graph cut to memories on pages: the rest neither fire nor conduct; mute ids conduct but never fire."""
    mem = {m: [p, b, float("inf") if m in mute else t] for m, (p, b, t) in graph.mem.items() if p in pages}
    keep = {"m:" + m for m in mem}
    links = {}
    for n, row in graph.links.items():
        if n.startswith("m:") and n not in keep:
            continue
        r = {k: w for k, w in row.items() if k.startswith("c:") or k in keep}
        if n.startswith("m:") or any(k.startswith("m:") for k in r):
            links[n] = r
    links = {n: {k: w for k, w in r.items() if k in links or k in keep} for n, r in links.items()}
    places = {p: [m for m in ms if m in mem] for p, ms in graph.places.items() if p in pages}
    return memory_net.Graph(mem, links, places, [r for r in graph.rivals if set(r) <= mem.keys()])


def body(store, mid, place):
    """The text of memory mid's line (ids, dates, topic off): on its place, else on that folder's card."""
    card = "core/CORE.md" if place.startswith("core/") else os.path.dirname(place) + "/DOMAIN.md"
    for page in (place, card):
        if os.path.isfile(store.path(page)):
            for l in store.lines(page):
                if l.id == mid:
                    return memory_store.TOPIC_RX.sub("", memory_store.DATES.sub("", memory_store.ID.sub("", l.raw)))
    return ""


def public_cues(graph, cues, pages):
    """The cue ids that name a word on a public page: an event never carries a word only a PRIVATE page holds."""
    return [c for c, _ in cues if any(k.startswith("m:") and not pages[graph.mem[k[2:]][0]] for k in graph.links[c])]


def log_event(session, cues, ids):
    """One row in $AGENT_WORK/memory-recall/events/<date>.tsv: time, session hash, cue ids, hinted ids. No prompt text."""
    path = os.path.join(agent_work(), "memory-recall", "events", time.strftime("%Y-%m-%d") + ".tsv")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S%z')}\t{session_hash(session)}\t{','.join(cues)}\t{','.join(ids)}\n")


def recall(store, text, ctx, write=True):
    """Result(block, firings, cues, PRIVATE ids) for one prompt; write=False is a dry run (no session file, no event row)."""
    if off():
        return Result("", [], [], set())
    pages = memory_route.pages_for(ctx.cwd, ctx.seat, os.environ, ctx.worker, store)
    private = any(pages.values())
    graph = memory_net.load(store, private=private)
    if graph is None:
        pub, priv = memory_net.born(store, private=private)
        graph = memory_net.merge(pub, priv) if private else pub
    state = read_session(ctx.session) if ctx.session else {}
    g = scope(graph, pages, loaded(store, ctx, pages) | set(state.get("shown", [])))
    cues = memory_cue.cues(text, g)
    fired = memory_net.fire(g, cues, state)[:memory_hint.MAX_HINTS]
    gists = {f.id: memory_hint.gist(body(store, f.id, f.place)) for f in fired if not pages[f.place]}
    if write:
        if ctx.session:
            state["shown"] = state.get("shown", []) + [f.id for f in fired]
            save_session(ctx.session, state)
        if fired and not protected(store, ctx):
            log_event(ctx.session, public_cues(g, cues, pages), [f.id for f in fired])
    return Result(memory_hint.render(fired, gists), fired, cues, {f.id for f in fired if f.id not in gists})
