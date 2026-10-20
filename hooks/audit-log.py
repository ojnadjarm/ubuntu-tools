#!/usr/bin/python3 -SI
"""Agent-agnostic audit core: one JSON line per tool call in $HARNESS_HOME/log/actions.jsonl.

stdin is the generic event {tool, input, cwd, session, agent}; each adapter maps its own agent's event
shape onto that (adapters/<agent>/hooks or adapters/<agent>/audit-from-stream). Schema and
field meanings: KB/audit.md. Always exits 0 — an audit failure never blocks a tool call.
Latency (T669): os, json and re stay unimported unless a string may hold a secret or the log directory is
missing; the rest is python3 start-up."""
import posix, sys, time

# Substrings without which no redaction pattern can match: lower-cased, then case-sensitive.
TRIGGERS = ('token', 'topic', 'pass', 'secret', 'key', 'authorization', 'bearer', 'mysql', 'mariadb', 'curl')
CASED = ('sk-', 'sk_', 'ghp', 'gho', 'ghu', 'ghs', 'github_pat', 'xoxb', 'xoxp', 'AKIA', 'eyJ')
HEX = str.maketrans(dict.fromkeys('0123456789abcdefABCDEF', 'h'))
_RX = None


def may_hold_secret(s):
    """False only when no redaction pattern can match s."""
    if not s.isascii():
        return True
    low = s.lower()
    return (any(t in low for t in TRIGGERS) or any(t in s for t in CASED)
            or ('@' in s and '://' in s) or 'h' * 40 in s.translate(HEX))


def patterns():
    """The compiled redaction patterns (SECRET, URLCRED, KEYLIKE, HEXKEY), compiled on first use."""
    global _RX
    if _RX is None:
        import re
        _RX = (re.compile(
    r'((?:token|topic|passwd|password|(?-i:(?<![A-Za-z])PASS)|secret|(?:secret|private)[\w-]*key|api[-_]?key|apikey'
    r'|authorization|\bx-[\w-]*key)["\']?\s*[:=]\s*|bearer\s+'
    r'|--(?:[\w-]*-)?(?:token|api-key|secret|pass(?:wd|word)?)[= ]|\b(?:mysql\w*|mariadb\w*)\b[^|;&\n]*?\s(?-i:-p)(?=\S)'
    r'|\bsshpass\b[^|;&\n]*?\s(?-i:-p)\s*|\bcurl\b[^|;&\n]*?\s(?:(?-i:-u)\s*|--user[= ])[^\s:"\']+:)'
    r'(["\'])?((?:bearer\s+)?)(?(2)(?:(?!\2)[^\n])+|[^\s"\'&;]+)', re.I),
               re.compile(r'(\b[a-z][\w+.-]*://[^\s:/@"\']+:)[^\s@/"\']+(?=@)', re.I),
               re.compile(r'\b(?:(?:sk|ghp|gho|ghu|ghs|github_pat|xoxb|xoxp)[-_][A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}\b'
                          r'|eyJ[\w-]{10,}\.[\w-]{2,}\.[\w-]*)'),
               re.compile(r'(?<!sha256)([=:]\s*["\']?)[0-9a-fA-F]{40,}\b'))
    return _RX


def loads(s):
    """json.loads of one document through the C scanner, without importing json."""
    import _json

    class Ctx:
        strict, object_hook, object_pairs_hook, parse_float, parse_int = True, None, None, float, int
        parse_constant = {'-Infinity': float('-inf'), 'Infinity': float('inf'), 'NaN': float('nan')}.__getitem__
    return _json.make_scanner(Ctx)(s.strip(), 0)[0]


def dumps(o):
    """json.dumps(o, default=str) through the C encoder, without importing json."""
    import _json
    if isinstance(o, str):
        return _json.encode_basestring_ascii(o)
    return ''.join(_json.make_encoder({}, str, _json.encode_basestring_ascii, None, ': ', ', ',
                                      False, False, True)(o, 0))


