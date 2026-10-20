"""### flaky: red<->green flips whose inputs are all older than the runs."""
import glob, os, re, time

from .common import AG, NA, TIMINGS, seconds, short, test_base, when

GENERATED = re.compile(r'/(node_modules|__pycache__|\.[^/]+|out|outputs?|cache|build|dist|tmp)/|\.(pyc|log)$')


def _bin_refs(paths):
    """Top-level ~/agents/bin files named by a word in the given files, one hop deep (a test's tools, then their libs)."""
    b = os.path.join(AG, 'bin')
    names = {n for n in os.listdir(b) if os.path.isfile(os.path.join(b, n))}
    seen, todo = set(), list(paths)
    for depth in (0, 1):
        found = set()
        for p in todo:
            try:
                found |= names & set(re.findall(r'[\w.+-]+', open(p, errors='replace').read()))
            except OSError:
                pass
        todo = [os.path.join(b, n) for n in found - seen]
        seen |= found
    return [os.path.join(b, n) for n in seen]


def _input_mtimes(rel):
    """Mtimes of a test file and what it tests: bin/tests/<x>.test.* -> bin/<x>*, <dir>/tests/* -> the non-generated files under
    <dir>, else <x>* beside it; plus any bin file a word in the test (or in those tools) names."""
    path = os.path.join(AG, rel)
    head, name = os.path.split(path)
    base = test_base(name)
    if os.path.basename(head) == 'tests' and os.path.dirname(head) != os.path.join(AG, 'bin'):
        root = os.path.dirname(head)
        files = [p for p in glob.glob(os.path.join(root, '**', '*'), recursive=True) if not GENERATED.search('/' + os.path.relpath(p, root))]
    else:
        tool_dir = os.path.dirname(head) if os.path.basename(head) == 'tests' else head
        files = [path] + glob.glob(os.path.join(tool_dir, glob.escape(base) + '*'))
    files += _bin_refs([path] + [f for f in files if f != path and os.path.dirname(f) == os.path.join(AG, 'bin')])
    return [os.path.getmtime(p) for p in set(files) if os.path.isfile(p)]


def _last_red(rel):
    """First FAIL line (else first line) of the newest record in state/test-fails/<rel, / as __>.txt (run.sh), 100 chars."""
    try:
        with open(os.path.join(AG, 'state', 'test-fails', rel.replace('/', '__') + '.txt')) as fh:
            rec = fh.read().rsplit('\n## ', 1)[-1].split('\n')[1:]
    except OSError:
        return ''
    rec = [x.removeprefix('  | ') for x in rec if x.strip()]
    return next((x for x in rec if re.search(r'\bFAIL', x)), rec[0] if rec else '')[:100]


def rows(ctx):
    """Files of state/test-timings-history.tsv whose rc flipped red<->green in the window (--since, else 7d). Only current input
    mtimes are known: a flip is flaky only when every input is older than its first run, dev when one changed between the runs,
    else unsure (an input changed later and may hide an edit between)."""
    if not os.path.isfile(TIMINGS):
        raise NA(f'no {short(TIMINGS)}')
    cutoff = time.time() - seconds(ctx.flaky_since)
    runs = {}
    with open(TIMINGS) as fh:
        for r in fh:
            r = r.rstrip('\n').split('\t')
            w = when(r[0]) if len(r) >= 5 and re.fullmatch(r'-?\d+', r[3]) else None
            if w and w.timestamp() >= cutoff:
                runs.setdefault(r[1], []).append((w.timestamp(), r[3] != '0', r[4]))
    out, dev, unsure = [], 0, 0
    for rel, v in sorted(runs.items()):
        v.sort()
        flips = [(x, y) for x, y in zip(v, v[1:]) if x[1] != y[1]]
        if not flips:
            continue
        mt = _input_mtimes(rel)
        real = [(x, y) for x, y in flips if all(m <= x[0] for m in mt)]
        d = sum(any(x[0] < m <= y[0] for m in mt) for x, y in flips)
        dev, unsure = dev + d, unsure + len(flips) - len(real) - d
        if real:
            reds = sorted({r for p in real for r in p if r[1]})
            last = _last_red(rel)
            out.append(f'{rel}  red {sum(r[1] for r in v)} / runs {len(v)}, flips {len(real)}, last '
                       f'{time.strftime("%m-%d %H:%M", time.localtime(real[-1][1][0]))}, load at red {"/".join(r[2] for r in reds[-3:])}'
                       + (f'  last red: {last}' if last else ''))
    return [f'{len(out)} flaky, {dev} dev flips (an input changed between the runs), {unsure} unsure (an input changed since) '
            f'in {ctx.flaky_since}'] + out
