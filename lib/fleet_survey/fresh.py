"""### fresh suite: score line of the newest evidence/*/fresh-suite*.txt."""
import os, re

from .common import AW, age, latest, short


def rows(ctx):
    f = latest(os.path.join(AW, 'evidence', '*', 'fresh-suite*.txt'))
    with open(f, errors='replace') as fh:
        score = next((r.strip() for r in fh if re.match(r'(PASS|FAIL) \d+/\d+', r)), 'no score line')
    return [f'{score}  ({short(f)}, {age(os.path.getmtime(f))})']
