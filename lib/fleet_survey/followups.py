"""### followups: `followups --open --json` counts line, then the due rows."""
import json

from .common import run


def rows(ctx):
    d = json.loads('\n'.join(run('followups', '--open', '--json')))
    out = [f"{d['open']} open, {d['due']} due, {d['shipped?']} shipped?"]
    return out + [f"L{r['line']} {r['tid'] or '-'} due {r['due']}  {r['text'][:110]}" for r in d['lines'] if r['status'] == 'due']