def redact(s):
    if not may_hold_secret(s):
        return s
    SECRET, URLCRED, KEYLIKE, HEXKEY = patterns()
    s = SECRET.sub(lambda m: m.group(1) + (m.group(2) or '') + m.group(3) + '<redacted>', s)
    s = URLCRED.sub(lambda m: m.group(1) + '<redacted>', s)
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


def assign_end(seg):
    """End of the leading `VAR=value` assignments of seg: $(...), "...", '...' or a non-blank run."""
    i = end = 0
    n = len(seg)
    while i < n and (seg[i] == '_' or seg[i].isascii() and seg[i].isalpha()):
        j = i + 1
        while j < n and (seg[j].isalnum() or seg[j] == '_'):
            j += 1
        if j == n or seg[j] != '=':
            break
        j += 1
        k = seg.find(')', j + 2) if seg.startswith('$(', j) else -1
        if k < 0 and seg[j:j + 1] in ('"', "'"):
            k = seg.find(seg[j], j + 1)
        if k >= 0:
            j = k + 1
        else:
            while j < n and not seg[j].isspace():
                j += 1
        while j < n and seg[j].isspace():
            j += 1
        i = end = j
    return end


def first_segment(cmd):
    """The first segment of a command line that is not a `cd`/`export`/`VAR=value` prefix."""
    for sep in ('&&', '||', ';', '|'):
        cmd = cmd.replace(sep, '\0')
    segs = [s.strip() for s in cmd.split('\0')]
    segs = [s for s in segs if s]
    for seg in segs:
        rest = seg[assign_end(seg):]
        if rest and basename(rest.split()[0]) not in SETUP_VERBS:
            return rest
    return segs[0] if segs else ''


def basename(p):
    """os.path.basename without importing os."""
    return p[p.rfind('/') + 1:]


def summarise(tool, ti):
    """(op, summary) for one tool call: op is the searchable verb, summary the redacted detail."""
    if tool == 'Bash':
        cmd = redact(str(ti.get('command', '')))
        toks = first_segment(cmd).split()
        op = ' '.join(t for t in (basename(toks[0]) if toks else '',
                                  toks[1] if len(toks) > 1 else '') if t)[:40]
        return op, cmd[:500]
    if tool.startswith('mcp__'):
        return tool, redact(dumps(redact_values(ti)))[:200]
    arg = ''
    for k in ARG_KEYS:
        if ti.get(k):
            arg = redact(str(ti[k]))
            break
    else:
        arg = redact(dumps(ti)) if ti else ''
    short = basename(arg) if arg.startswith(('/', '~', './')) else arg
    return (tool + ' ' + short).strip()[:60], arg[:500]


def clip_error(e, head=100, tail=300):
    """The first head and last tail chars of a long error, joined by a '…' line; the error names itself at the end."""
    return e if len(e) <= head + tail else e[:head] + '\n…\n' + e[-tail:]


def record(tool, tool_input, cwd='', session='', agent='', ok=None, error='', agent_id='', agent_type=''):
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
        if ok is not None:
            rec['ok'] = bool(ok)
        if error:
            rec['error'] = clip_error(redact(str(error)))
        if agent_id:
            rec['agent_id'] = str(agent_id)
        if agent_type:
            rec['agent_type'] = str(agent_type)
        env = posix.environ
        p = (env.get(b'HARNESS_HOME') or env.get(b'HOME', b'') + b'/agents') + b'/log/actions.jsonl'
        flags = posix.O_WRONLY | posix.O_APPEND | posix.O_CREAT
        try:
            fd = posix.open(p, flags, 0o666)
        except FileNotFoundError:
            import os
            os.makedirs(os.path.dirname(p), exist_ok=True)
            fd = posix.open(p, flags, 0o666)
        try:
            posix.write(fd, (dumps(rec) + '\n').encode())
        finally:
            posix.close(fd)
    except Exception:
        pass


def main():
    d = loads(sys.stdin.read())
    record(d.get('tool', '?'), d.get('input') or {}, d.get('cwd', ''), d.get('session', ''),
           d.get('agent', ''))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
