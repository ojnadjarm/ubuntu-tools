#!/usr/bin/env python3
"""External commands and Python modules called by the scripts in bin dirs or files, checked against DEPS.tsv.

usage: deps_scan.py <bindir|file>... [--deps DEPS.tsv]
Names in every scanned dir are local (never external).
Without --deps: one `tool<TAB>files` line per external tool found. With --deps: `MISSING <tool> <package> <files>`
for every tool that is neither in DEPS.tsv nor from a BASE package; exit 1 when any.
"""
import os
import re
import shutil
import subprocess
import sys
from importlib.util import find_spec

# Packages every Ubuntu install has: their commands need no DEPS.tsv row.
BASE = {'bash', 'dash', 'coreutils', 'rust-coreutils', 'gnu-coreutils', 'grep', 'sed', 'mawk', 'findutils', 'gzip',
        'tar', 'util-linux', 'bsdutils', 'procps', 'libc-bin', 'perl-base', 'debianutils', 'dpkg', 'apt', 'hostname',
        'diffutils', 'mount', 'systemd'}
SEARCH = os.environ.get('PATH', '') + ':/usr/local/sbin:/usr/sbin:/sbin'

SEP = re.compile(r'\$\(|`|&&|\|\||[|;\n]|(?<!\$)\{|(?<![=\w$])\(|\b(?:then|do|else|elif|if|while|until|!)\s')
PREFIX = {'sudo', 'timeout', 'flock', 'nice', 'ionice', 'stdbuf', 'setsid', 'nohup', 'env', 'exec', 'command', 'time',
          'xargs', 'pc_cmd', 'pc_timeout', 'run_traced', '$PC_TIMEOUT_BIN'}
ARG = re.compile(r'^(?:-\S*|\d+(?:\.\d+)?[smh]?)$')
WORD = re.compile(r'^[A-Za-z][\w.+-]*$')
PYCALL = [
    re.compile(r'(?<![\w\])\]])\[\s*["\'](?:timeout["\']\s*,\s*["\'][\d.]+["\']\s*,\s*["\'])?([A-Za-z][\w.+-]*)["\']\s*[,\]]'),
    re.compile(r'\b(?:which|system|getoutput|getstatusoutput|check_output|run|Popen|call)\(\s*f?["\']([A-Za-z][\w.+-]*)'),
]
PYIMPORT = re.compile(r'^\s*(?:import|from)\s+(\w+)', re.M)
SHIMPORT = re.compile(r'python3 -c\s*["\'][^"\']*?\bimport\s+(\w+)|python3 -m\s+(\w+)')
HEREDOC = re.compile(r'<<-?\s*([\'"]?)(\w+)\1')


def split_heredocs(text):
    """Shell text without heredoc bodies, and the bodies."""
    keep, body, end = [], [], None
    for line in text.splitlines():
        if end:
            if line.strip() == end:
                end = None
                keep.append('')
            else:
                body.append(line)
            continue
        m = HEREDOC.search(line)
        if m:
            end = m.group(2)
        keep.append(line)
    return '\n'.join(keep), '\n'.join(body)


def blank(text):
    """Comments, literal quoted text and arithmetic blanked; command substitutions and `-c` / `x='…;…'` scripts (not prose) kept."""
    out, i, n, st = [], 0, len(text), ['cs']
    sp = lambda s: re.sub(r'[^\n]', ' ', s)  # noqa: E731
    while i < n:
        c, two = text[i], text[i:i + 2]
        if c == '\\':
            out.append(text[i:i + 2] if st[-1] != 'dq' else '  ')
            i += 2
            continue
        if st[-1] == 'dq':
            if c == '"':
                st.pop()
                out.append(' ')
                i += 1
            elif two == '$(' and text[i:i + 3] != '$((':
                st.append('cs')
                out.append(' (')
                i += 2
            else:
                out.append('\n' if c == '\n' else ' ')
                i += 1
            continue
        if text[i:i + 3] == '$((' or (two == '((' and (i == 0 or text[i - 1] in ' \t\n;')):
            d, j = 0, i
            while j < n:
                d += {'(': 1, ')': -1}.get(text[j], 0)
                j += 1
                if d == 0:
                    break
            out.append(sp(text[i:j]))
            i = j
            continue
        if c == '#' and (i == 0 or text[i - 1] in ' \t\n;'):
            j = text.find('\n', i)
            i = n if j < 0 else j
            continue
        if c == "'":
            j = text.find("'", i + 1)
            j = n if j < 0 else j
            inner = text[i + 1:j]
            script = re.search(r'-c\s*$', text[max(0, i - 6):i]) or (
                re.search(r'\w=$', text[max(0, i - 2):i]) and re.search(r'[;\n]', inner)
                and not re.search(r'[A-Za-z][.,] [A-Za-z]', inner))
            out.append('; ' + blank(inner) + ' ' if script else ' ' + sp(inner) + ' ')
            i = j + 1
            continue
        if c == '"':
            m = re.match(r'"(\$\w+|\$\{\w+\})"', text[i:])
            if m:
                out.append(' ' + m.group(1).replace('{', '').replace('}', '') + ' ')
                i += m.end()
                continue
            st.append('dq')
            out.append('_')
            i += 1
            continue
        if two == '$(':
            st.append('cs')
            out.append(two)
            i += 2
            continue
        if c == '(':
            st.append('p')
        elif c == ')' and len(st) > 1:
            st.pop()
            c = ' )'
        out.append(c)
        i += 1
    return ''.join(out)


