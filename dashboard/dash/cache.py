"""TTL memo for slow reads, and stale-while-revalidate for the /api/status blocks."""
import threading, time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

TTL = 30

_cache = {}
lock = threading.Lock()


def cached(key, ttl, fn, empty=None):
    """Return fn() memoised for ttl seconds; on error keep the last good value and record {at, error}."""
    with lock:
        hit = _cache.get(key)
        if hit and time.time() - hit["tried"] < ttl:
            return hit["val"]
    try:
        val, err = fn(), None
    except Exception as e:
        val, err = (hit["val"] if hit else ({} if empty is None else empty)), str(e)
    with lock:
        _cache[key] = {"at": time.time() if err is None else (hit["at"] if hit else 0),
                       "tried": time.time(), "val": val, "error": err}
    return val


def forget(*keys):
    """Drop cached values so the next read recomputes them."""
    with lock:
        for k in keys:
            _cache.pop(k, None)


_refreshing = set()


def swr(blocks):
    """Serve cached blocks at once; expired ones refresh in one background thread, missing ones are computed in parallel."""
    now = time.time()
    with lock:
        missing = [k for k in blocks if k not in _cache]
        expired = [k for k in blocks if k in _cache and now - _cache[k]["tried"] >= TTL and k not in _refreshing]
        _refreshing.update(expired)

    def fill(keys):
        with ThreadPoolExecutor(len(keys)) as pool:
            list(pool.map(lambda k: cached(k, 0, *blocks[k]), keys))

    def refresh():
        try:
            fill(expired)
        finally:
            with lock:
                _refreshing.difference_update(expired)

    if expired:
        threading.Thread(target=refresh, daemon=True).start()
    if missing:
        fill(missing)
    with lock:
        return {k: _cache[k]["val"] for k in blocks}


def cache_meta(keys):
    """stale: blocks whose last good read is older than 2×TTL (and when); errors: last message per failing block."""
    now = time.time()
    with lock:
        c = {k: _cache.get(k) for k in keys}
    stale = [k for k, h in c.items() if h and h["at"] and now - h["at"] >= 2 * TTL and not (k in _refreshing and h["error"] is None)]
    errors = {k: h["error"] for k, h in c.items() if h and h["error"]}
    since = min(c[k]["at"] for k in stale) if stale else None
    return stale, errors, datetime.fromtimestamp(since).astimezone().isoformat(timespec="seconds") if since else None
