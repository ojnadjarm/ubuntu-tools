"""Rows every creative-stack section shares: script/test counts and the newest ~/drop previews."""
import glob, os, re, time

from .common import AG, AW, NA, short

STACKS = ('motion-video', 'gamedev')
MEDIA = ('.mp4', '.webm', '.mkv', '.mov', '.gif', '.png', '.jpg', '.jpeg')


def _brief(t):
    """Text of briefs/<T>-*.md above its common rules, or ''."""
    for f in glob.glob(os.path.join(AW, 'briefs', f'{t}-*.md')) + glob.glob(os.path.join(AW, 'briefs', f'{t}.md')):
        with open(f, errors='replace') as fh:
            return fh.read().split('## Common rules')[0]
    return ''


def _drop_stack(t):
    text = _brief(t)
    n = {s: text.count(s) for s in STACKS}
    best = max(n, key=n.get)
    return best if n[best] and list(n.values()).count(n[best]) == 1 else None


def _drops(stack):
    """Newest media file of each ~/drop/T<n>* dir whose brief names the stack, newest 3."""
    hits = []
    for d in glob.glob(os.path.join(os.path.expanduser('~'), 'drop', 'T*')):
        m = re.match(r'(T\d+)', os.path.basename(d))
        if not (m and os.path.isdir(d)) or _drop_stack(m.group(1)) != stack:
            continue
        media = [os.path.join(d, f) for f in os.listdir(d) if f.lower().endswith(MEDIA)]
        if media:
            hits.append(max(media, key=os.path.getmtime))
    hits.sort(key=os.path.getmtime, reverse=True)
    return [f'drop  {os.path.getsize(f) / 1e6:6.1f} MB  {time.strftime("%m-%d %H:%M", time.localtime(os.path.getmtime(f)))}  '
            f'{short(f)}' for f in hits[:3]] or ['drop  none']


def stack_rows(stack, middle):
    """Counts row, the stack's own rows (middle(root)), then its drops."""
    root = os.path.join(AG, 'skills', stack)
    if not os.path.isdir(root):
        raise NA(f'no {root}')
    scripts = [f for f in glob.glob(os.path.join(root, 'scripts', '*')) if os.path.isfile(f)]
    tests = glob.glob(os.path.join(root, 'tests', '*.test.*'))
    return [f'{len(scripts)} scripts, {len(tests)} tests  {short(root)}'] + middle(root) + _drops(stack)
