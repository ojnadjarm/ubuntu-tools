#!/usr/bin/env python3
"""Time every dashboard GET endpoint and page on localhost, sequentially."""
import argparse
import http.client
import os
import statistics
import sys
import time

HOST, PORT, RUNS = "127.0.0.1", 19998, 5
PATHS = [
    "/api/status",
    "/api/voice/prompts",
    "/api/voice/progress",
    "/api/voice/stats",
    "/api/ls",
    "/api/seen",
    "/",
    "/api/agents",
    "/classic",
    "/static/eye.css",
    "/static/machine.html",
]


def get(conn, path, gzip=False):
    """One GET on conn; returns (ms, status, body bytes on the wire)."""
    t = time.perf_counter()
    conn.request("GET", path, headers={"Accept-Encoding": "gzip"} if gzip else {})
    r = conn.getresponse()
    body = r.read()
    return (time.perf_counter() - t) * 1000, r.status, len(body)


def fresh(path, gzip=False):
    """GET on a new connection, connect time included."""
    conn = http.client.HTTPConnection(HOST, PORT, timeout=30)
    try:
        return get(conn, path, gzip)
    finally:
        conn.close()


def stats(ms):
    return "%8.1f %8.1f %8.1f" % (min(ms), statistics.median(ms), max(ms))


def cold(blocks):
    """Compute time of each /api/status block fn, no cache: {name: ms}."""
    out = {}
    for name, row in blocks.items():
        t = time.perf_counter()
        row[0]()
        out[name] = (time.perf_counter() - t) * 1000
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cold", action="store_true", help="time each /api/status block computed without the cache")
    args = ap.parse_args()
    start = time.perf_counter()

    if args.cold:
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        from dash.services.system import BLOCKS
        ms = cold(BLOCKS)
        for name, m in sorted(ms.items(), key=lambda kv: -kv[1]):
            print("cold block %-18s %8.1f ms" % (name, m))
        print("/api/status cold (blocks fill in parallel, slowest bounds it): %.1f ms\n" % max(ms.values()))

    print("%-28s %-5s %26s %26s %9s %9s" % ("path", "code", "keep-alive min/med/max ms", "fresh min/med/max ms", "raw B", "gzip B"))
    for path in PATHS:
        conn = http.client.HTTPConnection(HOST, PORT, timeout=30)
        ka = [get(conn, path) for _ in range(RUNS)]
        conn.close()
        fr = [fresh(path) for _ in range(RUNS)]
        _, _, gz = fresh(path, gzip=True)
        print("%-28s %-5d %26s %26s %9d %9d" % (path, ka[-1][1], stats([r[0] for r in ka]), stats([r[0] for r in fr]), ka[-1][2], gz))

    conn = http.client.HTTPConnection(HOST, PORT, timeout=30)
    seq = [get(conn, "/api/seen")[0] for _ in range(RUNS)]
    conn.close()
    print("\nkeep-alive sequence /api/seen, ms per request: " + " ".join("%.1f" % m for m in seq))
    print("total %.1f s" % (time.perf_counter() - start))


if __name__ == "__main__":
    main()
