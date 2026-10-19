"""Shared reader for logrotated jsonl logs (live file plus moodle-keep's .N.gz rotations)."""
import gzip, json, os, re, shlex, time


def row_stamp(row):
    """Epoch of a row's local 'ts' stamp, or None when it has none."""
    try:
        return time.mktime(time.strptime(row['ts'][:19], '%Y-%m-%dT%H:%M:%S'))
    except (ValueError, KeyError, TypeError):
        return None


def _rows(p):
    """Parsed rows of one plain or gzipped jsonl file; bad lines skipped."""
    rows = []
    with (gzip.open(p, 'rt') if p.endswith('.gz') else open(p)) as f:
        for line in f:
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue
    return rows


def rotated_rows(path, cut):
    """Rows oldest first: live file, then each .N.gz until one starts before cut (cut 0 = live only)."""
    chunks, p, n = [], path, 1
    while os.path.exists(p):
        rows = _rows(p)
        chunks.append(rows)
        start = next((t for t in map(row_stamp, rows) if t is not None), None)
        if not cut or (start is not None and start < cut):
            break
        p, n = f'{path}.{n}.gz', n + 1
    return [r for c in reversed(chunks) for r in c]


# (raw tool, subcommand) -> (class, pc verb); '*' is any other subcommand of that tool.
# covered: a pc verb does it; by-design: raw is correct (pc refuses it); gap: no verb yet.
RAW_MAP = {
    ('tailscale', 'status'): ('covered', 'pc net tailscale'),
    ('tailscale', 'serve'): ('by-design', None),
    ('tailscale', '*'): ('gap', None),
    ('systemctl', 'restart'): ('covered', 'pc units restart'),
    ('systemctl', 'stop'): ('covered', 'pc units stop'),
    ('docker', 'restart'): ('covered', 'pc docker restart'),
    ('pactl', '*'): ('covered', 'pc audio'),
    ('wpctl', '*'): ('covered', 'pc audio'),
    ('powerprofilesctl', '*'): ('covered', 'pc power profile'),
    ('nmcli', '*'): ('gap', None),
    ('brightnessctl', '*'): ('gap', None),
}
RAW_TOOLS = {t for t, _ in RAW_MAP}
SEGMENT = re.compile(r'&&|\|\||;|\|')


def raw_call(row):
    """(label, class, pc verb) when a Bash row's op starts with a raw tool, else None."""
    op = (row.get('op') or '').split() if row.get('tool') == 'Bash' else []
    if not op or op[0] not in RAW_TOOLS:
        return None
    words = op[1:]
    for seg in SEGMENT.split(row.get('summary') or ''):
        w = seg.split()
        if w and os.path.basename(w[0]) == op[0]:
            words = w[1:]
            break
    sub = next((w for w in words if not w.startswith('-')), '')
    if (op[0], sub) in RAW_MAP:
        return (f'{op[0]} {sub}',) + RAW_MAP[(op[0], sub)]
    if (op[0], '*') in RAW_MAP:
        return (op[0],) + RAW_MAP[(op[0], '*')]
    return None


def outcome_rows(rows):
    """Rows from the first one with a logged outcome ('ok'), the window a failure rate is clamped to."""
    return rows[next((i for i, r in enumerate(rows) if 'ok' in r), len(rows)):]


def row_kind(row):
    """'bench' for pcbench trials, 'agent' for rostered agent runs, else 'interactive'."""
    agent = row.get('agent') or ''
    if agent == 'bench' or '/bench/runs/' in (row.get('cwd') or ''):
        return 'bench'
    return 'agent' if agent else 'interactive'


FOLD = ((re.compile(r'https?://\S+'), '<url>'), (re.compile(r'(?:~|\.{1,2})?/[^\s:\'"]+'), '<path>'),
        (re.compile(r'\b(?=\w*\d)(?=\w*[a-zA-Z])\w{6,}\b'), '<id>'), (re.compile(r'\d+'), 'N'),
        (re.compile(r'\s+'), ' '))
# Known error lines, most specific first: (pattern, cluster text). A hit names the error on its own.
SIGNALS = (
    (re.compile(r'\S+: command not found'), 'command not found'),
    (re.compile(r'(\S+): refused inside the (\S+) sandbox'), r'\1: refused inside the \2 sandbox'),
    (re.compile(r'sudo: a password is required'), 'sudo: a password is required'),
    (re.compile(r'getcwd: cannot access parent directories|error retrieving current directory'),
     'cwd was deleted (getcwd)'),
    (re.compile(r'\b(error TS\d+)'), r'\1'),
    (re.compile(r'npm (?:ERR!|error) code (\S+)'), r'npm error \1'),
    (re.compile(r'^([A-Z]\w*(?:Error|Exception))\b'), r'\1'),
    (re.compile(r'Permission denied'), 'Permission denied'),
    (re.compile(r'No such file or directory'), 'No such file or directory'),
    (re.compile(r'^[Uu]sage: (\S+)'), r'usage: \1'),
    (re.compile(r'^FAIL\b|FAIL\s*[—-]'), 'test FAIL'),
)
EXITS = {'97': 'refused inside the code-review sandbox', '124': 'timed out', '126': 'not executable',
         '127': 'command not found', '137': 'killed (SIGKILL)', '143': 'killed (SIGTERM)'}
