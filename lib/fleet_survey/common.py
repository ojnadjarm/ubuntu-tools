"""Shared roots, the CLI seam and the helpers more than one fleet-survey section uses."""
import datetime, glob, os, re, statistics, subprocess, time

AG = os.environ.get('HARNESS_HOME') or os.path.expanduser('~/agents')
AW = os.environ.get('AGENT_WORK') or os.path.expanduser('~/agent-work')
SKILL_ROOTS = [os.path.join(AG, 'skills'), os.path.expanduser('~/.claude/skills')]
TIMEOUT = 25
TIMINGS = os.path.join(AG, 'state', 'test-timings-history.tsv')


class NA(Exception):
    pass


def run(*argv, ok=(0,)):
    exe = os.path.join(AG, 'bin', argv[0])
    if not os.access(exe, os.X_OK):
        raise NA(f'{argv[0]} not found in {AG}/bin')
    try:
        p = subprocess.run([exe, *argv[1:]], capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        raise NA(f'{" ".join(argv)} timed out after {TIMEOUT} s')
    if p.returncode not in ok:
        err = (p.stderr.strip().splitlines() or p.stdout.strip().splitlines() or [''])[-1]
        raise NA(f'{" ".join(argv)} rc {p.returncode}: {err[:120]}')
    return p.stdout.rstrip('\n').splitlines()


def seconds(since):
    m = re.fullmatch(r'(\d+)([mhd])', since)
    if not m:
        raise ValueError(since)
    return int(m.group(1)) * {'m': 60, 'h': 3600, 'd': 86400}[m.group(2)]


def latest(pattern):
    files = glob.glob(pattern)
    if not files:
        raise NA(f'no {pattern.replace(os.path.expanduser("~"), "~")}')
    return max(files, key=os.path.getmtime)


def short(p):
    return p.replace(os.path.expanduser('~'), '~')


def when(iso):
    try:
        return datetime.datetime.fromisoformat(iso).astimezone()
    except (TypeError, ValueError):
        return None


def age(t):
    """`<n> m|h|d old` for an epoch."""
    s = max(0, time.time() - t)
    return f'{s / 60:.0f} m old' if s < 3600 else f'{s / 3600:.0f} h old' if s < 172800 else f'{s / 86400:.0f} d old'


def epoch(iso, path):
    w = when(iso)
    return w.timestamp() if w else os.path.getmtime(path)


def test_base(name):
    """A test file's tool stem: `test_x.py`, `x.test.sh` and `x.sh` all give `x`."""
    return re.sub(r'^test_|\.test\.\w+$|\.\w+$', '', name)


def _code(p):
    return os.path.isfile(p) and '.test.' not in p and '__pycache__' not in p and p.endswith(('.py', '.sh', '.js'))


def scripts():
    """Executables in bin/ and skill dirs, plus .py/.sh/.js in lib/, hooks/, adapters/*/hooks/ (symlinks de-duplicated)."""
    out = [p for p in glob.glob(os.path.join(AG, 'bin', '*'))
           if os.path.isfile(p) and os.access(p, os.X_OK)]
    out += [p for d in ('lib', 'hooks', 'adapters/*/hooks') for p in glob.glob(os.path.join(AG, d, '*')) if _code(p)]
    seen = set()
    for root in SKILL_ROOTS:
        for p in glob.glob(os.path.join(root, '*', '**', '*'), recursive=True):
            real = os.path.realpath(p)
            if real in seen or '/tests/' in p or '/node_modules/' in p or '/synced/' in p:
                continue
            if os.path.isfile(p) and os.access(p, os.X_OK):
                seen.add(real)
                out.append(p)
    return out


def p50(cmd, n, env=None, stdin=None, timeout=10):
    """Median wall ms of n runs of cmd, every run's ms and the last rc."""
    ms, rc = [], 0
    for _ in range(n):
        t = time.time()
        try:
            rc = subprocess.run(cmd, input=stdin, capture_output=True, text=True, env=env, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            rc = 'timeout'
        ms.append(int(1000 * (time.time() - t)))
    return statistics.median(ms), ms, rc
