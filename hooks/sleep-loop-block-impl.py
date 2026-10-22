#!/usr/bin/python3 -IS
"""Body of the sleep-loop-block.py PreToolUse hook: deny a hand-written Bash wait loop or a self-matching `pkill -f` and name the fix (TSP-040, T536, T735); hint the pc verb for a raw state change (T1047)."""
import sys

RAW = sys.stdin.buffer.read()
LOOP = b'sleep' in RAW and (b'until' in RAW or b'while' in RAW or b'for' in RAW)
KILL = b'pkill' in RAW or b'pgrep' in RAW
RAWT = b'pactl' in RAW or b'powerprofilesctl' in RAW or (b'systemctl' in RAW and (b'start' in RAW or b'stop' in RAW))
SHADOWT = b'grep' in RAW and b'{' in RAW or b'-newer' in RAW
APTT = b'apt' in RAW and (b'install' in RAW or b'remove' in RAW or b'purge' in RAW)
CDRMT = b'cd ' in RAW and b'rm ' in RAW
SUDOT = b'sudo' in RAW and (b' do' in RAW or b';do' in RAW or b'\\ndo' in RAW or b'xargs' in RAW)
if not (LOOP or KILL or RAWT or SHADOWT or APTT or CDRMT or SUDOT or b'"cwd"' in RAW):
    sys.exit(0)

import json, os, re

REASON = ('sleep-loop-block (AGENTS.md §3, TSP-040): hand-written wait loop denied. Run instead, as a '
          'run_in_background Bash call: `{}` (add --job <pid> when a job writes the file; '
          'guide: wait-for-and-stuck-loops).')
KILL_REASON = ('sleep-loop-block (KB/quirks.md, T536): a plain `-f` pattern also matches this Bash call\'s own '
               'shell, {}. Run instead: `{}` '
               '(the bracket keeps the regex from matching its own text; or use `pkill -x`/`killall` by name).')
OWN_REASON = ('sleep-loop-block (KB/quirks.md, T735): the `-f` pattern `{}` also matches `{}` elsewhere in this '
              'command, so it matches this Bash call\'s own shell, {}. Run the pkill as its '
              'own Bash call: `{}`.')
SELF_REASON = ('sleep-loop-block (KB/quirks.md, T735): the bracket in `-f` pattern `{}` still matches its own text, '
               'so it matches this Bash call\'s own shell, {}. Bracket a plain letter outside any class (`[a]pp-[0-9]*`, '
               'not `app-[0-9]*`), or use `pkill -x`/`killall` by name.')
HINT = 'pc-verb nudge (AGENTS.md §3, T1047): {}; pc verbs ledger every change (--apply, `pc undo <id>`).'
AUDIO = {'set-default-sink': 'pc audio default sink <name> --apply', 'set-default-source': 'pc audio default source <name> --apply',
         'set-sink-volume': 'pc audio vol <node> <0-150%|+N|-N> --apply',
         'set-source-volume': 'pc audio vol <node> <0-150%|+N|-N> --apply',
         'set-sink-mute': 'pc audio mute <node> on|off|toggle --apply',
         'set-source-mute': 'pc audio mute <node> on|off|toggle --apply',
         'move-sink-input': 'pc audio move <stream-id|app-name> <sink-name|earbuds|tv> --apply'}
PREFIX = re.compile(r'^(?:sudo|nice|timeout|env|exec|command|-\S*|\d+[smhd]?|\w+=\S*)$')
PREFIX_ARG = {'-u', '-g', '--user', '--group', '-s', '--signal', '-k', '--kill-after'}
KEYWORD = {'do', 'then', 'else', 'elif', 'if', 'while', 'until', 'time', '{', '!'}
READ_ONLY = ('list', 'get', 'info', 'stat', 'subscribe', 'version')
REMOTE = ('-H', '--host', '-M', '--machine')
SYSTEMCTL_ARG = {'-p', '--property', '-H', '--host', '-M', '--machine', '-t', '--type', '-n', '--lines', '-o', '--output',
                 '-s', '--signal', '--state', '--job-mode', '--kill-whom', '--root'}
