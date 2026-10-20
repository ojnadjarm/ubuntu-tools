#!/usr/bin/python3 -IS
"""Body of the sleep-loop-block.py PreToolUse hook: deny a hand-written Bash wait loop or a self-matching `pkill -f` and name the fix (TSP-040, T536, T735)."""
import sys

RAW = sys.stdin.buffer.read()
LOOP = b'sleep' in RAW and (b'until' in RAW or b'while' in RAW or b'for' in RAW)
KILL = b'pkill' in RAW or b'pgrep' in RAW
if not (LOOP or KILL):
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
except Exception:
    pass
sys.exit(0)
