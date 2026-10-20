"""### untested: scripts whose name or stem is no word in any test file."""
import glob, os, re

from .common import AG, SKILL_ROOTS, scripts, test_base


def _test_words():
    files = glob.glob(os.path.join(AG, 'bin', 'tests', '**', '*'), recursive=True)
    files += glob.glob(os.path.join(AG, 'hooks', '*.test.*')) + glob.glob(os.path.join(AG, 'adapters', '*', 'hooks', '*.test.*'))
    for root in SKILL_ROOTS:
        files += glob.glob(os.path.join(root, '*', 'tests', '**', '*'), recursive=True)
    words = set()
    for f in files:
        if not os.path.isfile(f) or '__pycache__' in f:
            continue
        words.add(test_base(os.path.basename(f)))
        try:
            with open(f, errors='replace') as fh:
                words.update(re.findall(r'[\w.+-]+', fh.read()))
        except OSError:
            pass
    return words


def rows(ctx):
    words = _test_words()
    home = os.path.expanduser('~')
    out = []
    for p in sorted(scripts()):
        name = os.path.basename(p)
        if name in words or os.path.splitext(name)[0] in words:
            continue
        with open(p, 'rb') as fh:
            n = fh.read().count(b'\n')
        out.append(f'{n:6}  {p.replace(home, "~")}')
    return [f'{len(out)} scripts with no test naming them'] + out