GREP_HINT = ('ugrep shadow (KB/quirks.md, T1082): this shell\'s `grep` is ugrep, which can reject a bounded repeat after '
             'another repeat (`exceeds complexity limits`, exit 2; GNU grep takes it): use `command grep` or rg')
FIND_HINT = ('bfs shadow (KB/quirks.md, T1082): this shell\'s `find` is bfs, which takes only ISO dates or @epoch '
             '(`{}` → `Invalid timestamp`): use `command find` or `-newermt $(date -d \'-1 day\' +%F)`')
APT_HINT = 'pc-verb nudge (T1087): `{}` → `pc pkg {} {} --apply` (ledgered, `pc undo <id>`)'
CWD_REASON = ('cwd guard (KB/quirks.md, T1082): this shell\'s cwd `{}` was deleted, so every command fails with getcwd: '
              'start with `cd ~ &&`.')
CDRM_REASON = ('cwd guard (KB/quirks.md, T1082): this command cds into `{}` and then deletes `{}`, so the Bash tool\'s '
               'closing pwd fails (exit 1, getcwd: cannot access parent directories) even when every step worked. '
               'Leave first: `cd ~ && rm -rf {}`.')
BOUND = re.compile(r'(\.|\[\^?\]?[^\]]*\])(?:\\?\{(\d*),(\d+)\\?\}|(\\?[*+]))(?=(?:\\?\))*(\\?.)?)')
SUDO_HINT = ('sudo-loop nudge (T1147): `sudo` in a loop body or after xargs runs once per item, 3 journal lines each '
             '(11,606 calls in 2 min on 10-21); one root shell: `sudo -n bash -c \'…loop…\'` or '
             '`sudo -n find … -exec du -sk {} +`')
XARGS_ARG = {'-I', '-n', '-P', '-d', '-L', '-s', '-E', '-a', '--max-args', '--max-procs', '--delimiter', '--arg-file'}
ASSIGN = re.compile(r'^\w+=\S*$')
ISO = re.compile(r'^(\d{4}-\d\d-\d\d|@\d+$)')
EFFECT = {'pkill': 'which then dies with exit 144 and loses the rest of the command',
          'pgrep': 'which pgrep then reports as a false hit'}


def shell_words(cmd):
    """Words and operator tokens (; & | ( ) newline) of a shell command, quotes removed, heredoc bodies dropped."""
    toks, w, quoted, i, n, here = [], '', False, 0, len(cmd), []
    while i < n:
        c = cmd[i]
        if c in "'\"":
            j = cmd.find(c, i + 1)
            if j < 0:
                return None
            w, quoted, i = w + cmd[i + 1:j], True, j + 1
            continue
        if c == '\\' and i + 1 < n:
            w, i = w + cmd[i + 1], i + 2
            continue
        if c == '<' and cmd.startswith('<<', i) and not cmd.startswith('<<<', i):
            i += 2 + (cmd.startswith('-', i + 2))
            while i < n and cmd[i] in ' \t':
                i += 1
            j = i
            while j < n and cmd[j] not in ' \t\n;&|()<>':
                j += 1
            here.append(cmd[i:j].strip("'\""))
            i = j
            continue
        if c in ' \t\r;&|()\n':
            if w or quoted:
                toks.append(w)
            w, quoted = '', False
            if c not in ' \t\r':
                toks.append(c)
            if c == '\n':
                for d in here:
                    while i < n:
                        j = cmd.find('\n', i + 1)
                        j = n if j < 0 else j
                        line, i = cmd[i + 1:j].strip(), j
                        if line == d:
                            break
                here = []
            i += 1
            continue
        w, i = w + c, i + 1
    if w or quoted:
        toks.append(w)
    return toks


def matches(pat, text):
    """First match of pat as a regex in text, None when it does not match or does not compile."""
    try:
        m = re.search(pat, text)
    except (re.error, OverflowError):
        return None
    return m and m.group(0)


def bracket_letter(pat):
    """pat with its first letter or digit outside a [class] or escape wrapped in brackets, None when it has none."""
    inside, k = False, 0
    while k < len(pat):
        c = pat[k]
        if c == '\\':
            k += 2
            continue
        inside = (inside or c == '[') and c != ']'
        if not inside and c.isalnum():
            return pat[:k] + '[' + c + ']' + pat[k + 1:]
        k += 1
    return None


