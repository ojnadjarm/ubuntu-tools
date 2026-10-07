#!/usr/bin/env python3
"""Agent-agnostic audit core: one JSON line per tool call in $HARNESS_HOME/log/actions.jsonl.

stdin is the generic event {tool, input, cwd, session, agent}; each adapter maps its own agent's event
shape onto that (adapters/<agent>/hooks or adapters/<agent>/audit-from-stream). Schema and
field meanings: KB/audit.md. Always exits 0 — an audit failure never blocks a tool call.
Latency budget is a soft target: ~18-20 ms per call, dominated by python3 start-up."""
import json, os, re, sys, time

SECRET = re.compile(
    r'((?:token|passwd|password|secret|api[-_]?key|apikey|authorization|\bx-[\w-]*key)'
    r'["\']?\s*[:=]\s*["\']?(?:bearer\s+)?|bearer\s+|--password[= ]|\b(?:mysql\w*|mariadb\w*)\b[^|;&\n]*?\s(?-i:-p)(?=\S)'
    r'|\bsshpass\b[^|;&\n]*?\s(?-i:-p)\s*|\bcurl\b[^|;&\n]*?\s(?:(?-i:-u)\s*|--user[= ])[^\s:"\']+:)'
    r'([^\s"\'&;]+)', re.I)
KEYLIKE = re.compile(r'\b(?:sk|ghp|gho|ghu|ghs|github_pat|xoxb|xoxp)[-_][A-Za-z0-9_-]{16,}')
HEXKEY = re.compile(r'(?<!sha256)([=:]\s*["\']?)[0-9a-fA-F]{40,}\b')


def redact(s):
    s = SECRET.sub(lambda m: m.group(1) + '<redacted>', s)
    s = HEXKEY.sub(lambda m: m.group(1) + '<redacted>', s)
    return KEYLIKE.sub('<redacted>', s)


def redact_values(v):
    """Redact every string inside a nested dict/list before it is JSON-escaped."""
    if isinstance(v, str):
        return redact(v)
    if isinstance(v, dict):
        return {k: redact_values(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [redact_values(x) for x in v]
    return v


ARG_KEYS = ('pattern', 'query', 'url', 'file_path', 'notebook_path', 'path',
            'description', 'prompt', 'command')


SETUP_VERBS = ('cd', 'export', 'set', 'source', 'eval', '.')
SEGMENT = re.compile(r'&&|\|\||;|\|')
ASSIGN = re.compile(r'^(?:[A-Za-z_]\w*=(?:\$\([^)]*\)|"[^"]*"|\'[^\']*\'|\S*)\s*)+')


def first_segment(cmd):
    """The first segment of a command line that is not a `cd`/`export`/`VAR=value` prefix."""
    segs = [s.strip() for s in SEGMENT.split(cmd)]
    segs = [s for s in segs if s]
    for seg in segs:
        rest = ASSIGN.sub('', seg)
        if rest and os.path.basename(rest.split()[0]) not in SETUP_VERBS:
            return rest
    return segs[0] if segs else ''


def summarise(tool, ti):
    """(op, summary) for one tool call: op is the searchable verb, summary the redacted detail."""
    if tool == 'Bash':
        cmd = redact(str(ti.get('command', '')))
        toks = first_segment(cmd).split()
        op = ' '.join(t for t in (os.path.basename(toks[0]) if toks else '',
                                  toks[1] if len(toks) > 1 else '') if t)[:40]
        return op, cmd[:500]
    if tool.startswith('mcp__'):
        return tool, redact(json.dumps(redact_values(ti), default=str))[:200]
    arg = ''
    for k in ARG_KEYS:
        if ti.get(k):
            arg = redact(str(ti[k]))
            break
    else:
        arg = redact(json.dumps(ti, default=str)) if ti else ''
    short = os.path.basename(arg) if arg.startswith(('/', '~', './')) else arg
    return (tool + ' ' + short).strip()[:60], arg[:500]


def record(tool, tool_input, cwd='', session='', agent=''):
    """Append one audit line; agent: rostered name, 'bench', or '' (interactive). Never raises."""
    try:
        op, summary = summarise(tool, tool_input or {})
        rec = {
            'ts': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
            'session': (session or '')[:8],
            'agent': agent or '',
            'cwd': cwd or '',
            'tool': tool,
            'op': op,
            'summary': summary,
        }
        p = os.path.join(os.environ.get('HARNESS_HOME') or os.path.expanduser('~/agents'),
                         'log', 'actions.jsonl')
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'a') as f:
            f.write(json.dumps(rec) + '\n')
    except Exception:
        pass


def main():
    d = json.load(sys.stdin)
    record(d.get('tool', '?'), d.get('input') or {}, d.get('cwd', ''), d.get('session', ''),
           d.get('agent', ''))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
