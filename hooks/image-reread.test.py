#!/usr/bin/env python3
"""image-reread PreToolUse hook on fixture images, then a replay of 7 days of real transcripts.
Run: python3 image-reread.test.py"""
import glob, io, json, mmap, os, statistics, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.realpath(__file__))
HOOK = os.path.join(HERE, 'image-reread.py')
CODE = compile(open(HOOK, 'rb').read(), HOOK, 'exec')
sys.path.insert(0, os.path.join(HERE, '..', 'bin', 'tests', 'lib'))
from budget import budget
WORK = tempfile.mkdtemp(prefix='irr-')
RUN = os.path.join(WORK, 'run')
os.makedirs(RUN)
ENV = dict(os.environ, HOME=WORK, HARNESS_HOME=WORK, XDG_RUNTIME_DIR=RUN)
REAL_RUN = os.environ.get('XDG_RUNTIME_DIR', '')
bad = 0


def check(name, ok):
    global bad
    print(('ok   ' if ok else 'FAIL ') + name)
    bad |= not ok


def fixture(name, data=b'\x89PNG fixture'):
    p = os.path.join(WORK, name)
    with open(p, 'wb') as f:
        f.write(data)
    return p


def call(raw, env=ENV, spawn=False):
    """(exit code, stdout) of the hook: a real process when spawn, else its code run here with stdin, stdout and environ swapped."""
    if spawn:
        p = subprocess.run([HOOK], input=raw, capture_output=True, text=True, env=env, cwd=WORK, timeout=10)
        return p.returncode, p.stdout
    saved = os.environ.copy(), sys.stdin, sys.stdout
    os.environ.clear()
    os.environ.update(env)
    sys.stdin, sys.stdout = io.TextIOWrapper(io.BytesIO(raw.encode())), io.StringIO()
    rc = 0
    try:
        exec(CODE, {'__name__': '__main__', '__file__': HOOK})
    except SystemExit as e:
        rc = e.code or 0
    finally:
        out = sys.stdout.getvalue()
        os.environ.clear()
        os.environ.update(saved[0])
        sys.stdin, sys.stdout = saved[1], saved[2]
    return rc, out


def run(path, tool='Read', sid='s1', aid=None, raw=None, env=ENV, spawn=False):
    """(exit code, deny reason or None) of the hook fed one PreToolUse event."""
    ev = {'hook_event_name': 'PreToolUse', 'session_id': sid, 'tool_name': tool, 'tool_input': {'file_path': path}}
    if aid:
        ev['agent_id'] = aid
    rc, out = call(raw if raw is not None else json.dumps(ev), env, spawn)
    o = json.loads(out).get('hookSpecificOutput', {}) if out.strip() else {}
    return rc, (o.get('permissionDecisionReason') if o.get('permissionDecision') == 'deny' else None)


def outcomes(path, n, **kw):
    return [run(path, **kw)[1] for _ in range(n)]


def compact(sid='s1', aid=None):
    """Feed one PostCompact event, the shape Claude Code 2.1.303 sends."""
    ev = {'hook_event_name': 'PostCompact', 'session_id': sid, 'trigger': 'auto', 'compact_summary': 'summary'}
    if aid:
        ev['agent_id'] = aid
    return call(json.dumps(ev))


# Selftest: the sandbox's runtime dir is the only one written; the real one never sees a fixture session.
img = fixture('shot.png')
run(img, sid='selftest', spawn=True)
check('selftest: counts land in the fixture runtime dir', os.path.exists(os.path.join(RUN, 'image-reread', 'selftest-.json')))
check('selftest: the real runtime dir is untouched', not glob.glob(os.path.join(REAL_RUN, 'image-reread', 'selftest*')))

r = outcomes(img, 5)
check('reads 1-3 of the same image pass', r[:3] == [None] * 3)
check('the 4th read is denied with "read 3× already; use the earlier view, or crop"',
      r[3] is not None and 'read 3× already; use the earlier view, or crop' in r[3] or print('     got', r))
check('the 5th read is still denied', r[4] is not None)
os.utime(img, ns=(time.time_ns(), time.time_ns() + 10**9))
check('a re-rendered image (new mtime) passes again', run(img)[1] is None)
check('another session passes', run(img, sid='s2')[1] is None)
check('a subagent of the same session has its own count', outcomes(img, 4, aid='a7')[:3] == [None] * 3)
cimg = fixture('compact.png')
before3 = outcomes(cimg, 3, sid='c1') + outcomes(cimg, 3, sid='c2') + outcomes(cimg, 3, sid='c1', aid='ca')
p = compact(sid='c1')
check('PostCompact: exit 0, no output', p[0] == 0 and not p[1].strip())
r = outcomes(cimg, 4, sid='c1')
check('compaction: 3 reads, compact, 3 more pass, the 4th after it is denied',
      before3 == [None] * 9 and r[:3] == [None] * 3 and r[3] is not None or print('     got', before3, r))