def self_kill(cmd):
    """Deny reason for the first `pkill`/`pgrep` -f whose pattern matches cmd's own text, else None."""
    toks = shell_words(cmd)
    if not toks:
        return None
    ops = set(';&|()\n')
    for i, t in enumerate(toks):
        if t not in ('pkill', 'pgrep') or not (i == 0 or toks[i - 1] in ops or toks[i - 1] == 'sudo'):
            continue
        full = exact = False
        j = i + 1
        while j < len(toks) and toks[j].startswith('-') and toks[j] not in ops:
            o = toks[j]
            if o.startswith('--'):
                full |= o == '--full'
                exact |= o == '--exact'
                j += 1 if '=' in o or o not in ('--signal', '--euid', '--uid', '--group', '--pgroup',
                                               '--parent', '--session', '--terminal', '--delimiter', '--ns') else 2
            else:
                full |= 'f' in o[1:]
                exact |= 'x' in o[1:]
                j += 2 if o[-1] in 'dgGPstuU' and len(o) == 2 else 1
        if not full or exact or j >= len(toks) or toks[j] in ops:
            continue
        pat = toks[j]
        if pat.startswith('^') or '$' in pat or '`' in pat:
            continue
        effect = EFFECT[t]
        if '[' in pat:
            if matches(pat, pat):
                fixed = bracket_letter(pat)
                if not fixed or matches(fixed, fixed):
                    return SELF_REASON.format(pat, effect)
                fix = ' '.join(toks[i:j] + ["'" + fixed.replace("'", "'\\''") + "'"])
                hit = matches(fixed, cmd.replace(pat, ''))
                return OWN_REASON.format(fixed, hit, effect, fix) if hit else KILL_REASON.format(effect, fix)
            hit = matches(pat, cmd)
            if hit:
                return OWN_REASON.format(pat, hit, effect, ' '.join(toks[i:j] + ["'" + pat.replace("'", "'\\''") + "'"]))
            continue
        alts, depth, start = [], 0, 0
        for n, c in enumerate(pat + '|'):
            depth += (c == '(') - (c == ')')
            if c == '|' and depth == 0 and pat[n - 1:n] != '\\':
                alts.append(pat[start:n])
                start = n + 1
        if not all(any(c.isalnum() for c in a) for a in alts):
            continue
        fixed = '|'.join(a[:k] + '[' + a[k] + ']' + a[k + 1:]
                         for a in alts for k in [next(n for n, c in enumerate(a) if c.isalnum())])
        fix = ' '.join(toks[i:j] + ["'" + fixed.replace("'", "'\\''") + "'"])
        hit = cmd.count(pat) > 1 and pat or matches(fixed, cmd.replace(pat, ''))
        return OWN_REASON.format(fixed, hit, effect, fix) if hit else KILL_REASON.format(effect, fix)
    return None


def raw_hint(cmd):
    """One-line pc-verb hint for each state-changing local pactl, powerprofilesctl or systemctl start|stop|restart at command position, else None."""
    toks = shell_words(cmd)
    if not toks:
        return None
    ops, out = set(';&|()\n'), []

    def head(k):
        """True when toks[k] is a separator or a shell keyword that itself starts a command."""
        return k < 0 or toks[k] in ops or toks[k] in KEYWORD and head(k - 1)

    for i, t in enumerate(toks):
        tool = os.path.basename(t)
        if tool not in ('pactl', 'powerprofilesctl', 'systemctl'):
            continue
        k = i - 1
        while k >= 0 and toks[k] not in ops and toks[k] not in KEYWORD and (
                PREFIX.match(toks[k]) or k > 0 and toks[k - 1] in PREFIX_ARG):
            k -= 1
        if not head(k):
            continue
        args, j = [], i + 1
        while j < len(toks) and toks[j] not in ops:
            args.append(toks[j])
            j += 1
        words, n = [], 0
        while n < len(args):
            a = args[n]
            n += 2 if tool == 'systemctl' and a in SYSTEMCTL_ARG else 1
            if not a.startswith('-'):
                words.append(a)
        sub = words[0] if words else ''
        if not sub or sub.startswith(READ_ONLY) or any(
                a in REMOTE or a.startswith(('--host=', '--machine=')) for a in args):
            continue
        if tool == 'pactl':
            verb = AUDIO.get(sub) or 'pc audio --help'
        elif tool == 'powerprofilesctl':
            verb = f'pc power profile {words[1] if len(words) > 1 else "<profile>"} --apply'
        elif sub in ('start', 'stop', 'restart'):
            mgr = ' --user' if '--user' in args else ' --system' if '--system' in args else ''
            verb = f'pc units {sub} {words[1] if len(words) > 1 else "<u>"}{mgr} --apply'
        else:
            continue
        line = f'`{" ".join([tool, sub]).strip()}` → `{verb}`'
        if line not in out:
            out.append(line)
    return HINT.format('; '.join(out[:3])) if out else None



