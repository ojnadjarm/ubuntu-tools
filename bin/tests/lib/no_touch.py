#!/usr/bin/env python3
"""no_touch.py <strace -f -y log> <path>...: print every syscall that opens, lists, stats or runs in a protected path,
or reaches a container runtime; exit 1 on any. Allowed: the protected matcher's own `readlink -m` of its config entry, a
read of the /proc cwd link, and a cwd in the path only as the AT_FDCWD annotation of a call on an absolute path."""
import re
import sys

LINE = re.compile(r"^(\d+) +(\w+)\((.*)$")
RUNTIME = re.compile(r'execve\("[^"]*/(docker|podman|nerdctl|ctr)"|docker\.sock|containerd\.sock|podman\.sock')
CWD_LINK = re.compile(r'^"/proc/(self|\d+)/cwd"')
ABS_AT_CWD = re.compile(r'AT_FDCWD<[^>]*>(?=, "/)')
LOOKUP = {"execve", "stat", "lstat", "newfstatat", "statx", "readlink", "readlinkat"}


def main(log, paths):
    rows = [m.groups() for m in map(LINE.match, open(log, errors="replace")) if m]
    matcher = {pid for pid, call, rest in rows if call == "execve" and re.match(r'"[^"]*/readlink", \["readlink", "-m"', rest)}
    bad = []
    for pid, call, rest in rows:
        text = f"{pid} {call}({rest}"
        if call in ("readlink", "readlinkat") and CWD_LINK.match(rest):
            continue
        rest = ABS_AT_CWD.sub("AT_FDCWD", rest)
        if RUNTIME.search(text):
            bad.append(text)
        elif any(re.search(re.escape(p) + r'(?![\w.-])', rest) for p in paths):
            if not (pid in matcher and call in LOOKUP):
                bad.append(text)
    for b in bad:
        print(b[:300])
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2:]))
