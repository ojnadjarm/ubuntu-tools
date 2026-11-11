"""JSON-line framing over a Unix socket: read, write, the peer's credentials and one client call."""
import json
import socket
import struct

MAX_LINE = 1 << 20


def read_msg(rfile):
    """Read one JSON object terminated by a newline; ValueError on a bad or oversized line."""
    line = rfile.readline(MAX_LINE + 1)
    if not line or len(line) > MAX_LINE or not line.endswith(b"\n"):
        raise ValueError("bad request line")
    msg = json.loads(line)
    if not isinstance(msg, dict):
        raise ValueError("request is not an object")
    return msg


def write_msg(wfile, obj):
    """Write one JSON object and a newline, then flush."""
    wfile.write(json.dumps(obj, separators=(",", ":")).encode() + b"\n")
    wfile.flush()


def peer(sock):
    """The connected peer's (pid, uid, gid) from SO_PEERCRED."""
    raw = sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    return struct.unpack("3i", raw)


def call(path, req, timeout=30):
    """Send one request to the socket at path and return the reply object."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect(path)
        with s.makefile("rwb") as f:
            write_msg(f, req)
            return read_msg(f)