def at_command(toks, i, prefix):
    """True when toks[i] starts a command, past words that prefix matches."""
    ops = set(';&|()\n')
    k = i - 1
    while k >= 0 and toks[k] not in ops and toks[k] not in KEYWORD and (
            prefix.match(toks[k]) or k > 0 and toks[k - 1] in PREFIX_ARG):
        k -= 1
    while k >= 0 and toks[k] in KEYWORD:
        k -= 1
    return k < 0 or toks[k] in ops


def args_of(toks, i):
    """Words after toks[i] up to the next operator token."""
    out = []
    for t in toks[i + 1:]:
        if t in ';&|()\n':
            break
        out.append(t)
    return out


def too_complex(pat, ere):
    """True when a top-level branch of pat has a bounded repeat {m,N} (N >= 16) after a 16+ or */+ repeat on . or a class (Claude Code 2.1.306's ugrep)."""
    branches, depth, start = [], 0, 0
    for m in re.finditer(r'\[\^?\]?[^\]]*\]|\\?[()|]', pat):
        t = m.group(0)[-1]
        if m.group(0)[0] == '[' or (len(m.group(0)) == 1) != ere:
            continue
        depth += (t == '(') - (t == ')')
        if t == '|' and depth == 0:
            branches.append(pat[start:m.start()])
            start = m.end()
    for branch in branches + [pat[start:]]:
        seen, end = 0, 0
        for m in BOUND.finditer(branch):
            w = float('inf') if m.group(4) else int(m.group(3))
            if m.group(3) and w >= 16 and seen >= 16 and not (w < 100 and re.search(r'[^\\.\[\](){}*+?|^$]{6}', branch[end:m.start()])):
                return True
            nxt = m.group(5) or ''
            if m.group(1) != '.' and len(nxt) == 1 and nxt not in '.[(|\\' and not matches(m.group(1), nxt):
                continue
            seen, end = max(seen, w), m.end()
    return False


def shadow_hints(toks):
    """ugrep/bfs gotcha hints for a bare `grep` or `find` at command position (the shell functions Claude Code defines)."""
    out = []
    for i, t in enumerate(toks):
        if t not in ('grep', 'find') or not at_command(toks, i, ASSIGN):
            continue
        args = args_of(toks, i)
        if t == 'grep':
            fixed = any(a in ('--fixed-strings', '--perl-regexp') or a[:1] == '-' and a[1:2] != '-' and (
                'F' in a or 'P' in a) for a in args)
            ere = any(a == '--extended-regexp' or a[:1] == '-' and a[1:2] != '-' and 'E' in a for a in args)
            if not fixed and any(too_complex(a, ere) for a in args) and GREP_HINT not in out:
                out.append(GREP_HINT)
            continue
        for a, v in zip(args, args[1:]):
            if re.match(r'^-newer[aBcm]t$', a) and not ISO.match(v) and '$' not in v:
                out.append(FIND_HINT.format(v))
                break
    return out


