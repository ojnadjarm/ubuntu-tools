#!/usr/bin/python3 -SI
"""Agent-agnostic audit core: one JSON line per tool call in $HARNESS_HOME/log/actions.jsonl.

stdin is the generic event {tool, input, cwd, session, agent}; each adapter maps its own agent's event
shape onto that (adapters/<agent>/hooks or adapters/<agent>/audit-from-stream). Schema and
field meanings: KB/audit.md. Always exits 0 — an audit failure never blocks a tool call.
Latency (T669): os, json and re stay unimported unless a string may hold a secret or the log directory is
missing; the rest is python3 start-up."""
import posix, sys, time

from _frozen_importlib_external import SourceFileLoader  # importlib.machinery's loader, without importing importlib


def _lib(name):
    """The module lib/<name>.py beside this hooks folder, through its bytecode cache."""
    m = type(sys)(name)
    here = _lib.__code__.co_filename.rpartition('/')[0] or '.'  # __file__ is unset when an adapter loads this core
    SourceFileLoader(name, here + '/../lib/' + name + '.py').exec_module(m)
    return m


_redact = _lib('redact')
redact, redact_values = _redact.redact, _redact.redact_values


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
