"""### dup defs (--measure): top-level function names defined in >= 3 script files."""
import collections, os, re

from .common import AG, scripts, short

COMMON_DEFS = {'main', 'usage', 'die'}
PY_DEF = re.compile(r'^def (\w+)\(', re.M)
SH_DEF = re.compile(r'^\s*(?:function\s+)?([A-Za-z_][\w-]*)\s*\(\)\s*\{', re.M)


def rows(ctx):
    """Top-level function names defined in >= 3 files of bin/, lib/, hooks/ and skill scripts (COMMON_DEFS skipped)."""
    files = {os.path.realpath(p) for p in scripts()}
    where = collections.defaultdict(dict)
    for f in files:
        try:
            with open(f, errors='replace') as fh:
                text = fh.read(500000)
        except OSError:
            continue
        if '\0' in text[:1000]:
            continue
        py = f.endswith('.py') or 'python' in text.split('\n', 1)[0]
        for m in (PY_DEF if py else SH_DEF).finditer(text):
            where[m.group(1)].setdefault(f, text.count('\n', 0, m.start()) + 1)
    dups = sorted(((len(v), k) for k, v in where.items() if len(v) >= 3 and k not in COMMON_DEFS), reverse=True)
    home = os.path.join(AG, '')
    return [f'{len(dups)} names defined in >= 3 of {len(files)} files ({"/".join(sorted(COMMON_DEFS))} skipped)'] + \
        [f'{n:3}x {k:20} ' + ' '.join(f'{short(f.replace(home, ""))}:{ln}' for f, ln in sorted(where[k].items())[:5])
         for n, k in dups[:20]]
