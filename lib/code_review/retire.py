"""Retire a NOT USEFUL item behind its gates (with a one-line restore), and reserve improve/queue items."""
import os
import re
import shutil
import sys

from .claims import claimed_by_others, covers
from .common import DATE, FIXTURE, HOME, QUEUE, RETIRED, SKILLS, absp, die, locked, rel
from .evidence import refs
from .policy import policy

RETIRE_WHY = ('broken', 'duplicate', 'superseded', 'obsolete')


def retire_gates(target, why, by, proof):
    """Reasons the item may not be retired; empty list = allowed. Usage counts are never a gate (usefulness rule)."""
    out = []
    pol = policy(target)
    if pol not in ('edit', 'retire-only'):
        out.append(f'policy {pol}')
    if not os.path.lexists(target):
        out.append('does not exist')
    if why not in RETIRE_WHY:
        out.append(f'--why must be one of {", ".join(RETIRE_WHY)} (low use is never a reason)')
    if why in ('duplicate', 'superseded'):
        if not by:
            out.append(f'--why {why} needs --by <the item that does the job at least as well>')
        elif '/' in by and not os.path.lexists(absp(by)):
            out.append(f'--by {by} does not exist')
        elif '/' not in by and not shutil.which(by) and not os.path.isdir(os.path.join(SKILLS, by)):
            out.append(f'--by {by} is not installed (no command or skill of that name)')
        if not proof or not os.path.isfile(absp(proof)) or os.path.getsize(absp(proof)) == 0:
            out.append('--proof <file> must hold the side-by-side run showing the replacement does the job at least as well')
    r = refs(target)
    if r:
        out.append(f'{len(r)} reference(s) still point at it (migrate them first): {", ".join(r[:5])}')
    for owner, p in claimed_by_others(''):
        if covers(p, target):
            out.append(f'claimed by {owner}')
    return out


def cmd_retire(a):
    target = absp(a.path)
    why = retire_gates(target, a.why, a.by, a.proof)
    if why:
        print(f'kept {rel(target)}: ' + '; '.join(why))
        sys.exit(4)
    if a.check:
        print(f'retirable {rel(target)} ({a.why})')
        return
    dst = os.path.join(RETIRED, DATE, rel(target))
    if os.path.lexists(dst):
        die(f'{rel(dst)} already exists', 2)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.isdir(target) and not os.path.islink(target):
        shutil.copytree(target, dst, symlinks=True)
    else:
        shutil.copy2(target, dst, follow_symlinks=False)
    side = f'{target}.cr-retiring-{os.getpid()}'
    os.rename(target, side)
    try:
        shutil.rmtree(side) if os.path.isdir(side) and not os.path.islink(side) else os.unlink(side)
    except OSError as e:
        print(f'code-review: copy is in {rel(dst)}; could not clear {rel(side)} ({e})', file=sys.stderr)
    home = '~' if not FIXTURE else HOME
    restore = f'mv {home}/{rel(dst)} {home}/{rel(target)}'
    reason = f'{a.why}' + (f' by {a.by}' if a.by else '')
    with open(os.path.join(RETIRED, DATE, 'MANIFEST.tsv'), 'a') as fh:
        fh.write(f'{rel(target)}\t{a.id or "-"}\t{restore}\t{reason}\n')
    print(f'retired {rel(target)} ({reason}) → {rel(dst)} · restore: {restore}')


def cmd_queue_new(a):
    """Reserve the next CR-NNN in improve/queue with the improve-gate skeleton; print its path."""
    def make():
        os.makedirs(QUEUE, exist_ok=True)
        nums = [int(m.group(1)) for f in os.listdir(QUEUE) for m in [re.match(r'CR-(\d+)\.md$', f)] if m]
        n = max(nums, default=0) + 1
        p = os.path.join(QUEUE, f'CR-{n:03d}.md')
        with open(p, 'x') as fh:
            fh.write(f'# CR-{n:03d} — {a.title}\n\nclass: {a.cls}\nrollback: \nstatus: proposed\n'
                     f'source: code-review {DATE}\n\n## Problem\n\n## Evidence\n\n## Proposed change\n\n'
                     '## Success check\n- metric: \n- before: \n- target: \n- measured by: \n\n## Class\n'
                     f'{a.cls}\n')
        return p
    print(locked(os.path.join(QUEUE, '.cr'), make))
