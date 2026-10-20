"""### tmp residue (--measure): entries of the tmp base by kind, count and MB."""
import collections, os, re, subprocess

from .common import TIMEOUT


def _kind(name):
    """Leading lowercase word segments of a /tmp entry name; mktemp's tmp.XXXX is `tmp.*`."""
    if name.startswith('tmp.'):
        return 'tmp.*'
    words = []
    for seg in re.split(r'[-_.]', name):
        if not re.fullmatch(r'[a-z]+', seg):
            break
        words.append(seg)
    return '-'.join(words) or '(other)'


def rows(ctx):
    """Entries of the tmp base by kind: count and MB (du -sb), top 10 by MB."""
    base = os.environ.get('FLEET_SURVEY_TMP') or '/tmp'
    names = os.listdir(base)
    if not names:
        return [f'0 entries in {base}']
    p = subprocess.run(['du', '-sb', '--', *[os.path.join(base, n) for n in names]],
                       capture_output=True, text=True, timeout=TIMEOUT)
    size = {os.path.basename(r.split('\t', 1)[1]): int(r.split('\t', 1)[0]) for r in p.stdout.splitlines() if '\t' in r}
    kinds = collections.defaultdict(lambda: [0, 0])
    for n in names:
        k = kinds[_kind(n)]
        k[0] += 1
        k[1] += size.get(n, 0)
    top = sorted(kinds.items(), key=lambda kv: (kv[1][1], kv[1][0]), reverse=True)
    return [f'{len(names)} entries, {sum(size.values()) / 1e6:.0f} MB in {base}, {len(kinds)} kinds'] + \
        [f'{n:5}  {b / 1e6:8.1f} MB  {k}' for k, (n, b) in top[:10]]