check('compaction leaves another session\'s count alone', run(cimg, sid='c2')[1] is not None)
check('compaction of the main thread leaves its subagent\'s count alone', run(cimg, sid='c1', aid='ca')[1] is not None)
compact(sid='c1', aid='ca')
r = outcomes(cimg, 4, sid='c1', aid='ca')
check('a subagent\'s own compaction resets only its count', r[:3] == [None] * 3 and r[3] is not None
      and run(cimg, sid='c1')[1] is not None)
check('compaction with no count file yet: exit 0', compact(sid='fresh')[0] == 0)
up = fixture('UP.JPG')
check('upper-case .JPG is counted', outcomes(up, 4)[3] is not None)
for ext in ('gif', 'webp', 'jpeg'):
    check(f'.{ext} is counted', outcomes(fixture('x.' + ext), 4)[3] is not None)

before = sorted(os.listdir(os.path.join(RUN, 'image-reread')))
mtimes = {f: os.stat(os.path.join(RUN, 'image-reread', f)).st_mtime_ns for f in before}
for name, path, tool in [('a .md file', fixture('notes.md', b'x.png'), 'Read'),
                         ('a .png.md file', fixture('notes.png.md'), 'Read'),
                         ('a .py file', fixture('render_png.py'), 'Read'),
                         ('Write of a .png', img, 'Write'),
                         ('Edit of a .png', img, 'Edit'),
                         ('a missing image', os.path.join(WORK, 'gone.png'), 'Read')]:
    check(f'pass {name}, 6 times', outcomes(path, 6, sid='nt', tool=tool) == [None] * 6)
after = sorted(os.listdir(os.path.join(RUN, 'image-reread')))
check('non-images and other tools never touch a count file',
      after == before and all(os.stat(os.path.join(RUN, 'image-reread', f)).st_mtime_ns == mtimes[f] for f in after))
check('no runtime dir: fail open', outcomes(img, 5, sid='nr', env={k: v for k, v in ENV.items() if k != 'XDG_RUNTIME_DIR'}) == [None] * 5)
check('fail open on bad input (exit 0, no output)', run('', raw='not json "Read" .png') == (0, None))
with open(os.path.join(RUN, 'image-reread', 'corrupt-.json'), 'w') as f:
    f.write('{oops')
check('a corrupt count file restarts the count', run(img, sid='corrupt')[1] is None)


def p50(path, tool, lim):
    """Median ms of 9 spawns; over lim, 12 more spawns join the median (21, the pre-T851 sample)."""
    ts = []
    for i in range(21):
        if i == 9 and statistics.median(ts) * 1000 <= lim:
            break
        t0 = time.time()
        run(path, tool=tool, sid=f'lat{i}', spawn=True)
        ts.append(time.time() - t0)
    return statistics.median(ts) * 1000


lim = budget(0.04) * 1000
for name, path, tool in [('Bash (byte gate)', 'ls -la', 'Bash'), ('Read of a .py', fixture('a.py'), 'Read'),
                         ('Read of an image', img, 'Read')]:
    ms = p50(path, tool, lim)
    check(f'p50 latency, {name}: {ms:.0f} ms (budget {lim:.0f} ms)', ms <= lim)

def read_lines(p, needle=b'"name":"Read"'):
    """Each line of p holding needle, found by mmap.find rather than a Python loop over every line."""
    with open(p, 'rb') as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
        i = m.find(needle)
        while i >= 0:
            e = m.find(b'\n', i)
            e = len(m) if e < 0 else e
            yield m[m.rfind(b'\n', 0, i) + 1:e]
            i = m.find(needle, e)


# Replay: every Read of an image in the last 7 days of transcripts; one transcript file is one context.
cut = time.time() - 7 * 86400
exts = (b'.png', b'.jpg', b'.jpeg', b'.gif', b'.webp')
reads, saved, top = 0, 0, {}
t0 = time.time()
for p in glob.glob(os.path.expanduser('~/.claude/projects/**/*.jsonl'), recursive=True):
    try:
        if os.path.getmtime(p) < cut:
            continue
        seen = {}
        for line in read_lines(p):
            if any(e in line.lower() for e in exts):
                try:
                    content = json.loads(line).get('message', {}).get('content', [])
                except ValueError:
                    continue
                for c in content if isinstance(content, list) else []:
                    fp = str((c.get('input') or {}).get('file_path', '')) if c.get('name') == 'Read' else ''
                    if c.get('type') == 'tool_use' and fp.lower().endswith(tuple(e.decode() for e in exts)):
                        reads += 1
                        seen[fp] = seen.get(fp, 0) + 1
                        if seen[fp] > 3:
                            saved += 1
                            top[fp] = top.get(fp, 0) + 1
    except (OSError, ValueError):
        continue
print(f'     replay: {reads} image Reads in 7 d, {saved} denied at the 4th+ read of a path per context '
      f'({100 * saved / max(reads, 1):.0f} %, upper bound: re-renders are not in transcripts), {time.time() - t0:.1f} s')
for fp, n in sorted(top.items(), key=lambda kv: -kv[1])[:3]:
    print(f'       {n:4d} saved  {fp}')
check('replay: the hook would have saved calls', reads == 0 or saved > 0)

subprocess.run(['rm', '-rf', WORK])
print('PASS' if not bad else 'FAIL')
raise SystemExit(bad)
