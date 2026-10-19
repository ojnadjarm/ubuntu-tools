#!/usr/bin/env python3
"""Spot hand-written wait loops in a Bash command and suggest the exact `wait-for` equivalent (T376)."""
import glob, gzip, json, os, re, shlex, sys, time

LOOP = re.compile(r'\b(until|while)\s+([^;]+?);\s*do\s+(.{1,1000}?)\s*;?\s*done\b', re.S)
POLL = re.compile(r'\b(?:while\s+(?:true|:)|for\s+\w+\s+in\s+[^;]+);\s*do\s+(.{1,1000}?)\s*;?\s*done\b', re.S)
SLEEP_ONLY = re.compile(r'sleep\s+[\d.]+[smh]?')
BREAK = re.compile(r'(?:^|;|\bdo\b|\bthen\b)\s*(?:if\s+(.+?);\s*then\s+break|(.+?)\s*&&\s*break)\b', re.S)
PLAIN_SLEEP = re.compile(r'^(?:(?:cd|export)\s[^;&|]*(?:;|&&)\s*)*sleep\s+(\d+)\b|(?<!&)&\s*sleep\s+(\d+)\b')
PID = re.compile(r'^!\s*(?:kill\s+-0|ps\s+-p)\s+(\S+)(?:\s+[0-9]?>\s*/dev/null|\s+2>&1)*$')
GREP = re.compile(r'^grep\s+-(q[a-zA-Z]*|[a-zA-Z]*q[a-zA-Z]*)\s+(\S+|"[^"]*"|\'[^\']*\')\s+(\S+?)(?:\s+2>\s*/dev/null)?$')
PGREP = re.compile(r'(pgrep\s+(?:-\w+\s+)*)(["\']?)([A-Za-z0-9])([^"\'\s]*)\2')
SHELL_C = re.compile(r'(?:\b(?:ba|z|da)?sh\s+(?:-[a-z]+\s+)*-[a-z]*c|\beval)\s*$')
HEREDOC = re.compile(r'(?<!<)<<(?!<)-?\s*([\'"]?)(\w+)\1')
PLAIN_MIN = 10
HINT = ('wait-nudge (AGENTS.md §3): hand-written wait seen. Next time, in a run_in_background Bash call: `{}`'
        ' (add --job <pid> when a job writes it; guide: wait-for-and-stuck-loops).')
PLAIN = ('wait-nudge (AGENTS.md §3): `sleep {}` is a blind wait. Wait on the condition instead, in a '
         'run_in_background Bash call: `wait-for --label wait --pid PID`, `--file LOG --match RE --job PID` '
         'or `--until \'COND\'`.')


def _unquote(s):
    return s[1:-1] if len(s) > 1 and s[0] == s[-1] and s[0] in '"\'' else s


def equivalent(target):
    """The wait-for command that waits until the shell condition `target` holds."""
    target = target.strip()
    m = PID.match(target)
    if m:
        return f'wait-for --label wait --pid {m.group(1)}'
    m = GREP.match(target)
    if m:
        pat = _unquote(m.group(2))
        if 'E' not in m.group(1):
            pat = pat.replace('\\|', '|')
        return f'wait-for --label wait --file {m.group(3)} --match {shlex.quote(pat)}'
    target = PGREP.sub(lambda p: f"{p.group(1)}'[{p.group(3)}]{p.group(4)}'"
                       if not p.group(3) == '[' else p.group(0), target)
    return f'wait-for --label wait --until {shlex.quote(target)}'


def _negate(cond):
    cond = cond.strip()
    return cond[1:].strip() if cond.startswith('!') else '! ' + cond


def code_mask(cmd):
    """Per character of `cmd`: True when the shell runs it, False inside heredoc bodies and quoted data."""
    mask, i, n, skip = [True] * len(cmd), 0, len(cmd), {}
    while i < n:
        if i in skip:
            i = skip.pop(i)
            continue
        c = cmd[i]
        if c == '\\':
            i += 2
            continue
        if c in '"\'':
            end = i + 1
            while end < n and cmd[end] != c:
                end += 2 if c == '"' and cmd[end] == '\\' else 1
            if not SHELL_C.search(cmd[max(0, i - 40):i]):
                mask[i:end + 1] = [False] * (min(end, n - 1) + 1 - i)
            i = end + 1
            continue
        h = HEREDOC.match(cmd, i)
        if h:
            start = cmd.find('\n', h.end())
            if start < 0:
                break
            tag = re.compile(r'^\t*' + re.escape(h.group(2)) + r'$', re.M)
            e = tag.search(cmd, start + 1)
            stop = e.start() if e else n
            mask[start:stop] = [False] * (stop - start)
            skip[start] = stop
            i = h.end()
            continue
        i += 1
    return mask


def loop_wait(cmd):
    """The wait-for line replacing a hand-written wait loop the shell would run in `cmd`, or None."""
    if not cmd or 'wait-for' in cmd or 'sleep' not in cmd:
        return None
    mask = code_mask(cmd)
    for m in LOOP.finditer(cmd):
        kind, cond, body = m.groups()
        if mask[m.start()] and SLEEP_ONLY.fullmatch(body.strip().rstrip(';').strip()) \
                and cond.strip() not in ('true', ':'):
            return equivalent(cond if kind == 'until' else _negate(cond))
    for m in POLL.finditer(cmd):
        if not mask[m.start()]:
            continue
        body = m.group(1)
        b = BREAK.search(body)
        if b and re.search(r'\bsleep\s', body):
            return equivalent((b.group(1) or b.group(2)).strip())
    return None


def hint(cmd):
    """One-line nudge for a hand-written wait in `cmd`, or None."""
    if not cmd or 'wait-for' in cmd or 'sleep' not in cmd:
        return None
    line = loop_wait(cmd)
    if line:
        return HINT.format(line)
    if LOOP.search(cmd) or POLL.search(cmd):
        return None
    secs = [int(a or b) for a, b in PLAIN_SLEEP.findall(cmd.strip())]
    if secs and max(secs) >= PLAIN_MIN:
        return PLAIN.format(max(secs))
    return None


def share(records):
    """(wait-for calls, hand-written waits, wait-for share %) over audit records."""
    wf = hand = 0
    for r in records:
        if r.get('tool') != 'Bash':
            continue
        s = r.get('summary', '')
        if re.search(r'(?:^|[;&|(\s])wait-for\s+--', s):
            wf += 1
        elif hint(s):
            hand += 1
    return wf, hand, round(100 * wf / (wf + hand), 1) if wf + hand else 0.0


def _records(days, since=''):
    cut = since or time.strftime('%Y-%m-%dT%H:%M', time.localtime(time.time() - days * 86400))
    log = os.path.join(os.environ.get('HARNESS_HOME') or os.path.expanduser('~/agents'), 'log', 'actions.jsonl')
    for p in sorted(glob.glob(log + '*')):
        with (gzip.open(p, 'rt') if p.endswith('.gz') else open(p)) as f:
            for line in f:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if r.get('ts', '') >= cut:
                    yield r


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--share':
        arg = sys.argv[2] if len(sys.argv) > 2 else '14'
        wf, hand, pct = share(_records(0, arg) if 'T' in arg or '-' in arg else _records(float(arg)))
        print(f'wait-for {wf} · hand-written {hand} · share {pct}%')
    else:
        print('usage: wait_nudge.py --share [DAYS|SINCE-ISO]', file=sys.stderr)
        sys.exit(2)