def shell_words(text):
    words = set()
    for m in [None] + list(SEP.finditer(text)):
        toks = text[m.end() if m else 0:].split('\n', 1)[0].split()
        while toks and re.match(r'^\w+=\S*$', toks[0]):
            toks.pop(0)
        while toks and toks[0] in PREFIX:
            w = toks.pop(0).lstrip('$')
            if w not in ('exec', 'command', 'time'):
                words.add(w)
            while toks and ARG.match(toks[0]):
                toks.pop(0)
        w = re.sub(r'^/(?:usr/)?s?bin/', '', toks[0].rstrip(';}`')) if toks else ''
        if WORD.match(w):
            words.add(w)
    return words


def py_words(text):
    return {w for r in PYCALL for w in r.findall(text)}


def scan(paths):
    """{tool: {file, …}}: commands on the search path and importable third-party modules (`python3:<mod>`)."""
    dirs = sorted({p if os.path.isdir(p) else os.path.dirname(p) for p in map(os.path.abspath, paths)})
    files = [os.path.join(p, n) for p in map(os.path.abspath, paths)
             for n in (sorted(os.listdir(p)) if os.path.isdir(p) else [os.path.basename(p)])]
    local = {n for d in dirs for n in os.listdir(d)}
    local_mods = {n[:-3] for n in local if n.endswith('.py')}
    roots = sorted({os.path.dirname(d) for d in dirs})
    for top in [r for r in roots if not any(r.startswith(q + os.sep) for q in roots)]:
        for root, subs, names in os.walk(top):
            subs[:] = [d for d in subs if not d.startswith('.') and d != 'node_modules']
            local_mods |= {f[:-3] for f in names if f.endswith('.py')} | set(subs)
    res = {}
    for p in files:
        n = os.path.basename(p)
        if os.path.islink(p) or not os.path.isfile(p):
            continue
        text = open(p, errors='replace').read()
        if not (text.startswith('#!') or n.endswith(('.sh', '.py'))):
            continue
        if 'python' in text.split('\n', 1)[0] or n.endswith('.py'):
            ws = py_words(text)
            mods = set(PYIMPORT.findall(text))
        else:
            code, body = split_heredocs(text)
            ws = shell_words(blank(code)) | py_words(body)
            mods = set(PYIMPORT.findall(body)) | {a or b for a, b in SHIMPORT.findall(text)}
        funcs = set(re.findall(r'^\s*(?:function\s+)?([\w.-]+)\s*\(\)', text, re.M))
        tools = {w for w in ws - funcs - local if shutil.which(w, path=SEARCH)}
        tools |= {'python3:' + m for m in mods - local_mods
                  if m not in sys.stdlib_module_names and find_spec(m) is not None}
        for t in tools:
            res.setdefault(t, set()).add(n)
    return res


def packages(tools):
    """{tool: dpkg package that ships it, or '-'}, from one dpkg -S call."""
    cands = {}
    for t in tools:
        if t.startswith('python3:'):
            o = find_spec(t[8:]).origin or ''
            cands[t] = [os.path.dirname(o) if o.endswith('__init__.py') else o]
        else:
            p = shutil.which(t, path=SEARCH)
            cands[t] = [os.path.realpath(p), p, '/bin/' + t, '/usr/bin/' + t]
    r = subprocess.run(['dpkg', '-S'] + sorted({q for qs in cands.values() for q in qs}), capture_output=True, text=True)
    owner = {}
    for line in r.stdout.splitlines():
        pkgs, _, path = line.partition(': ')
        owner.setdefault(path, pkgs.split(',')[0].split(':')[0].strip())
    return {t: next((owner[q] for q in qs if q in owner), '-') for t, qs in cands.items()}


def main():
    args = sys.argv[1:]
    if not args or args[0] in ('-h', '--help'):
        print(__doc__.strip())
        return 0 if args else 2
    paths = args[:args.index('--deps')] if '--deps' in args else args
    found = scan(paths)
    if '--deps' not in args:
        for t in sorted(found):
            print(t, ','.join(sorted(found[t])), sep='\t')
        return 0
    deps = {line.split('\t', 1)[0] for line in open(args[args.index('--deps') + 1])
            if line.strip() and not line.startswith('#')}
    bad = 0
    pkg_of = packages(set(found) - deps)
    for t in sorted(pkg_of):
        pkg = pkg_of[t]
        if pkg not in BASE:
            print('MISSING', t, pkg, ','.join(sorted(found[t])))
            bad += 1
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
