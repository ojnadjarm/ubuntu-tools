"""`memory recall`: cut the network to what the session may read, fire it on a prompt, render the hints, keep the session's
residual and shown ids, log an ids-only event (T1624)."""
import hashlib
import json
import os
import re
import tempfile
import time
from collections import namedtuple

import memory_cue
import memory_hint
import memory_net
import memory_route
import memory_store
from agent_work import _key, agent_work

Context = namedtuple("Context", "cwd seat worker session recent", defaults=(None,))
SESSION_MAX, SHOWN_MAX = 4096, 200
RECENT_N, TAIL = 5, 1 << 20
# Text the harness wrote into the prompt slot (task notifications, hand-backs), not him (T1838).
HARNESS = re.compile(r"\A\s*(<[a-z-]+[ >]|Another Claude session sent a message:)")
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


def scope(graph, pages, mute, near=None):
    """The graph cut to memories on pages: the rest neither fire nor conduct; mute ids conduct but never fire; with near
    (page prefixes), a memory off them fires only at THETA_FAR."""
    mem = {m: [p, b, float("inf") if m in mute else t if near is None or p.startswith(near) else max(t, memory_net.THETA_FAR)]
           for m, (p, b, t) in graph.mem.items() if p in pages}
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


def owner_prompts(transcript, n=RECENT_N):
    """The last n prompts he typed in a Claude Code transcript (no meta rows, tool results, harness text), oldest first."""
    with open(transcript, "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - TAIL))
        rows = f.read().decode("utf-8", "replace").splitlines()
    out = []
    for row in rows:
        if '"user"' not in row:
            continue
        try:
            r = json.loads(row)
            c = r["message"]["content"]
        except (ValueError, KeyError, TypeError):
            continue
        if r.get("type") != "user" or r.get("isMeta") or not isinstance(c, (str, list)):
            continue
        if isinstance(c, list):
            if any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c):
                continue
            c = " ".join(x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text")
        if c.strip() and not HARNESS.match(c):
            out.append(c)
    return out[-n:]


def supported(graph, firings, recent, cues=()):
    """The firings whose memory has a word of the recent prompts besides this prompt's cues; all when none was read."""
    if not recent:
        return firings
    words = {"c:" + w for w in memory_cue.tokens(" ".join(recent))
             if not any(memory_cue.variant(w, c[2:]) for c, _ in cues)}
    return [f for f in firings if any("m:" + f.id in graph.links.get(w, ()) for w in words)]


def recall(store, text, ctx, write=True):
    """Result(block, firings, cues, PRIVATE ids) for one prompt; write=False is a dry run (no session file, no event row).

    ctx.recent: his previous prompts of the session; when given, a hint needs one of its words in them.
    """
    if off() or HARNESS.match(text):
        return Result("", [], [], set())
    pages = memory_route.pages_for(ctx.cwd, ctx.seat, os.environ, ctx.worker, store)
    private = any(pages.values())
    graph = memory_net.load(store, private=private)
    if graph is None:
        pub, priv = memory_net.born(store, private=private)
        graph = memory_net.merge(pub, priv) if private else pub
    state = read_session(ctx.session) if ctx.session else {}
    near = tuple(f"domains/{d}/" for d in memory_route.domains_for(ctx.cwd, ctx.seat, os.environ, store))
    g = scope(graph, pages, loaded(store, ctx, pages) | set(state.get("shown", [])), near)
    cues = memory_cue.cues(text, g)
    fired = supported(g, memory_net.fire(g, cues, state), ctx.recent, cues)[:memory_hint.MAX_HINTS]
    gists = {f.id: graph.gists.get(f.id) or memory_hint.gist(body(store, f.id, f.place)) for f in fired if not pages[f.place]}
    if write:
        if ctx.session:
            state["shown"] = state.get("shown", []) + [f.id for f in fired]
            save_session(ctx.session, state)
        if fired and not protected(store, ctx):
            log_event(ctx.session, public_cues(g, cues, pages), [f.id for f in fired])
    return Result(memory_hint.render(fired, gists), fired, cues, {f.id for f in fired if f.id not in gists})