def apt_hint(toks):
    """pc pkg hint for a raw apt/apt-get install|remove|purge once ~/agents/bin/pc-pkg exists, else None."""
    for i, t in enumerate(toks):
        if os.path.basename(t) not in ('apt', 'apt-get') or not at_command(toks, i, PREFIX):
            continue
        words = [a for a in args_of(toks, i) if not a.startswith('-')]
        if words and words[0] in ('install', 'remove', 'purge'):
            if not os.path.exists(os.path.expanduser('~/agents/bin/pc-pkg')):
                return None
            sub = 'remove' if words[0] == 'purge' else words[0]
            return APT_HINT.format(f'{os.path.basename(t)} {words[0]}', sub, ' '.join(words[1:]) or '<pkg…>')
    return None


def cd_then_rm(toks):
    """Deny reason when the command cds into a dir and later rm -r's it (or a parent) with no cd after, else None."""
    norm = lambda p: re.sub(r'\$\{(\w+)\}', r'$\1', p).rstrip('/') or p
    depth, cur, hit = 0, None, None
    for i, t in enumerate(toks):
        depth += (t == '(') - (t == ')')
        if depth or not at_command(toks, i, PREFIX):
            continue
        args = args_of(toks, i)
        if t == 'cd':
            cur, hit = (norm(args[0]) if args else None), None
        elif t == 'rm' and cur and any(a == '--recursive' or a[:1] == '-' and a[1:2] != '-' and 'r' in a.lower()
                                       for a in args):
            for a in args:
                n = norm(a)
                if not a.startswith('-') and (cur == n or cur.startswith(n + '/')):
                    hit = (cur, n)
    return CDRM_REASON.format(hit[0], hit[1], hit[1]) if hit else None


def sudo_loop(toks):
    """True when a `sudo` starts a command inside a do…done body or is the command xargs runs."""
    depth = 0
    for i, t in enumerate(toks):
        if t in ('do', 'done') and at_command(toks, i, ASSIGN):
            depth = max(0, depth + (1 if t == 'do' else -1))
        elif depth and t.rsplit('`', 1)[-1] == 'sudo' and at_command(toks, i, PREFIX):
            return True
        elif t == 'xargs' and at_command(toks, i, PREFIX):
            args, j = args_of(toks, i), 0
            while j < len(args) and args[j].startswith('-'):
                j += 2 if args[j] in XARGS_ARG else 1
            if j < len(args) and args[j] == 'sudo':
                return True
    return False


try:
    d = json.loads(RAW)
    cmd = str((d.get('tool_input') or {}).get('command', '')) if d.get('tool_name') == 'Bash' else ''
    why = self_kill(cmd) if KILL and ('pkill' in cmd or 'pgrep' in cmd) else None
    if why:
        print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny',
                                                 'permissionDecisionReason': why}}))
    elif LOOP and 'sleep' in cmd:
        import importlib.util
        _s = importlib.util.spec_from_file_location(
            'wait_nudge', os.path.join(os.path.dirname(os.path.realpath(__file__)), 'wait_nudge.py'))
        nudge = importlib.util.module_from_spec(_s)
        _s.loader.exec_module(nudge)
        line = nudge.loop_wait(cmd)
        if line:
            print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny',
                                                     'permissionDecisionReason': REASON.format(line)}}))
            why = True
    cwd = d.get('cwd')
    toks = (shell_words(cmd) or []) if cmd and (SHADOWT or APTT or CDRMT or SUDOT) else []
    if not why:
        if cmd and isinstance(cwd, str) and cwd and not os.path.isdir(cwd) and not re.match(r'\s*cd\s+[/~]', cmd):
            why = CWD_REASON.format(cwd)
        elif CDRMT:
            why = cd_then_rm(toks)
        if why:
            print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny',
                                                     'permissionDecisionReason': why}}))
    if not why:
        hints = ([raw_hint(cmd)] if RAWT else []) + (shadow_hints(toks) if SHADOWT else []) + (
            [apt_hint(toks)] if APTT else []) + ([SUDO_HINT] if SUDOT and sudo_loop(toks) else [])
        hints = [h for h in hints if h]
        if hints:
            print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'additionalContext': '\n'.join(hints)}}))
except Exception:
    pass
sys.exit(0)
