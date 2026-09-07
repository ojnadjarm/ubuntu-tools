#!/usr/bin/env bash
# Print, one per line, the repo-relative paths git would track in $HARNESS_HOME.
# Once the owner has run `git init`, this is git's own answer; before that it is the same
# `.gitignore` applied by a dry-run matcher, so the audit below reads the same set either way.
set -uo pipefail
# shellcheck source=/dev/null
[ -r "$HOME/agents/bin/env.sh" ] && . "$HOME/agents/bin/env.sh"
DIR="${1:-$HARNESS_HOME}"

if git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$DIR" ls-files --cached --others --exclude-standard | sort
  exit 0
fi

python3 - "$DIR" <<'PY'
import fnmatch, os, sys

root = sys.argv[1]
pats = []
gi = os.path.join(root, ".gitignore")
if os.path.exists(gi):
    for line in open(gi):
        line = line.strip()
        if line and not line.startswith("#"):
            pats.append(line)


def ignored(rel, isdir):
    """git's semantics for the pattern subset this .gitignore uses."""
    for p in pats:
        neg = p.startswith("!")
        if neg:
            p = p[1:]
        dironly = p.endswith("/")
        p = p.rstrip("/")
        anchored = p.startswith("/") or "/" in p.rstrip("/")
        p = p.lstrip("/")
        if dironly and not isdir:
            continue
        if anchored:
            hit = fnmatch.fnmatch(rel, p)
        else:
            hit = any(fnmatch.fnmatch(seg, p) for seg in rel.split("/"))
        if hit:
            return not neg
    return False


out = []
for dirpath, dirnames, filenames in os.walk(root):
    rel = os.path.relpath(dirpath, root)
    rel = "" if rel == "." else rel
    dirnames[:] = sorted(d for d in dirnames
                         if d != ".git" and not ignored(os.path.join(rel, d).lstrip("/"), True))
    for f in sorted(filenames):
        r = os.path.join(rel, f).lstrip("/")
        if not ignored(r, False):
            out.append(r)
print("\n".join(sorted(out)))
PY
