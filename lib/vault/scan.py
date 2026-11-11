"""Find live vault values in files the caller opened and passed by descriptor; answers names and counts, never a value."""
import gzip
import os
import re
import socket
import stat
import zlib

from . import wire

MAX_FDS = 200
CHUNK = 1 << 20
MIN_NEEDLE = 8
KV = re.compile(rb"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
SECRET_KEY = re.compile(rb"PASS|SECRET|TOKEN|KEY", re.I)


def needles(value):
    """The byte strings that mark a leak of one sealed value: the value itself, the secret keys of an env file,
    the secret half of an `<id>:<secret>` pair."""
    if not value:
        return []
    kv = [KV.match(line.strip()) for line in value.splitlines()]
    if any(kv):
        out = [m.group(2).strip().strip(b"\"'") for m in kv if m and SECRET_KEY.search(m.group(1))]
    else:
        v = value.strip()
        out = [v]
        if b":" in v and not re.search(rb"\s|/", v):
            right = v.rsplit(b":", 1)[1]
            out += [right] if len(right) >= 16 else []
    return sorted({n for n in out if len(n) >= MIN_NEEDLE})


def count(f, marks):
    """{index: hits} of each needle in the stream f, read in chunks with an overlap."""
    hits, keep, tail = {}, max(len(n) for n in marks) - 1, b""
    while True:
        chunk = f.read(CHUNK)
        if not chunk:
            return hits
        buf = tail + chunk
        for i, n in enumerate(marks):
            c = buf.count(n) - tail.count(n)
            if c:
                hits[i] = hits.get(i, 0) + c
        tail = buf[-keep:] if keep else b""


class Scanner:
    """The broker's `scan` op: values from the Sealer, files from the caller's descriptors, refused inside an agent."""

    def __init__(self, entries, sealer, audit, callers):
        self.entries, self.sealer, self.audit, self.callers = entries, sealer, audit, callers

    def marks(self):
        """[(secret name, needle)] for every value the broker holds."""
        return [(name, n) for name in sorted(self.entries()) for n in needles(self.sealer.get(name))]

    def serve(self, sock, wfile, req, uid, pid):
        """Answer one scan request on an admin connection: ask for the descriptors, scan, reply with counts."""
        labels = req.get("files")
        if self.callers.agent_unit(pid, uid):
            self.audit.log({"event": "scan", "result": "refused", "uid": uid, "agent": req.get("agent"),
                            "why": "asked from inside an agent"})
            return wire.write_msg(wfile, {"ok": False, "error": "refused: scan runs outside an agent"})
        if not isinstance(labels, list) or not 0 < len(labels) <= MAX_FDS or not all(isinstance(x, str) for x in labels):
            return wire.write_msg(wfile, {"ok": False, "error": f"files: 1 to {MAX_FDS} labels"})
        wire.write_msg(wfile, {"ok": True, "send": len(labels)})
        _msg, fds, _flags, _addr = socket.recv_fds(sock, 16, len(labels))
        try:
            if len(fds) != len(labels):
                return wire.write_msg(wfile, {"ok": False, "error": "descriptor count does not match the labels"})
            reply = self.scan(fds, labels)
        finally:
            for fd in fds:
                os.close(fd)
        self.audit.log({"event": "scan", "result": "hit" if reply["hits"] else "ok", "uid": uid,
                        "agent": req.get("agent"), "target": f"{reply['files']} files"})
        wire.write_msg(wfile, reply)

    def scan(self, fds, labels):
        """Counts per secret and the labels of the files that hold one; unreadable or non-regular files are skipped."""
        marks = self.marks()
        hits, where, files, size, skipped = {}, [], 0, 0, []
        for fd, label in zip(fds, labels):
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode):
                skipped.append(label)
                continue
            try:
                with os.fdopen(os.dup(fd), "rb") as raw:
                    f = gzip.GzipFile(fileobj=raw) if label.endswith(".gz") else raw
                    got = count(f, [n for _, n in marks]) if marks else {}
            except (OSError, EOFError, zlib.error):
                skipped.append(label)
                continue
            files, size = files + 1, size + st.st_size
            per = {}
            for i, c in got.items():
                per[marks[i][0]] = per.get(marks[i][0], 0) + c
            for name, c in per.items():
                hits[name] = hits.get(name, 0) + c
                where.append([label, name, c])
        return {"ok": True, "files": files, "bytes": size, "values": len({m[0] for m in marks}), "hits": hits,
                "where": where, "skipped": skipped}