DIAG = re.compile(r"(?i)^(?:\[[^\]]*\]\s*|[\w.-]+: )*(?:error|fatal|cannot|can't|failed|unable)\b|\bError: ")
HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)")
SHELL_WORDS = {'done', 'fi', 'esac', 'then', 'else', 'do', '{', '}', '(', ')', 'true'}


def fold(line):
    """One output line with urls, paths, ids and digits folded, cut to 70 chars."""
    for rx, to in FOLD:
        line = rx.sub(to, line)
    return line.strip()[:70]


def signal(lines, code):
    """(text, known) for the line that names the error: known pattern, known exit code, last diagnostic line."""
    for rx, to in SIGNALS:
        for line in reversed(lines):
            m = rx.search(line)
            if m:
                return m.expand(to), True
    if code in EXITS:
        return EXITS[code], True
    hit = next((l for l in reversed(lines) if DIAG.search(l)), None)
    return (fold(hit) if hit else None), False


def last_command(cmd):
    """Words of the command whose status a shell line returns (after the last ; && || or newline), None if unsure."""
    if len(cmd) >= 500:
        return None
    kept, end = [], None
    for line in cmd.split('\n'):
        if end:
            end = None if line.strip() == end else end
            continue
        h = HEREDOC.search(line)
        end = h[1] if h else None
        kept.append(line)
    try:
        toks = list(shlex.shlex(' ; '.join(kept), posix=True, punctuation_chars=True))
    except ValueError:
        return None
    segs, cur = [], []
    for t in toks:
        if t in (';', '&&', '||', '&', ';;'):
            segs, cur = segs + [cur], []
        elif t == '|':
            cur = []
        else:
            cur.append(t)
    segs = [s for s in segs + [cur] if s and s[0] not in SHELL_WORDS]
    return segs[-1] if segs else None


def error_cluster(row):
    """'cmd · exit N · error' of a failed row: the command that set the status and the line naming the error."""
    op = (row.get('tool') == 'Bash' and last_command(row.get('summary') or '')) or \
        (row.get('op') or row.get('tool') or '?').split() or ['?']
    cmd = os.path.basename(op[0]) or op[0]
    head = f'pc {op[1]}' if cmd == 'pc' and len(op) > 1 else cmd
    lines = [l for l in (row.get('error') or '').splitlines() if l.strip()]
    m = re.fullmatch(r'Exit code (\d+)', lines[0].strip()) if lines else None
    code = [f'exit {m[1]}'] if m else []
    sig, known = signal(lines[1:] if m else lines, m and m[1])
    if known:
        return ' · '.join(code + [sig])
    if not sig and not m and lines:
        sig = fold(lines[0])
    return ' · '.join([head] + code + ([sig] if sig else []))


PROBES = {'test', '[', '[[', 'which'}
PROBE_FLAGS = {'grep': ('-q', '--quiet', '-qs', '-sq'), 'diff': ('-q', '--brief'), 'cmp': ('-s', '--silent'),
               'command': ('-v',)}
RED_FIRST = re.compile(r'\.test\.(?:sh|py)\b')


def error_class(row):
    """'guarded' (sandbox refusal), 'probe' (a yes/no check answering no), 'red-first' (a test run failing) or 'real'."""
    key = error_cluster(row)
    if 'exit 97' in key or 'refused inside' in key:
        return 'guarded'
    m = re.match(r'Exit code (\d+)', row.get('error') or '')
    cmd = (row.get('tool') == 'Bash' and last_command(row.get('summary') or '')) or []
    name = os.path.basename(cmd[0]) if cmd else ''
    flags = PROBE_FLAGS.get(name, ())
    if m and (m[1] == '1' and (name in PROBES or any(f in cmd[1:] for f in flags))
              or m[1] in ('1', '3') and name == 'systemctl'
              and any(w in ('is-active', 'is-enabled', 'is-failed') for w in cmd[1:])):
        return 'probe'
    if key.endswith('test FAIL') and RED_FIRST.search(row.get('summary') or ''):
        return 'red-first'
    return 'real'
