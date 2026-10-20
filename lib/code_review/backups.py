"""Backups of what a fix touches, and restore without deleting (displaced/ keeps what the fix left)."""
import datetime as dt
import glob
import os
import shutil
import sys

from .common import AGENTS, AREAS, BACKUPS, HOME, RETIRED, SKILLS, absp, current_run, die, rel
from .policy import policy


def area_roots():
    return [os.path.join(HOME, p) for _, ps, _ in AREAS for p in ps] + [AGENTS, SKILLS, HOME]


def backup_refusal(src):
    if policy(src) != 'edit':
        return f'{rel(src)} is {policy(src)}; not backed up'
    if os.path.isdir(src) and not os.path.islink(src):
        if any(src == r or r.startswith(src.rstrip('/') + '/') for r in area_roots()):
            return f'{rel(src)} is an area root or above; back up the files you touch'
        files = [os.path.join(a, f) for a, _, fs in os.walk(src) for f in fs]
        if len(files) > 300:
            return f'{rel(src)} holds {len(files)} files; back up the files you touch'
        bad = [f for f in files if policy(f) != 'edit']
        if bad:
            return f'{rel(bad[0])} inside {rel(src)} is {policy(bad[0])}'
    return ''


def cmd_backup(a):
    """Copy every path a fix will touch (absent ones are recorded, so restore moves away what the fix created)."""
    run = current_run()
    base = os.path.join(BACKUPS, run, a.id)
    if os.path.exists(base):
        die(f'backup {rel(base)} exists; a finding id is backed up once per run', 2)
    srcs = [absp(p) for p in a.paths]
    for src in srcs:
        why = backup_refusal(src)
        if why:
            die(why, 3)
    rows = []
    for src in srcs:
        dst = os.path.join(base, 'files', rel(src))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.isdir(src) and not os.path.islink(src):
            shutil.copytree(src, dst, symlinks=True)
            rows.append(f'dir\t{rel(src)}')
        elif os.path.lexists(src):
            shutil.copy2(src, dst, follow_symlinks=False)
            rows.append(f'file\t{rel(src)}')
        else:
            rows.append(f'absent\t{rel(src)}')
    with open(os.path.join(base, 'MANIFEST.tsv'), 'w') as fh:
        fh.write('\n'.join(rows) + '\n')
    print(f'backup {rel(base)} ({len(rows)} path(s)) · restore: code-review restore {run} {a.id}')


def manifest(base):
    out = []
    for line in open(os.path.join(base, 'MANIFEST.tsv')):
        if '\t' in line:
            out.append(line.rstrip('\n').split('\t', 1))
    return out


def displace(dst, base):
    """Move the live item out of the way without deleting it: rename beside it, then into the backup's displaced/."""
    side = f'{dst}.cr-displaced-{os.getpid()}'
    os.rename(dst, side)
    keep = os.path.join(base, 'displaced', rel(dst))
    os.makedirs(os.path.dirname(keep), exist_ok=True)
    try:
        shutil.move(side, keep)
    except OSError as e:
        print(f'code-review: left {rel(side)} beside the item ({e})', file=sys.stderr)
    return side


def retired_now(r):
    """True when HOME-relative path r was removed by code-review retire and not brought back."""
    return not os.path.lexists(os.path.join(HOME, r)) and bool(glob.glob(os.path.join(glob.escape(RETIRED), '*', r)))


def restore(run, fid, auto=False):
    base = os.path.join(BACKUPS, run, fid)
    if not os.path.isfile(os.path.join(base, 'MANIFEST.tsv')):
        die(f'no backup at {rel(base)}', 2)
    if os.path.exists(os.path.join(base, 'RESTORED')):
        die(f'{rel(base)} was already restored', 2)
    n = 0
    for kind, r in manifest(base):
        dst = os.path.join(HOME, r)
        if auto and retired_now(r):
            continue
        if kind == 'absent':
            if os.path.lexists(dst):
                displace(dst, base)
        else:
            src = os.path.join(base, 'files', r)
            tmp = f'{dst}.cr-restore-{os.getpid()}'
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if kind == 'dir':
                shutil.copytree(src, tmp, symlinks=True)
            else:
                shutil.copy2(src, tmp, follow_symlinks=False)
            if os.path.lexists(dst):
                displace(dst, base)
            os.rename(tmp, dst)
        n += 1
    open(os.path.join(base, 'RESTORED'), 'w').write(f'{dt.datetime.now().isoformat(timespec="seconds")}\n')
    return n


def cmd_restore(a):
    n = restore(a.run, a.id)
    print(f'restored {n} path(s) from {rel(os.path.join(BACKUPS, a.run, a.id))}; what the fix left is in its displaced/')
