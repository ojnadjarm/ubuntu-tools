"""The nightly fold as files: hint events and the audit log's opens since the last fold become net/links.tsv
(links touching a PRIVATE memory: net/links.private.tsv, git-ignored), laid on the built graph (T1624)."""
import datetime
import gzip
import json
import os
import re

import memory_learn
import memory_net
import memory_store
from agent_work import agent_work
from memory_recall import session_hash

LINKS, PLINKS = "net/links.tsv", "net/links.private.tsv"
HEAD = "# from\tto\tweight\tlast\tcount · folded through "
FMT = "%Y-%m-%dT%H:%M:%S%z"
SHOW = re.compile(r"\bmemory\s+show\s+\^?([A-Za-z0-9-]+)")


def _time(s):
    try:
        return datetime.datetime.strptime(s, FMT)
    except (TypeError, ValueError):
        return None


def read(store, rel):
    """({(from, to): Link}, folded-through time or None) of a links file."""
    links, cursor = {}, None
    if os.path.isfile(store.path(rel)):
        for line in open(store.path(rel), encoding="utf-8"):
            if line.startswith(HEAD):
                cursor = _time(line[len(HEAD):].strip())
            elif not line.startswith("#") and line.count("\t") == 4:
                a, b, w, last, n = line.rstrip("\n").split("\t")
                links[(a, b)] = memory_learn.Link(float(w), last, int(n))
    return links, cursor


def write(store, rel, links, cursor):
    rows = "".join(f"{a}\t{b}\t{l.weight}\t{l.last}\t{l.count}\n" for (a, b), l in sorted(links.items()))
    memory_store._atomic(store.path(rel), f"{HEAD}{cursor.strftime(FMT)}\n{rows}")


def _graphs(store):
    out = []
    for rel in (memory_net.PUBLIC, memory_net.PRIVATE):
        p = store.path(rel)
        out.append(memory_net.Graph.from_json(open(p, encoding="utf-8").read()) if os.path.isfile(p) else None)
    return out


def lay(store):
    """Lay net/links.tsv and links.private.tsv on the freshly built graph files (once per build)."""
    for rel, graph_rel in ((LINKS, memory_net.PUBLIC), (PLINKS, memory_net.PRIVATE)):
        links, _ = read(store, rel)
        if links and os.path.isfile(store.path(graph_rel)):
            g = memory_net.Graph.from_json(open(store.path(graph_rel), encoding="utf-8").read())
            memory_store._atomic(store.path(graph_rel), memory_learn.lay(g, links).to_json())


def audit_rows(since):
    """Audit log rows after since: the current file and the one rotated before it."""
    path = os.path.join(os.environ.get("HARNESS_HOME") or os.path.expanduser("~/agents"), "log", "actions.jsonl")
    for p, op in ((path + ".1.gz", gzip.open), (path, open)):
        if not os.path.isfile(p):
            continue
        with op(p, "rt", encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                t = _time(d.get("ts"))
                if t and t > since:
                    yield t, d


def events(since, until, places, root):
    """[Hint, Open] after since: hints from the event rows; opens = `memory show <id>` or a Read of a hinted id's page,
    only in sessions that logged a hint (a protected session logs none, so it teaches nothing)."""
    hints, folder = [], os.path.join(agent_work(), "memory-recall", "events")
    for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else ():
        if name[:10] < since.strftime("%Y-%m-%d"):
            continue
        for line in open(os.path.join(folder, name), encoding="utf-8"):
            f = line.rstrip("\n").split("\t")
            t = _time(f[0]) if len(f) == 4 else None
            if t and since < t <= until:
                hints.append(memory_learn.Hint(t, f[1], [c for c in f[2].split(",") if c], [i for i in f[3].split(",") if i]))
    hinted = {}
    for h in hints:
        hinted.setdefault(h.session, set()).update(h.ids)
    opens = []
    for t, d in audit_rows(since):
        s = session_hash(d.get("session"))
        if s not in hinted or t > until:
            continue
        if d.get("tool") == "Bash":
            opens += [memory_learn.Open(t, s, m) for m in SHOW.findall(d.get("summary") or "")]
        elif d.get("tool") == "Read":
            page = os.path.relpath(os.path.realpath(d.get("summary") or "/"), os.path.realpath(root))
            opens += [memory_learn.Open(t, s, m) for m in sorted(hinted[s]) if places.get(m) == page]
    return hints + opens


def run(store, root=None, now=None):
    """Fold the uses since the last fold into the links files and lay them on the built graph; one summary line."""
    pub, priv = _graphs(store)
    if pub is None:
        return "net · learn · skipped · graph not built"
    now = now or datetime.datetime.now().astimezone()
    old, cursor = read(store, LINKS)
    old.update(read(store, PLINKS)[0])
    since = cursor or now - datetime.timedelta(days=1)
    places = {m: v[0] for g in (pub, priv) if g for m, v in g.mem.items()}
    evs = events(since, now, places, root or store.root)
    nights = (now.date() - cursor.date()).days if cursor else 1
    new = memory_learn.fold(old, evs, nights, now.strftime("%Y-%m-%d"))
    private = set(priv.mem) if priv else set()
    live = {k: l for k, l in new.items() if all(n[2:] in places for n in k if n.startswith("m:"))}
    split = lambda p: {k: l for k, l in live.items() if any(n[2:] in private for n in k if n.startswith("m:")) == p}
    for rel, part in ((LINKS, split(False)), (PLINKS, split(True))):
        if part or os.path.isfile(store.path(rel)):
            write(store, rel, part, now)
    lay(store)
    hints = [e for e in evs if isinstance(e, memory_learn.Hint)]
    opened = {(e.session, e.id) for e in evs if isinstance(e, memory_learn.Open)} & {(h.session, m) for h in hints for m in h.ids}
    grown = sum(l.count > old.get(k, memory_learn.Link(0.0, "", 0)).count for k, l in live.items())
    nums = (len(hints), len(opened), grown, len(set(old) - set(live)))
    _log(since, now, nums)
    return "net · learned · {} hints, {} opened, {} links grown, {} faded".format(*nums)


def _folds():
    return os.path.join(agent_work(), "memory-recall", "folds.tsv")


def _log(since, now, nums):
    os.makedirs(os.path.dirname(_folds()), exist_ok=True)
    with open(_folds(), "a", encoding="utf-8") as f:
        f.write("\t".join([since.strftime(FMT), now.strftime(FMT), *map(str, nums)]) + "\n")


def week(now=None, days=7):
    """The Sunday digest line: the folds of the last `days` days summed (a re-fold from the same cursor counts once)."""
    now = now or datetime.datetime.now().astimezone()
    rows = {}
    if os.path.isfile(_folds()):
        for line in open(_folds(), encoding="utf-8"):
            f = line.rstrip("\n").split("\t")
            until = _time(f[1]) if len(f) == 6 else None
            if until and now - datetime.timedelta(days=days) < until <= now:
                rows[f[0]] = [int(n) for n in f[2:]]
    h, o, g, x = (sum(c) for c in zip(*rows.values())) if rows else (0, 0, 0, 0)
    return f"recall: {h} hints, {o} opened, {g} links grown, {x} faded ({days} days)"
