"""After the swarm: enforce verified fixes, record seen verdicts, write findings.md and REPORT.md, then deliver once."""
import importlib.util
import json
import os
import re
import shutil
import subprocess
import time

from .backups import restore
from .common import AGENTS, BACKUPS, DATE, FIXTURE, ME, STATE, absp, current_run, die, rel, run_dir

_core = importlib.util.spec_from_file_location(
    'audit_log', os.path.join(os.path.dirname(os.path.realpath(__file__)), '..', '..', 'hooks', 'audit-log.py'))
audit_log = importlib.util.module_from_spec(_core)
_core.loader.exec_module(audit_log)
redact = audit_log.redact

# Verdicts that keep a finding out of later weeks; deferred (skipped, capped, reverted, failed, unverified) comes back.
SKIP_VERDICTS = ('refuted', 'queued', 'staged', 'reported', 'retired', 'kept')
SEEN_VERDICT = {'fixed': 'fixed', 'retired': 'retired', 'queued': 'queued', 'staged': 'staged', 'kept': 'kept',
                'left': 'reported'}


def read_or_none(p):
    try:
        return open(p, errors='replace').read()
    except OSError:
        return None


def toolsmith_tamper(tid, run):
    """Why a toolsmith lane broke append-only ('' if not): the proposal keeps its earlier lines, BACKLOG.md only status words."""
    old_dir = os.path.join(BACKUPS, run, tid, 'files', 'agents', 'toolsmith')
    live_dir = os.path.join(AGENTS, 'toolsmith')
    old, new = (read_or_none(os.path.join(d, 'proposals', tid + '.md')) for d in (old_dir, live_dir))
    if old is None or new is None or not new.startswith(old):
        return 'earlier lines of the proposal changed (or it was not backed up)'
    old, new = (read_or_none(os.path.join(d, 'BACKLOG.md')) for d in (old_dir, live_dir))
    cells = lambda line: [c for k, c in enumerate(line.split('|')) if k != 5]
    if old is None or new is None or len(old.splitlines()) != len(new.splitlines()) or \
            any(cells(a) != cells(b) for a, b in zip(old.splitlines(), new.splitlines())):
        return 'BACKLOG.md changed beyond a status word (or it was not backed up)'
    return ''


def enforce(items, run):
    """A 'fixed' item counts only with a VERIFIED backup (and, for a toolsmith item, append-only edits); else restored."""
    for i in items:
        if i.get('merged_into') or i.get('verdict') != 'confirmed':
            continue
        base = os.path.join(BACKUPS, run, str(i.get('id')))
        why = ''
        if i.get('status') == 'fixed':
            if not os.path.exists(os.path.join(base, 'VERIFIED')):
                why = f'no verified test record (code-review tests {i.get("id")} after)'
            elif i.get('kind') == 'toolsmith':
                why = toolsmith_tamper(str(i.get('id')), run)
        if why:
            restored = ''
            if os.path.isfile(os.path.join(base, 'MANIFEST.tsv')) and not os.path.exists(os.path.join(base, 'RESTORED')):
                restore(run, str(i.get('id')), auto=True)
                restored = '; its backup was restored'
            i['status'] = 'unverified'
            i['note'] = f'finish: {why}{restored}. ' + str(i.get('note') or '')
        if i.get('status') == 'already-fixed' and i.get('file') and not os.path.lexists(absp(i['file'])):
            i['status'] = 'deferred'
            i['note'] = 'the item was retired or moved before this fix ran; restoring it brings the defect back. ' + \
                str(i.get('note') or '')
    keeper = {i.get('id'): i for i in items if not i.get('merged_into')}
    for i in items:
        k = keeper.get(i.get('merged_into'))
        if k:
            i['status'], i['verdict'] = k.get('status'), k.get('verdict')


