#!/usr/bin/env python3
"""Append-only writer for the notes vault: raw, apply, index."""
import datetime
import json
import os
import re
import sys
import tempfile
import time

import jsonschema

HERE = os.path.dirname(os.path.realpath(__file__))
MAX_FILES_PER_HOUR = 20
INDEX_MAX_FILES = 300
INDEX_MAX_CHARS = 40_000


class Refused(Exception):
    pass


def vault():
    return os.path.realpath(os.path.expanduser(os.environ.get("NOTES_VAULT_DIR", "~/obsidian-vault")))


def folder():
    return os.environ.get("NOTES_FOLDER", "audio notes")


def home():
    return os.environ.get("NOTES_HOME", HERE)


def log(verb, status, detail=""):
    os.makedirs(os.path.join(home(), "logs"), exist_ok=True)
    with open(os.path.join(home(), "logs", "notes-file.log"), "a") as f:
        f.write(f"{datetime.datetime.now().isoformat(timespec='seconds')} {verb} {status} {detail}\n")


def jail(rel):
    if not os.path.isdir(vault()):
        raise Refused(f"no vault at {vault()}")
    parts = rel.split("/")
    if not rel.endswith(".md") or not parts[-1][:-3] or os.path.isabs(rel) or ".." in parts or "\\" in rel:
        raise Refused(f"bad path {rel}")
    full = os.path.join(vault(), rel)
    if not os.path.realpath(full).startswith(vault() + os.sep):
        raise Refused(f"path escapes vault {rel}")
    return full


