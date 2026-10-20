"""### creative motion-video: MV_* knobs and the newest motion build.json cost."""
import glob, json, os, re

from .common import AW, age, short
from .creative import stack_rows


def _knobs(root):
    """MV_* names in scripts/ and templates/, mv-knobs-doc's scope."""
    knobs = set()
    for d in ('scripts', 'templates'):  # mv-knobs-doc.test.sh: grep -rhoEI --exclude-dir=node_modules
        for dp, dns, fns in os.walk(os.path.join(root, d)):
            dns[:] = [x for x in dns if x != 'node_modules']
            for name in fns:
                with open(os.path.join(dp, name), 'rb') as fh:
                    data = fh.read()
                if b'\0' not in data:
                    knobs.update(k.decode() for k in re.findall(rb'MV_[A-Z0-9_]+', data))
    return f'{len(knobs)} MV_* knobs {" ".join(sorted(knobs))}'


def _build():
    """Newest ~/agent-work/motion/*/out/build.json: cpu_s and its top 3 steps_cpu."""
    files = glob.glob(os.path.join(AW, 'motion', '*', 'out', 'build.json'))
    if not files:
        return f'build cpu_s none: no {short(AW)}/motion/*/out/build.json'
    f = max(files, key=os.path.getmtime)
    with open(f) as fh:
        d = json.load(fh)
    top = sorted((d.get('steps_cpu') or {}).items(), key=lambda kv: kv[1], reverse=True)[:3]
    return (f'build cpu_s {d.get("cpu_s", "?")}  steps_cpu top {" ".join(f"{k}={v}" for k, v in top) or "none"}'
            f'  {short(f)}, {age(os.path.getmtime(f))}')


def rows(ctx):
    return stack_rows('motion-video', lambda root: [_knobs(root), _build()])
