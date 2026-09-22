"""Route registry: service modules register handlers with @route, the HTTP handler looks them up."""
EXACT, PREFIX = {}, []


def route(method, path, prefix=False):
    """Register fn(handler, path) for method + path, or for every path under path when prefix is set."""
    def reg(fn):
        if prefix:
            PREFIX.append((method, path, fn))
        else:
            EXACT[(method, path)] = fn
        return fn
    return reg


def find(method, path):
    """The handler for a request, exact paths first, then prefixes in registration order; None when nothing matches."""
    return EXACT.get((method, path)) or next((fn for m, p, fn in PREFIX if m == method and path.startswith(p)), None)
