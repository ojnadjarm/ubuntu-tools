"""Fix-lane gates: area tests before/after a fix, lint for areas without tests, and the post-session cleanup."""
import argparse
import datetime as dt
import glob
import json
import os
import re
import shlex
import subprocess
import sys
import time

from .backups import manifest, restore, retired_now
from .claims import drop_rows
from .common import AGENTS, AREAS, BACKUPS, HOME, SKILLS, STATE, current_run, die, locked, rel, run_dir, test_exists
from .policy import skill_policy
from .report import cmd_finish


def areas_of(paths):
    keys = []
    for p in paths:
        for key, roots, _ in AREAS:
            if any(p == os.path.join(HOME, r) or p.startswith(os.path.join(HOME, r) + '/') for r in roots) \
                    and key not in keys:
                keys.append(key)
    return keys


def area_tests(keys):
    cmds = []
    for key, _, tests in AREAS:
        if key in keys:
            cmds += [t for t in tests if t not in cmds and test_exists(t)]
    return cmds


def fail_lines(out):
    """Failing-test lines keyed `file: text`, with numbers, temp paths and hex runs masked so only the failure counts."""
    fails, cur = set(), None
    for l in out.splitlines():
        if l.startswith('$ '):
            cur = None
        m = re.match(r'--- (\S+) \(failure', l)
        if m:
            cur = m.group(1)
            continue
        if not re.search(r'\bFAIL|\bERROR\b|Error:|Traceback', l) or re.match(r'(ok|OK|PASS|pass)\b', l.strip()):
            continue
        m = re.match(r'FAIL (\S+\.(?:sh|py|js)) ', l) or re.match(r'FAILED (tests/\S+?\.py)', l)
        f = ('dashboard/' if m and l.startswith('FAILED') else '') + m.group(1) if m else cur
        t = l.strip()
        for pat, to in ((r'--user-data-dir \S+', '--user-data-dir #'), (r'/tmp/\S+', '/tmp/#'), (r'tmp\.[A-Za-z0-9]+', 'tmp.#'),
                        (r'\b[0-9a-f]{6,}\b', '#'), (r'\d+(\.\d+)?', '#')):
            t = re.sub(pat, to, t)
        fails.add((f + ': ' if f else '') + t[:160])
    return sorted(fails)


def file_of(fail):
    m = re.match(r'(\S+\.(?:sh|py|js)): ', fail)
    return m.group(1) if m else None


def run_tests(cmds, timeout=1200):
    me = f'{sys.executable} {os.path.abspath(sys.argv[0])} '
    out, rc = [], 0
    for c in cmds:
        c = me + c[len('code-review '):] if c.startswith('code-review ') else c
        try:
            r = subprocess.run(['bash', '-c', c], cwd=HOME, capture_output=True, text=True, timeout=timeout)
            out.append(f'$ {c}\n{r.stdout}{r.stderr}rc={r.returncode}\n')
            rc = rc or r.returncode
        except subprocess.TimeoutExpired:
            out.append(f'$ {c}\nFAIL timeout after {timeout} s\n')
            rc = rc or 124
    return rc, ''.join(out)


def cmd_tests(a):
    """Run the area tests for a backed-up finding, serialized across lanes; `after` marks the backup VERIFIED or not."""
    base = os.path.join(BACKUPS, current_run(), a.id)
    if not os.path.isfile(os.path.join(base, 'MANIFEST.tsv')):
        die(f'no backup at {rel(base)}: run code-review backup {a.id} <paths> first', 2)
    rows = manifest(base)
    cmds = area_tests(areas_of([os.path.join(HOME, r) for _, r in rows]))
    rc, out = locked(os.path.join(STATE, 'tests'), lambda: run_tests(cmds))
    open(os.path.join(base, f'tests.{a.phase}.log'), 'w').write(out)
    fails = fail_lines(out)
    json.dump({'rc': rc, 'fails': fails, 'cmds': cmds}, open(os.path.join(base, f'tests.{a.phase}.json'), 'w'))
    if a.phase == 'before':
        print(f'baseline: rc {rc}, {len(fails)} failing line(s) · {len(cmds)} command(s)')
        return
    try:
        before = json.load(open(os.path.join(base, 'tests.before.json')))
    except (OSError, ValueError):
        die(f'no baseline: run code-review tests {a.id} before, before the fix', 2)
    new = [f for f in fails if f not in before['fails']]
    if rc and not before['rc'] and not new:
        new = [f'rc {rc} (baseline rc 0)']
    touched = {r for _, r in rows}
    stems = {os.path.basename(r).split('.')[0] for r in touched}

    def own(f):
        b = os.path.basename(f)
        return 'agents/' + f in touched or any((b[5:] if b.startswith('test_') else b).startswith(s) for s in stems)
    outside = sorted({file_of(f) for f in new if file_of(f) and not own(file_of(f))})
    green, end = [], time.time() + 300
    for f in outside[:5]:
        left = int(end - time.time())
        if left <= 0:
            break
        cmd = f'bash agents/bin/tests/run.sh --only {shlex.quote(f)}'
        r, o = locked(os.path.join(STATE, 'tests'), lambda: run_tests([cmd], left))
        open(os.path.join(base, 'tests.after.log'), 'a').write(o)
        if not r:
            green.append(f)
    flaky = [f for f in new if file_of(f) in green]
    new_real = [f for f in new if f not in flaky]
    masked = sum(1 for f in fails if '/tmp/#' in f or 'tmp.#' in f or '--user-data-dir #' in f)
    json.dump({'rc': rc, 'fails': fails, 'cmds': cmds, 'new_real': new_real, 'flaky': flaky, 'masked': masked},
              open(os.path.join(base, 'tests.after.json'), 'w'))
    note = ''.join(f'\nflaky (green on one re-run): {f}' for f in flaky[:10])
    gone = [r for k, r in rows if k in ('file', 'dir') and not os.path.lexists(os.path.join(HOME, r)) and not retired_now(r)]
    why = [f'new failure: {f}' for f in new_real] + [f'deleted {r}: removal goes through code-review retire' for r in gone]
    mark = os.path.join(base, 'VERIFIED')
    if why:
        if os.path.exists(mark):
            os.unlink(mark)
        print('NOT verified\n' + '\n'.join(why[:10]) + note)
        sys.exit(5)
    open(mark, 'w').write(f'{dt.datetime.now().isoformat(timespec="seconds")}\n')
    print(f'verified: no new failures ({len(fails)} failing line(s) after, {len(flaky)} flaky), '
          f'nothing deleted outside code-review retire' + note)


