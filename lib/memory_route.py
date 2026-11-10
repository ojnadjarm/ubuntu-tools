"""Which domains a folder or seat gets, and which source a note's seat earns, from the store's domains.map (T1599)."""
import os
import re


def domains_for(cwd, seat, env, store):
    """Domains for an agent: MEMORY_DOMAINS, then the seat's `seat:` lines, then the deepest folder line holding cwd."""
    out = re.split(r"[\s,]+", env.get("MEMORY_DOMAINS", "").strip())
    rows = store.map()
    out += [d for w, d, _ in rows if seat and w == "seat:" + seat]
    cwd = os.path.normpath(cwd)
    held = [(len(f), d) for w, d, _ in rows if not w.startswith("seat:")
            for f in [os.path.normpath(os.path.expanduser(w))] if cwd == f or cwd.startswith(f + "/")]
    if held:
        deepest = max(n for n, _ in held)
        out += [d for n, d in held if n == deepest]
    return list(dict.fromkeys(d for d in out if d and d != "core"))


def source_for(seat, quoted, store):
    """The source a note earns: `owner` for a quote from a seat flagged `owner`, `untrusted` for any other quote, else `agent`."""
    if not quoted:
        return "agent"
    owner = any(w == "seat:" + seat and "owner" in fl for w, _, fl in store.map()) if seat else False
    return "owner" if owner else "untrusted"
