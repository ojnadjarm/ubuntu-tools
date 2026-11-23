#!/usr/bin/env python3
"""count.py [--header] <transcript.jsonl> [label]: one table row of repeated work around compactions (T1840).

Logic from the T1839 measure scripts: file keys and view verbs (measure2), tool-output tokens from context deltas and
re-orientation patterns (measure3), requests deduplicated by requestId, last usage wins (measure).
"""
import json, os, re, sys

COLS = ["arm", "calls", "compactions", "calls after compaction", "back on earlier files", "re-orientation",
        "input tokens", "output tokens", "tool-output tokens", "ram notes", "digests"]
VIEW = {'cat', 'head', 'tail', 'sed', 'grep', 'rg', 'wc', 'jq', 'less', 'awk', 'nl', 'cut', 'egrep', 'ls', 'find',
        'stat', 'file', 'diff', 'md5sum', 'sha256sum'}
PATH = re.compile(r'(?<![\w$])(~?/?[\w.@+-]+(?:/[\w.@+*-]+)+|[\w-]+\.(?:py|md|json|js|ts|tsx|sh|php|txt|yaml|yml|html|css|toml|gd|tscn|log|jsonl|cpp|h))\b')
REORIENT = re.compile(r'briefs/T\d+|\bTASK\.md|\bQUESTIONS\.md|\bguide \w|memory load|agent-verify|git (status|diff|log)|\bclaims ')
NOTE_LINE = re.compile(r'\b(fact|tried|decided|next|done) · ')
MATCH_LINE = re.compile(r'^([\w./@+-]+\.\w+):\d+[:-]', re.M)    # grep -n output: path:line:


def rows(p):
    for line in open(p, errors='replace'):
        try:
            yield json.loads(line)
        except ValueError:
            pass


def fkey(p, cwd=''):
    if cwd and p.startswith(cwd.rstrip('/') + '/'):
        p = p[len(cwd.rstrip('/')) + 1:]
    return '/'.join(p.rstrip('/').split('/')[-2:])


def segs(cmd):
    return [s.strip() for s in re.split(r'\|\||&&|[;|\n]', cmd) if s.strip()]


def view_keys(name, inp, cwd=''):
    """File keys a call looks at, or None when it is not a view."""
    if name == 'Read':
        return {fkey(inp.get('file_path') or '', cwd)}
    if name == 'Grep' and inp.get('path'):
        return {fkey(inp['path'], cwd)}
    if name != 'Bash':
        return None
    keys, view = set(), False
    for s in segs(inp.get('command') or ''):
        w = s.split()
        while w and (w[0] in ('cd', 'export', 'sudo', 'timeout', 'nice', 'env', 'time') or '=' in w[0]):
            w = [] if w[0] in ('cd', 'export') else w[2:] if w[0] == 'timeout' else w[1:]
        if not w:
            continue
        v = os.path.basename(w[0])
        if v in VIEW and not (v == 'sed' and '-i' in w) and '>' not in s:
            view = True
            keys |= {fkey(x, cwd) for x in PATH.findall(' '.join(w[1:]))}
    return keys if view else None


def count(p):
    calls = []                  # (name, input, epoch, cwd, id)
    out = {}                    # tool_use id -> result text
    reqs = {}                   # requestId -> [ctx, out, epoch, has_tools]
    order = []
    epoch = digests = 0
    for r in rows(p):
        t = r.get('type')
        if t == 'system' and r.get('subtype') == 'compact_boundary':
            epoch += 1
            continue
        if t == 'attachment':
            a = r.get('attachment') or {}
            if a.get('hookEvent') and NOTE_LINE.search(json.dumps(a.get('content'), ensure_ascii=False)):
                digests += 1
            continue
        if t == 'user':
            for b in (r.get('message') or {}).get('content') or []:
                if isinstance(b, dict) and b.get('type') == 'tool_result':
                    c = b.get('content')
                    out[b.get('tool_use_id')] = c if isinstance(c, str) else ' '.join(
                        x.get('text', '') for x in c or [] if isinstance(x, dict))
            continue
        if t != 'assistant':
            continue
        m = r.get('message') or {}
        rid = r.get('requestId') or m.get('id')
        if rid not in reqs:
            reqs[rid] = [0, 0, epoch, False]
            order.append(rid)
        u = m.get('usage') or {}
        if u:
            reqs[rid][0] = sum(u.get(k) or 0 for k in ('input_tokens', 'cache_read_input_tokens',
                                                       'cache_creation_input_tokens'))
            reqs[rid][1] = u.get('output_tokens') or 0
        for b in m.get('content') or []:
            if isinstance(b, dict) and b.get('type') == 'tool_use':
                calls.append((b.get('name'), b.get('input') or {}, epoch, r.get('cwd') or '', b.get('id')))
                reqs[rid][3] = True
    seen = {}                   # file key -> first epoch
    post = back = reorient = notes = 0
    for name, inp, ep, cwd, cid in calls:
        text = inp.get('command') or inp.get('file_path') or ''
        if name == 'Bash' and re.search(r'\bram note\b', text):
            notes += 1
        keys = view_keys(name, inp, cwd)
        if ep > 0:
            post += 1
            if name in ('Bash', 'Read') and REORIENT.search(text):
                reorient += 1
            if keys and any(seen.get(k, ep) < ep for k in keys):
                back += 1
        edited = name in ('Edit', 'Write') and inp.get('file_path')
        touched = keys or ({fkey(inp['file_path'], cwd)} if edited else set())
        if keys is not None:    # files a view showed as match lines were seen too
            touched = touched | {fkey(m, cwd) for m in MATCH_LINE.findall(out.get(cid) or '')}
        for k in touched:
            seen.setdefault(k, ep)
    st = [reqs[r] for r in order]
    tool_out = sum(max(0, b[0] - a[0] - a[1]) for a, b in zip(st, st[1:]) if a[2] == b[2] and a[3] and a[0] and b[0])
    return [len(calls), epoch, post, back, reorient, sum(s[0] for s in st), sum(s[1] for s in st), tool_out,
            notes, digests]


def line(cells):
    return '| ' + ' | '.join(str(c) for c in cells) + ' |'


if __name__ == '__main__':
    args = sys.argv[1:]
    header = '--header' in args
    args = [a for a in args if a != '--header']
    if not args:
        sys.exit(__doc__.splitlines()[0])
    if header:
        print(line(COLS))
        print(line(['---'] * len(COLS)))
    label = args[1] if len(args) > 1 else os.path.basename(args[0]).split('.')[0]
    print(line([label] + count(args[0])))