def cmd_lint(a):
    """Checks for areas without a test suite: skills need name+description frontmatter; guide INDEX slugs need a file."""
    bad = []
    if a.what == 'skills' and os.path.isdir(SKILLS):
        for d in sorted(os.listdir(SKILLS)):
            if skill_policy(d) != 'edit' or not os.path.isdir(os.path.join(SKILLS, d)):
                continue
            f = os.path.join(SKILLS, d, 'SKILL.md')
            try:
                m = re.match(r'---\n(.*?)\n---', open(f, errors='replace').read(), re.S)
            except OSError:
                bad.append(f'FAIL skill {d}: no SKILL.md')
                continue
            if not m or not re.search(r'^name:\s*\S', m.group(1), re.M) or \
                    not re.search(r'^description:\s*\S', m.group(1), re.M):
                bad.append(f'FAIL skill {d}: frontmatter needs name and description')
    elif a.what == 'guides':
        g = os.path.join(AGENTS, 'KB', 'guides')
        try:
            for line in open(os.path.join(g, 'INDEX.md')):
                m = re.match(r'- ([\w.-]+) — ', line)
                if m and not os.path.isfile(os.path.join(g, m.group(1) + '.md')):
                    bad.append(f'FAIL guide index: {m.group(1)}.md does not exist')
        except OSError:
            pass
    print('\n'.join(bad) if bad else f'lint {a.what}: ok')
    sys.exit(1 if bad else 0)


def cmd_cleanup(a):
    """Drop leftover code-review claim rows and restore every backup of this run that was never verified."""
    n = drop_rows(lambda l: l.startswith('- code-review-'))
    run = current_run()
    done = []
    for base in sorted(glob.glob(os.path.join(BACKUPS, run, '*'))):
        if not os.path.isfile(os.path.join(base, 'MANIFEST.tsv')):
            continue
        if os.path.exists(os.path.join(base, 'VERIFIED')) or os.path.exists(os.path.join(base, 'RESTORED')):
            continue
        mine = {r for _, r in manifest(base)}
        later = [o for o in glob.glob(os.path.join(BACKUPS, run, '*', 'VERIFIED'))
                 if os.path.getmtime(os.path.dirname(o)) > os.path.getmtime(base)
                 and mine & {r for _, r in manifest(os.path.dirname(o))}]
        if later:
            print(f'cleanup: kept {os.path.basename(base)}: a later verified fix covers the same path(s)')
            continue
        restore(run, os.path.basename(base), auto=True)
        done.append(os.path.basename(base))
    print(f'cleanup: {n} stale claim row(s) dropped · {len(done)} unverified backup(s) restored'
          + (f' ({", ".join(done)})' if done else ''))
    rdir = run_dir(run)
    if os.path.isfile(os.path.join(rdir, 'args.json')) and not os.path.isfile(os.path.join(rdir, 'result.json')):
        kept = len(glob.glob(os.path.join(BACKUPS, run, '*', 'VERIFIED')))
        json.dump({'found': 0, 'items': [], 'error': f'the session ended before the swarm returned (timeout or crash); '
                   f'{len(done)} unverified edit(s) restored, {kept} verified fix(es) kept'},
                  open(os.path.join(rdir, 'result.json'), 'w'))
        cmd_finish(argparse.Namespace(run=run))