def read(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".notes-file-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def insert_under(content, heading, lines, level=2):
    """Insert lines at the end of the heading's section; add the heading at the end if absent."""
    if content and not content.endswith("\n"):
        content += "\n"
    if heading is None:
        body = "\n".join(lines)
        return content.rstrip("\n") + "\n" + body + "\n" if content else body.lstrip("\n") + "\n"
    rows = content.split("\n")
    pat = re.compile(rf"^#{{{level}}}\s+{re.escape(heading)}\s*$")
    start = next((i for i, r in enumerate(rows) if pat.match(r)), None)
    if start is None:
        return content.rstrip("\n") + f"\n\n{'#' * level} {heading}\n" + "\n".join(lines) + "\n"
    end = next((i for i in range(start + 1, len(rows)) if re.match(rf"^#{{1,{level}}}\s", rows[i])), len(rows))
    while end > start + 1 and rows[end - 1] == "":
        end -= 1
    rows[end:end] = lines
    return "\n".join(rows)


def split_front_matter(text):
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end != -1:
            return text[4:end], text[end + 5:]
    return None, text


def parse_tags(fm):
    if not fm:
        return []
    m = re.search(r"^tags:[ \t]*\[(.*)\][ \t]*$", fm, re.M)
    if m:
        return [t.strip().strip("'\"") for t in m.group(1).split(",") if t.strip()]
    m = re.search(r"^tags:[ \t]*$((?:\n[ \t]*-[ \t]*.+)*)", fm, re.M)
    if m:
        return [re.sub(r"^[ \t]*-[ \t]*", "", r).strip().strip("'\"") for r in m.group(1).split("\n") if r.strip()]
    return []


def with_tags(text, tags):
    """Front matter tags gain the missing entries; nothing is removed."""
    fm, body = split_front_matter(text)
    new = [t for t in tags if t not in parse_tags(fm)]
    if not new:
        return text
    if fm is None:
        return f"---\ntags: [{', '.join(new)}]\n---\n" + text
    m = re.search(r"^tags:[ \t]*\[(.*)\][ \t]*$", fm, re.M)
    if m:
        inner = m.group(1).strip()
        joined = ", ".join(([inner] if inner else []) + new)
        fm = fm[:m.start(1)] + joined + fm[m.end(1):]
    elif re.search(r"^tags:[ \t]*$", fm, re.M):
        m = re.search(r"^tags:[ \t]*$((?:\n[ \t]*-[ \t]*.+)*)", fm, re.M)
        fm = fm[:m.end()] + "".join(f"\n  - {t}" for t in new) + fm[m.end():]
    else:
        fm = fm + f"\ntags: [{', '.join(new)}]"
    return f"---\n{fm}\n---\n{body}"


def daily_rel(day):
    return f"{folder()}/{day}.md"


def daily_skeleton(day):
    return f"# {day}\n\n## Raw\n\n## Refined\n"


def now():
    return datetime.datetime.now()


def cmd_raw(text):
    at = now()
    day = at.strftime("%Y-%m-%d")
    path = jail(daily_rel(day))
    content = read(path) or daily_skeleton(day)
    line = f"- {at.strftime('%H:%M')} — {text}"
    write(path, insert_under(content, "Raw", [line]))
    log("raw", "ok", daily_rel(day))
    print(line)
    return 0


def clean_heading(h):
    """A heading without its markdown marks; empty after stripping is refused."""
    if h is None:
        return None
    h = h.lstrip("#").strip()
    if not h:
        raise Refused("empty heading")
    return h


def title_from(rel):
    return os.path.basename(rel)[:-3].replace("-", " ").capitalize()


def plan_changes(plan):
    """Compute every new file content in memory; nothing is written here."""
    changes = {}

    def current(rel):
        path = jail(rel)
        return path, (changes[path] if path in changes else read(path))

    for a in plan["actions"]:
        path, old = current(a["file"])
        if a["op"] == "create" and old is None:
            new = f"---\ntags: [{', '.join(a.get('tags', []))}]\n---\n# {a.get('title') or title_from(a['file'])}\n\n{a['text']}\n"
        else:
            new = insert_under(old or "", clean_heading(a.get("heading")), [""] + a["text"].splitlines())
            new = with_tags(new, a.get("tags", []))
        changes[path] = new

    unsure = {(a["file"], a.get("heading")) for a in plan["actions"] if a.get("sure") is False}
    day = now().strftime("%Y-%m-%d")
    for r in plan.get("refined", []):
        jail(r["file"])
        heading = clean_heading(r.get("heading"))
        link = r["file"][:-3] + (f"#{heading}" if heading else "")
        line = f"- {r.get('at') or now().strftime('%H:%M')} → [[{link}]] {r['gist']}"
        if r.get("sure") is False or (r["file"], r.get("heading")) in unsure:
            line += " (?)"
        path, old = current(daily_rel(day))
        changes[path] = insert_under(old or daily_skeleton(day), "Refined", [line])
    return changes


def touched_within_hour():
    ledger = os.path.join(home(), "state", "touched.json")
    try:
        with open(ledger) as f:
            rows = json.load(f)
    except (OSError, ValueError):
        rows = []
    return ledger, [r for r in rows if r[0] > time.time() - 3600]


def cmd_apply(plan_path):
    try:
        with (sys.stdin if plan_path == "-" else open(plan_path)) as f:
            plan = json.load(f)
    except (OSError, ValueError) as e:
        raise Refused(f"unreadable plan: {e}")
    with open(os.path.join(HERE, "plan.schema.json")) as f:
        schema = json.load(f)
    try:
        jsonschema.validate(plan, schema)
    except jsonschema.ValidationError as e:
        raise Refused(f"schema: {e.message}")
    changes = plan_changes(plan)
    ledger, rows = touched_within_hour()
    if len(rows) + len(changes) > MAX_FILES_PER_HOUR:
        raise Refused(f"{len(rows) + len(changes)} files inside an hour, cap {MAX_FILES_PER_HOUR}")
    for path, new in changes.items():
        before = os.path.getsize(path) if os.path.exists(path) else 0
        if len(new.encode("utf-8")) < before:
            raise Refused(f"would shrink {os.path.relpath(path, vault())}")
    for path, new in changes.items():
        write(path, new)
    os.makedirs(os.path.dirname(ledger), exist_ok=True)
    rows += [[time.time(), os.path.relpath(p, vault())] for p in changes]
    with open(ledger, "w") as f:
        json.dump(rows, f)
    log("apply", "ok", " ".join(os.path.relpath(p, vault()) for p in changes))
    return 0


def index_entry(path):
    fm, body = split_front_matter(read(path))
    rows = body.splitlines()
    title = next((r[2:].strip() for r in rows if r.startswith("# ")), None)
    return {
        "title": title or title_from(path),
        "tags": parse_tags(fm),
        "headings": [re.sub(r"^#+\s+", "", r) for r in rows if re.match(r"^##+\s", r)],
        "excerpt": " ".join(" ".join(r for r in rows if not r.startswith("#")).split())[:200],
    }


def cmd_index():
    daily = re.compile(r"^\d{4}-\d{2}-\d{2}\.md$")
    cache_path = os.path.join(home(), "state", "index.json")
    try:
        with open(cache_path) as f:
            cache = json.load(f)
    except (OSError, ValueError):
        cache = {}
    entries = []
    for root, dirs, files in os.walk(vault()):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for name in sorted(files):
            rel = os.path.relpath(os.path.join(root, name), vault())
            if not name.endswith(".md") or (rel == f"{folder()}/{name}" and daily.match(name)):
                continue
            st = os.stat(os.path.join(root, name))
            hit = cache.get(rel)
            if not hit or hit["mtime"] != st.st_mtime or hit["size"] != st.st_size:
                hit = {"mtime": st.st_mtime, "size": st.st_size, **index_entry(os.path.join(root, name))}
            entries.append((rel, hit))
    cache = dict(entries)
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    with open(cache_path, "w") as f:
        json.dump(cache, f)
    entries.sort(key=lambda e: e[1]["mtime"], reverse=True)
    full = min(len(entries), INDEX_MAX_FILES)
    while True:
        lines = [json.dumps({"file": rel, **({k: e[k] for k in ("title", "tags", "headings", "excerpt")} if i < full else {"title": e["title"]})}, ensure_ascii=False)
                 for i, (rel, e) in enumerate(entries)]
        if sum(len(l) + 1 for l in lines) <= INDEX_MAX_CHARS or full == 0:
            break
        full -= 1
    print("\n".join(lines))
    log("index", "ok", f"{len(entries)} files, {full} full")
    return 0


def main(argv):
    verb = argv[0] if argv else ""
    try:
        if verb == "raw" and len(argv) == 2:
            return cmd_raw(argv[1])
        if verb == "apply" and len(argv) == 2:
            return cmd_apply(argv[1])
        if verb == "index" and len(argv) == 1:
            return cmd_index()
    except Refused as e:
        log(verb, "refused", str(e))
        print(f"refused: {e}", file=sys.stderr)
        return 1
    print("usage: notes-file.py raw <text> | apply <plan.json|-> | index", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