def cmd_finish(a):
    run = current_run() if not a.run else a.run
    rdir = run_dir(run)
    try:
        res = json.load(open(os.path.join(rdir, 'result.json')))
        items = res['items']
    except (OSError, ValueError, KeyError, TypeError) as e:
        die(f'result.json unreadable in {rel(rdir)}: {e}', 2)
    enforce(items, run)
    main = [i for i in items if not i.get('merged_into')]
    found = int(res.get('found', len(main)))
    confirmed = [i for i in main if i.get('verdict') == 'confirmed']
    fixed = [i for i in confirmed if i.get('status') in ('fixed', 'already-fixed')]
    retired = [i for i in confirmed if i.get('status') == 'retired']
    left = [i for i in confirmed if i not in fixed and i not in retired]
    with open(os.path.join(STATE, 'seen.jsonl'), 'a') as fh:
        for i in items:
            st = i.get('status')
            v = 'unverified' if i.get('verdict') == 'unverified' else 'refuted' if i.get('verdict') != 'confirmed' else \
                'fixed' if st == 'already-fixed' else SEEN_VERDICT.get(st, 'deferred')
            fh.write(json.dumps({'key': i.get('key'), 'date': DATE, 'run': run, 'verdict': v,
                                 'title': i.get('title'), 'file': i.get('file')}) + '\n')
    by = {}
    for i in left:
        by[i.get('status') or 'left'] = by.get(i.get('status') or 'left', 0) + 1
    md = [f'# Code review — {run}', '',
          f'Found {found} · confirmed {len(confirmed)} · fixed {len(fixed)} · retired {len(retired)} · left {len(left)}', '']
    if res.get('error'):
        md += [f'**Run error:** {res["error"]}', '']

    def section(title, rows):
        if not rows:
            return
        md.extend([f'## {title}', ''])
        for i in rows:
            md.append(f'- **{i.get("title")}** — `{rel(absp(i.get("file", "?")))}` · {i.get("kind")} · '
                      f'votes {i.get("votes", "?")}' + (f' · {i.get("status")}' if i.get('status') else ''))
            for k in ('note', 'test', 'restore', 'queue'):
                if i.get(k):
                    md.append(f'  - {k}: {i[k]}')
        md.append('')
    section('Fixed', fixed)
    section('Retired', retired)
    section('Left for the owner or next week', left)
    section('Unverified (refuters gave no answer; back next week)', [i for i in main if i.get('verdict') == 'unverified'])
    section('Refuted', [i for i in main if i.get('verdict') not in ('confirmed', 'unverified')])
    section('Duplicate reports merged into the findings above', [i for i in items if i.get('merged_into')])
    doc = os.path.join(rdir, 'findings.md')
    open(doc, 'w').write(redact('\n'.join(md) + '\n'))
    lines = [f'found {found}', f'confirmed {len(confirmed)}', f'fixed {len(fixed)}', f'retired {len(retired)}',
             f'left {len(left)}' + (' (' + ', '.join(f'{k} {v}' for k, v in sorted(by.items())) + ')' if by else '')]
    unver = sum(i.get('verdict') == 'unverified' for i in main)
    if unver:
        lines.append(f'unverified {unver} (refuters gave no answer; back next week)')
    with open(os.path.join(ME, 'REPORT.md'), 'w') as fh:
        fh.write('\n'.join(lines) + '\n')
    msg = (f'code-review: found {found}, confirmed {len(confirmed)}, fixed {len(fixed)}, retired {len(retired)}, '
           f'left {len(left)}' + (' (run error)' if res.get('error') else ''))
    json.dump({'doc': doc, 'msg': msg, 'at': time.time()}, open(os.path.join(rdir, 'outbox.json'), 'w'))
    print('\n'.join(lines + ['publish and push: code-review deliver (run by the sandbox wrapper after the session)']))


def cmd_deliver(a):
    """Publish the findings doc and send the one weekly push; runs outside the sandbox, after the session."""
    rdir = run_dir()
    try:
        box = json.load(open(os.path.join(rdir, 'outbox.json')))
    except (OSError, ValueError):
        print(f'deliver: nothing to deliver in {rel(rdir)}')
        return
    mark = os.path.join(rdir, 'delivered')
    if os.path.exists(mark) and os.path.getmtime(mark) >= box.get('at', 0):
        print('deliver: already delivered')
        return
    link = publish(box['doc'])
    sent = os.path.join(rdir, 'pushed')
    if os.path.exists(sent):
        print(f'deliver: doc republished at {link}; push already sent for this run')
    else:
        notify(f'{box["msg"]} {link}'[:200])
        open(sent, 'w').write(box['msg'] + '\n')
        print(f'deliver: published {link} · one push sent')
    open(mark, 'w').write(link + '\n')


def publish(doc):
    if FIXTURE:
        out = os.path.join(STATE, 'outbox')
        os.makedirs(out, exist_ok=True)
        shutil.copy(doc, os.path.join(out, 'published.md'))
        return f'https://fixture.invalid:8498/plans/code-review-{DATE}/'
    r = subprocess.run(['plan-publish', '--kind', 'report', '--slug', 'code-review', doc],
                       capture_output=True, text=True)
    url = (r.stdout.strip().splitlines() or [''])[-1]
    return re.sub(r'^http://([^/:]+):19998', r'https://\1:8498', url)


def notify(msg):
    if FIXTURE:
        os.makedirs(os.path.join(STATE, 'outbox'), exist_ok=True)
        with open(os.path.join(STATE, 'outbox', 'notify.log'), 'a') as fh:
            fh.write(msg + '\n')
        return
    subprocess.run(['notify-owner', '-t', 'code-review', msg], check=False)
