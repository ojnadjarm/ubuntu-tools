#!/usr/bin/env python3
"""sleep-loop-block PreToolUse hook on fixture commands, then a replay of 7 days of real Bash commands.
Run: python3 sleep-loop-block.test.py"""
import glob, gzip, importlib.util, json, os, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.realpath(__file__))
HOOK = os.path.join(HERE, 'sleep-loop-block.py')
IMPL = os.path.join(HERE, 'sleep-loop-block-impl.py')
_s = importlib.util.spec_from_file_location('wait_nudge', os.path.join(HERE, 'wait_nudge.py'))
w = importlib.util.module_from_spec(_s)
_s.loader.exec_module(w)
sys.path.insert(0, os.path.join(HERE, '..', 'bin', 'tests', 'lib'))
from budget import budget
WORK = tempfile.mkdtemp(prefix='slb-')
ENV = dict(os.environ, HOME=WORK, HARNESS_HOME=WORK)
bad = 0


def check(name, ok):
    global bad
    print(('ok   ' if ok else 'FAIL ') + name)
    bad |= not ok


def event(cmd, tool='Bash'):
    return json.dumps({'hook_event_name': 'PreToolUse', 'tool_name': tool,
                       'tool_input': {'command': cmd}, 'agent_id': 'a1'})


SPAWNED = {}


def run(cmd, tool='Bash', raw=None):
    """(exit code, parsed stdout or None) of the hook fed one PreToolUse event."""
    ev = raw if raw is not None else event(cmd, tool)
    p = subprocess.run([HOOK], input=ev, capture_output=True, text=True, env=ENV, cwd=WORK, timeout=10)
    res = p.returncode, (json.loads(p.stdout) if p.stdout.strip() else None)
    if raw is None and tool == 'Bash':
        SPAWNED[cmd] = res
    return res


# Runs the impl file's code once per event inside one process (stdin swapped, exit caught).
BATCH = r"""
import io, json, sys
from contextlib import redirect_stdout
code = compile(open(sys.argv[1]).read(), sys.argv[1], 'exec')
evs, res = [json.loads(l) for l in sys.stdin], []
for ev in evs:
    sys.stdin, out, rc = io.TextIOWrapper(io.BytesIO(ev.encode())), io.StringIO(), 0
    with redirect_stdout(out):
        try:
            exec(code, {'__name__': '__main__', '__file__': sys.argv[1]})
        except SystemExit as e:
            rc = e.code or 0
    res.append([rc, out.getvalue()])
print(json.dumps(res))
"""


def run_many(cmds):
    """run() for many commands in one process: [(exit code, parsed stdout or None)]."""
    p = subprocess.run([sys.executable, '-c', BATCH, IMPL], input=''.join(json.dumps(event(c)) + '\n' for c in cmds),
                       capture_output=True, text=True, env=ENV, cwd=WORK, timeout=120)
    return [(rc, json.loads(o) if o.strip() else None) for rc, o in json.loads(p.stdout)]


def denied_many(cmds):
    """denied() for many commands in one process."""
    out = []
    for rc, res in run_many(cmds):
        o = (res or {}).get('hookSpecificOutput', {})
        out.append((rc == 0 and o.get('permissionDecision') == 'deny', o.get('permissionDecisionReason', '')))
    return out


def denied(cmd):
    rc, out = run(cmd)
    o = (out or {}).get('hookSpecificOutput', {})
    return rc == 0 and o.get('permissionDecision') == 'deny', o.get('permissionDecisionReason', '')


# Selftest: the hook only reads stdin; it never runs the command it judges.
for cmd in [f'until [ -e {WORK}/x ]; do sleep 1; done; touch {WORK}/must-not-exist',
            f'touch {WORK}/must-not-exist-2; sleep 1']:
    run(cmd)
check('selftest: hook never executes the command',
      not os.path.exists(f'{WORK}/must-not-exist') and not os.path.exists(f'{WORK}/must-not-exist-2'))

DENY = [
    ('until grep -q "^exit" run.log; do sleep 3; done; cat run.log', "wait-for --label wait --file run.log --match '^exit'"),
    ('cd /x && until grep -q "ALL DONE" done.txt; do sleep 15; done', "wait-for --label wait --file done.txt --match 'ALL DONE'"),
    ('S=/tmp/a; until [ -s $S/o.log ] && grep -q ok $S/o.log; do sleep 5; done', "wait-for --label wait --until '[ -s $S/o.log ] && grep -q ok $S/o.log'"),
    ('while kill -0 4242 2>/dev/null; do sleep 5; done; echo done', 'wait-for --label wait --pid 4242'),
    ('while ! grep -q "^rc=" $f; do sleep 5; done', "wait-for --label wait --file $f --match '^rc='"),
    ('until curl -sf localhost:8080/health; do sleep 2; done', "wait-for --label wait --until 'curl -sf localhost:8080/health'"),
    ('for i in $(seq 30); do curl -sf x && break; sleep 2; done', "wait-for --label wait --until 'curl -sf x'"),
    ("timeout 590 bash -c 'until grep -q \"^EXIT\" out/make.log; do sleep 5; done'; tail -5 out/make.log",
     "wait-for --label wait --file out/make.log --match '^EXIT'"),
    ('f=x.log; timeout 500 bash -c "while ! grep -q \'^rc=\' $f; do sleep 5; done"; tail -6 $f',
     "wait-for --label wait --file $f --match '^rc='"),
]
for cmd, want in DENY:
    ok, reason = denied(cmd)
    check(f'deny {cmd[:55]!r}', ok and f'`{want}`' in reason or print('     got', reason))

PASS = [
    'sleep 1', 'sleep 1; ls', 'kill 7301; sleep 1; cat x', 'sleep 120; cat tasks/b1.output', 'watch -n 2 ls',
    "wait-for --label b --until '[ -e f ]'", 'wait-for --label b --pid 1; sleep 30',
    'for f in *.log; do grep -c x $f; sleep 1; done', 'while read f; do echo $f; sleep 1; done < list',
    "echo 'until [ -e f ]; do sleep 1; done'", "grep -n 'until x; do sleep 1; done' notes.md",
    "cat > wait.sh <<'EOF'\nuntil grep -q RC= ci.log; do sleep 20; done\nEOF\necho ok",
    'echo \'{"tool_input":{"command":"until [ -e /etc/hostname ]; do sleep 1; done"}}\' | ./audit-log.py',
    'claude -p "Step 1: run this exact Bash command: until [ -e /etc/hostname ]; do sleep 1; done"',
    'python3 - <<EOF\ncmd = "eval \'until grep -q X f; do sleep 5; done\'"\nEOF',
    'ls -la', '',
]
for cmd in PASS:
    rc, out = run(cmd)
    check(f'pass {cmd[:55]!r}', rc == 0 and out is None or print('     got', rc, out))
KILL_DENY = [
    ("pkill -f 'wait-for --label x'", "pkill -f '[w]ait-for --label x'"),
    ('pgrep -f vite | xargs kill', "pgrep -f '[v]ite'"),
    ("kill $(pgrep -f 'node server.js') 2>&1; echo done", "pgrep -f '[n]ode server.js'"),
    ('pkill --full http.server', "pkill --full '[h]ttp.server'"),
    ('ls; sudo pkill -9 -f ollama || true', "pkill -9 -f '[o]llama'"),
    ("pgrep -af 'remotion render'", "pgrep -af '[r]emotion render'"),
    ("pgrep -af 'make.sh|ffmpeg' | grep -v grep", "pgrep -af '[m]ake.sh|[f]fmpeg'"),
    ("pgrep -af 'Caddyfile\\.(a|b)'", "pgrep -af '[C]addyfile\\.(a|b)'"),
]
for cmd, want in KILL_DENY:
    ok, reason = denied(cmd)
    check(f'deny {cmd[:55]!r}', ok and f'`{want}`' in reason or print('     got', reason))

# T735: a bracketed (or fixed) pattern that still matches another literal of the same command.
KILL_OWN = [
    ("pkill -f '[m]v-fog.test'; cd t && python3 - <<'PY'\np=\"mv-fog.test.sh\"\nPY", "pkill -f '[m]v-fog.test'"),
    ("pkill -f '[t]imeout 120 godot --path /x/T703' ; pkill -f '[g]odot --path /x/T703'; ls",
     "pkill -f '[g]odot --path /x/T703'"),
    ("pkill -f '[b]fv37id22' ; pkill -f '[s]tate settings --tab'; godot --path . -- --state settings --tab audio",
     "pkill -f '[s]tate settings --tab'"),
    ('pkill -f vite; echo vite done', "pkill -f '[v]ite'"),
]
for cmd, want in KILL_OWN:
    ok, reason = denied(cmd)
    check(f'deny own-call {cmd[:48]!r}', ok and f'own Bash call: `{want}`' in reason or print('     got', reason))

# T735: a bracket that still matches its own text gets the moved-bracket fix, never the own-call advice.
KILL_SELF = [
    ("pkill -f 'foo[0-9]*'", "`pkill -f '[f]oo[0-9]*'`"),
    ("pkill -f 'app-[0-9]*'", "`pkill -f '[a]pp-[0-9]*'`"),
    ("pkill -f 'foo[0-9]*'; echo foo1", "own Bash call: `pkill -f '[f]oo[0-9]*'`"),
    ("pkill -f '[x]'", 'Bracket a plain letter outside any class'),
    ("pgrep -f 'app-[0-9]*'", 'reports as a false hit'),
]
for cmd, want in KILL_SELF:
    ok, reason = denied(cmd)
    check(f'deny self-bracket {cmd[:44]!r}', ok and want in reason and f'own Bash call: `{cmd}`' not in reason
          or print('     got', reason))
for cmd in ("pkill -f '[f]oo[0-9]*'", "pkill -f '[a]pp-[0-9]*'"):
    rc, out = run(cmd)
    check(f'pass the suggested fix {cmd!r}', rc == 0 and out is None or print('     got', rc, out))

KILL_PASS = [
    "pkill -f '[w]ait-for --label x'", "pkill -f '[m]v-fog.test'; echo done", "pgrep -af '[g]odot|[w]eston' | head", 'pkill -x chrome', 'killall gnome-calculator', 'pc app close gnome-calculator',
    "pkill -fx 'python3 -m http.server'", "pkill -f '^python3 serve.py'", 'pkill -f "$NAME"',
    "echo 'pkill -f foo'", "grep -n 'pkill -f' KB/quirks.md", "cat > s.sh <<'EOF'\npkill -f foo\nEOF\nchmod +x s.sh",
]
for cmd in KILL_PASS:
    rc, out = run(cmd)
    check(f'pass {cmd[:55]!r}', rc == 0 and out is None or print('     got', rc, out))

# T1047: a raw state-change tool at command position gets a non-blocking pc-verb hint (exit 0, additionalContext).
HINT = [
    ('pactl set-sink-volume @DEFAULT_SINK@ 50%', '`pc audio vol <node> <0-150%|+N|-N> --apply`'),
    ('pactl set-default-sink bluez_output.X 2>&1; echo rc=$?', '`pc audio default sink <name> --apply`'),
    ('timeout 5 pactl set-sink-mute X 1', '`pc audio mute <node> on|off|toggle --apply`'),
    ('XDG_RUNTIME_DIR=/run/user/$UID /usr/bin/pactl unload-module 5', '`pc audio --help`'),
    ('powerprofilesctl get; powerprofilesctl set balanced; echo rc=$?', '`pc power profile balanced --apply`'),
    ('sudo systemctl restart netdata', '`pc units restart netdata --apply`'),
    ('cd ~; systemctl --user stop dark-eye.service && ls', '`pc units stop dark-eye.service --user --apply`'),
    ('sudo -n systemctl --system start foo.timer', '`pc units start foo.timer --system --apply`'),
    ('for u in a; do systemctl --user stop $u; done', '`pc units stop $u --user --apply`'),
    ('if true; then systemctl --user restart a; fi', '`pc units restart a --user --apply`'),
    ('if x; then :; else pactl set-sink-mute x 1; fi', '`pc audio mute <node> on|off|toggle --apply`'),
    ('if x; then :; elif ! powerprofilesctl set power-saver; then :; fi', '`pc power profile power-saver --apply`'),
    ('{ pactl set-sink-mute x 1; }', '`pc audio mute <node> on|off|toggle --apply`'),
    ('while ! systemctl --user start a; do :; done', '`pc units start a --user --apply`'),
    ('sudo -u someone systemctl --user stop x', '`pc units stop x --user --apply`'),
    ('x=$(pactl set-default-sink tv)', '`pc audio default sink <name> --apply`'),
]


def hint(cmd):
    """(exit code, additionalContext or None, permissionDecision or None) of the hook on cmd."""
    rc, out = run(cmd)
    o = (out or {}).get('hookSpecificOutput', {})
    return rc, o.get('additionalContext'), o.get('permissionDecision')


for cmd, want in HINT:
    rc, ctx, dec = hint(cmd)
    check(f'hint {cmd[:55]!r}', rc == 0 and dec is None and ctx and want in ctx and 'pc undo' in ctx
          or print('     got', rc, ctx, dec))
NO_HINT = [
    'systemctl --user status netdata', 'systemctl --user cat foo-start.service', 'systemctl show -p ActiveState x',
    'systemctl --user daemon-reload', 'echo pactl set-sink-mute x 1', 'grep -n "systemctl stop" notes.md',
    "cat > s.sh <<'EOF'\npactl set-sink-mute x 1\nEOF\nchmod +x s.sh", 'claude -p "run powerprofilesctl set balanced"',
    'pc audio vol earbuds 50% --apply', 'pc units stop foo --apply',
    'systemctl -H host stop foo', 'systemctl --host=host restart foo', 'systemctl -M box start foo',
    'pactl list short sinks', 'pactl get-default-sink', 'x=$(pactl get-default-sink)', 'pactl info',
    'powerprofilesctl get', 'powerprofilesctl', 'echo do systemctl stop x', 'echo { pactl set-sink-mute x 1',
    'ssh host systemctl stop foo',
]
for cmd in NO_HINT:
    rc, out = run(cmd)
    check(f'no hint {cmd[:52]!r}', rc == 0 and out is None or print('     got', rc, out))
ok, reason = denied("pkill -f vite; pactl list short sinks")
check('a deny wins over a hint (one JSON object, deny)', ok and '[v]ite' in reason)

# T1082: Claude Code's shell runs `grep` as ugrep and `find` as bfs; name the two gotchas before they fail.
SHADOW = [
    ("grep -oiE '.{0,30}(dbpass|_pass=|-P [^ ]+).{0,25}' actions.jsonl | head -12", 'command grep'),
    ('sed -n 49p d/CLAUDE.md | grep -o ".\\{0,200\\}vendor.\\{0,200\\}"', 'complexity'),
    ("f=x; LC_ALL=C grep -ao -m2 '.\\{0,200\\}asyncRewake.\\{0,200\\}' \"$f\" | head -c 1500", 'command grep'),
    ("grep -o '\"summary\": \"[^\"]*\\(sshpass -p \\|curl [^\"]*-u \\)[^\"]\\{0,40\\}' log/a.jsonl", 'command grep'),
    ("cd /x && grep -o 'declutter [0-9a-z-]*[^\"]\\{0,120\\}' $f | sort -u", 'command grep'),
    ("find ~/agent-work -newermt '-1 day' -type f | wc -l", 'command find'),
    ('ls; find . -newerct yesterday', "-newermt $(date -d '-1 day' +%F)"),
]
for cmd, want in SHADOW:
    rc, ctx, dec = hint(cmd)
    check(f'shadow hint {cmd[:48]!r}', rc == 0 and dec is None and ctx and want in ctx or print('     got', rc, ctx, dec))
NO_SHADOW = [
    'grep -c x f', "grep -oE '.{0,400}x' f", "grep -oE '.{0,15}x.{0,15}' f", "grep -oE '.{40}x.{40}' f",
    "command grep -oE '.{0,30}x.{0,30}' f", "rg -o '.{0,30}x.{0,30}' f", "grep -F '.{0,30}x.{0,30}' f",
    "grep -P '.{0,30}x.{0,30}' f", "timeout 5 grep -oE '.{0,30}x.{0,30}' f", "ls | xargs grep -oE '.{0,30}x.{0,30}'",
    "echo grep -oE '.{0,30}x.{0,30}'", "grep -oE 'a+b.{0,40}' f", "grep -oE 'execve\\(\"[^\"]+\", \\[[^]]{0,160}' f",
    "grep -o '.\\{200\\}<task-id>[^<]*</task-id>.\\{0,300\\}' f", 'grep -ohE \'"(votes|refut[a-z]*)":[^,}]{0,60}\' f',
    'find . -newer ref.txt', 'find . -newermt 2026-10-20', "find . -newermt '2026-10-20 10:00'", 'find . -newermt @1760000000',
    'find . -newermt "@$(( $(date +%s) - 86400))"',
    "find . -newermt \"$(date -d '-1 day' +%F)\"", "command find . -newermt '-1 day'", "echo find . -newermt '-1 day'",
]
for cmd in NO_SHADOW:
    rc, out = run(cmd)
    check(f'no shadow hint {cmd[:45]!r}', rc == 0 and out is None or print('     got', rc, out))

# T1082: a command that deletes the cwd it cd'd into fails the Bash tool's closing `pwd` (getcwd, exit 1).
CDRM = [
    ('d=$(mktemp -d); cd $d && ffmpeg -i x f.png; rm -rf "$d"', 'cd ~ && rm -rf $d'),
    ('S=/tmp/s/t811; cd $S; python3 b.py; rm -rf $S', 'cd ~ && rm -rf $S'),
    ('T=$(mktemp -d); cd "$T/sub" && make; rm -rf "${T}"', 'cd ~ && rm -rf $T'),
    ('cd /tmp/x && ls && rm -fr /tmp/x/', 'cd ~ && rm -rf /tmp/x'),
]
for cmd, want in CDRM:
    ok, reason = denied(cmd)
    check(f'deny cd-then-rm {cmd[:48]!r}', ok and 'getcwd' in reason and f'`{want}`' in reason or print('     got', reason))
NO_CDRM = [
    'd=$(mktemp -d); cd $d && ls; cd ~ && rm -rf "$d"', 'd=$(mktemp -d); (cd $d && ls); rm -rf $d',
    'cd $d && rm -rf build', 'cd /x && rm -rf /x2', 'rm -rf $d; cd $d', 'cd $d; rm -rf $d; cd /', 'cd $d; rm $d/f',
    "echo 'cd $d; rm -rf $d'",
]
for cmd in NO_CDRM:
    rc, out = run(cmd)
    check(f'no cd-then-rm deny {cmd[:45]!r}', rc == 0 and out is None or print('     got', rc, out))


def cwd_event(cmd, cwd, sep=': '):
    """A PreToolUse event that carries the session cwd, keys spaced like json.dumps or compact like Claude Code."""
    return json.dumps({'cwd': cwd, 'hook_event_name': 'PreToolUse', 'tool_name': 'Bash', 'tool_input': {'command': cmd}},
                      separators=(', ', sep))


gone = os.path.join(WORK, 'gone')
for sep in (': ', ':'):
    rc, out = run('', raw=cwd_event('ls -la', gone, sep))
    o = (out or {}).get('hookSpecificOutput', {})
    check(f'deny a call whose cwd was deleted (sep {sep!r})', rc == 0 and o.get('permissionDecision') == 'deny'
          and 'cd ~ &&' in o.get('permissionDecisionReason', '') or print('     got', rc, out))
for cmd, cwd in (('cd ~ && ls', gone), ('cd /tmp; ls', gone), ('ls -la', WORK)):
    rc, out = run('', raw=cwd_event(cmd, cwd, ':'))
    check(f'no cwd deny {cmd!r} in {os.path.basename(cwd)}', rc == 0 and out is None or print('     got', rc, out))

# T1082: raw apt gets the pc pkg hint only once ~/agents/bin/pc-pkg exists (T1087).
rc, out = run('sudo -n apt-get install -y iw')
check('no apt hint while pc-pkg is missing', rc == 0 and out is None or print('     got', rc, out))
os.makedirs(os.path.join(WORK, 'agents', 'bin'), exist_ok=True)
open(os.path.join(WORK, 'agents', 'bin', 'pc-pkg'), 'w').close()
for cmd, want in (('sudo -n apt-get install -y iw nvme-cli', '`pc pkg install iw nvme-cli --apply`'),
                  ('sudo apt remove weston', '`pc pkg remove weston --apply`')):
    rc, ctx, dec = hint(cmd)
    check(f'apt hint {cmd!r}', rc == 0 and dec is None and ctx and want in ctx or print('     got', rc, ctx, dec))
for cmd in ('apt-cache policy iw', 'apt list --installed', "echo 'apt-get install x'", 'dpkg -l iw'):
    rc, out = run(cmd)
    check(f'no apt hint {cmd!r}', rc == 0 and out is None or print('     got', rc, out))
os.remove(os.path.join(WORK, 'agents', 'bin', 'pc-pkg'))
for cmd in ('sudo -n apt-get install -y iw nvme-cli', 'sudo apt remove weston'):
    SPAWNED.pop(cmd)

# T1147: sudo once per loop item writes 3 journal lines each; nudge to one root shell.
SUDO_LOOP = [
    'ls /tmp | while read p; do sudo -n du -sk "$p"; done',
    'sudo -n find /tmp -maxdepth 1 | while read p; do n=$(sudo -n du -sm "$p"); echo $n; done',
    'for d in /tmp/*; do sudo du -sk $d; done',
    'until false; do nice sudo -n true; done',
    'ls /tmp | xargs -I{} sudo -n du -sk {}',
    'find /tmp | xargs -r -n 1 sudo du -sk',
    'for f in a; do `sudo ls`; done',
    'while read p\n  do\n  n=`sudo du -sk $p`\ndone < l',
]
for cmd in SUDO_LOOP:
    rc, ctx, dec = hint(cmd)
    check(f'sudo-loop hint {cmd[:46]!r}', rc == 0 and dec is None and ctx and "sudo -n bash -c '" in ctx
          and 'sudo -n find' in ctx or print('     got', rc, ctx, dec))
NO_SUDO_LOOP = [
    "sudo -n bash -c 'for p in /tmp/*; do du -sk \"$p\"; done'", 'sudo -n find /tmp -exec du -sk {} +',
    'sudo -n du -sk /tmp', 'for f in a b; do echo $f; done; sudo -n ls', "echo 'while read p; do sudo x; done'",
    "grep -n 'do sudo' notes.md", 'ls | xargs grep sudo', "cat > s.sh <<'EOF'\nfor f in x; do sudo ls; done\nEOF\nls",
]
for cmd in NO_SUDO_LOOP:
    rc, out = run(cmd)
    check(f'no sudo-loop hint {cmd[:43]!r}', rc == 0 and out is None or print('     got', rc, out))


def p50(cmd):
    """Median wall ms of 10 hook runs on cmd."""
    ts = []
    for _ in range(10):
        t0 = time.time()
        run(cmd)
        ts.append((time.time() - t0) * 1000)
    return sorted(ts)[5]


def miss_ms(raw):
    """Median wall ms of 21 front runs on a raw event that carries no trigger bytes."""
    ts = []
    for _ in range(21):
        t0 = time.time()
        subprocess.run([HOOK], input=raw, capture_output=True, text=True, env=ENV, cwd=WORK, timeout=10)
        ts.append((time.time() - t0) * 1000)
    return sorted(ts)[10]


kms = p50("pkill -f 'wait-for --label x'")
print(f'     hook p50 on a pkill command {kms:.0f} ms')
load, ncpu = os.getloadavg()[0], os.cpu_count()
u = f', unjudged at load {load:.2f}' if load > ncpu / 2 else ''
ms = miss_ms(event('ls -la; git status'))
check(f'front miss median {ms:.1f} ms (budget 8 ms{u})', ms <= 8 or u)
ms = miss_ms(event('systemctl --user status netdata; systemctl show x'))
check(f'front read-only systemctl miss median {ms:.1f} ms, no python (budget 10 ms{u})', ms <= 10 or u)
ms = miss_ms(event('cat <<EOF\n' + 'a' * 100000 + '\nEOF'))
check(f'front 100 KB miss median {ms:.1f} ms (budget 15 ms{u})', ms <= 15 or u)

trig = [c for c, _ in DENY + KILL_DENY + KILL_OWN][:20] + [c for c, _ in HINT]
same = [c for c in trig if subprocess.run([HOOK], input=event(c).encode(), capture_output=True, env=ENV, cwd=WORK).stdout
        == subprocess.run(['/usr/bin/python3', '-IS', IMPL], input=event(c).encode(), capture_output=True, env=ENV, cwd=WORK).stdout]
check(f'front deny/hint output byte-identical to the impl on {len(same)}/{len(trig)} trigger commands', len(same) == len(trig) == 20 + len(HINT))

rc, out = run('', raw=json.dumps({'tool_name': 'Write', 'tool_input': {'content': 'until x; do sleep 1; done'}}))
check('pass a non-Bash tool', rc == 0 and out is None)
rc, out = run('', raw='not json')
check('fail open on bad input (exit 0, no output)', rc == 0 and out is None)

fx = list(SPAWNED)
check(f'batch runner matches the spawned hook on all {len(fx)} fixture commands', run_many(fx) == [SPAWNED[c] for c in fx])

t0 = time.time()
for _ in range(10):
    run('ls -la; git status')
ms = (time.time() - t0) * 100
check(f'hook latency on a plain command {ms:.0f} ms (budget {budget(0.1) * 1000:.0f} ms)', ms < budget(0.1) * 1000)

# Replay: every Bash command of the last 7 days in the audit log (summaries, cut at 500 chars).
cut = time.strftime('%Y-%m-%dT%H:%M', time.localtime(time.time() - 7 * 86400))
cmds = []
for p in glob.glob(os.path.expanduser('~/agents/log/actions.jsonl*')):
    with (gzip.open(p, 'rt') if p.endswith('.gz') else open(p)) as f:
        for line in f:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get('ts', '') >= cut and r.get('tool') == 'Bash':
                cmds.append(r.get('summary', ''))
t0 = time.time()
hits = [c for c in cmds if w.loop_wait(c)]
dt = time.time() - t0
data = [c for c in hits if c.lstrip().startswith(('echo ', 'grep ', 'printf ', 'claude ')) or '<<' in c.split('until')[0]]
print(f'     replay: {len(cmds)} commands, {len(hits)} denied, {len(data)} with the loop in data, {dt:.2f} s')
check('replay: 0 denies where the loop is data (echo/grep/claude -p text, heredoc body)', not data)
check(f'replay: the parser costs under 1 ms per command (budget {budget(0.001) * 1000:.2f} ms)', not cmds or dt / len(cmds) < budget(0.001))
pk = [c for c in cmds if 'pkill' in c or 'pgrep' in c]
kills = [c for c, (d, _) in zip(pk, denied_many(pk)) if d]
kdata = [c for c in kills if c.lstrip().startswith(('echo ', 'grep ', 'printf ', 'claude ', 'rg '))
         and not any(o in c for o in (';', '&', '|', '$(', '\n'))]
print(f'     replay: {sum("pkill" in c or "pgrep" in c for c in cmds)} pkill/pgrep commands, {len(kills)} self-kill denies')
check('replay: 0 self-kill denies where pkill is data (echo/grep/claude -p text)', not kdata or print('     data', kdata[:3]))
rw = [c for c in cmds if 'pactl' in c or 'powerprofilesctl' in c or 'systemctl' in c]
hinted = [c for c, (_, o) in zip(rw, run_many(rw)) if o and 'additionalContext' in o.get('hookSpecificOutput', {})]
hdata = [c for c in hinted if c.lstrip().startswith(('echo ', 'grep ', 'printf ', 'claude ', 'rg '))
         and not any(o in c for o in (';', '&', '|', '$(', '\n'))]
print(f'     replay: {len(rw)} pactl/powerprofilesctl/systemctl commands, {len(hinted)} pc-verb hints')
check('replay: 0 pc-verb hints where the tool is data (echo/grep/claude -p text)', not hdata or print('     data', hdata[:3]))
sh = [c for c in cmds if 'grep' in c and '{' in c or '-newer' in c or 'cd ' in c and 'rm ' in c]
res = run_many(sh)
shint = [c for c, (_, o) in zip(sh, res) if o and 'shadow (KB' in o.get('hookSpecificOutput', {}).get('additionalContext', '')]
cdrm = [c for c, (_, o) in zip(sh, res) if o and 'cds into' in o.get('hookSpecificOutput', {}).get('permissionDecisionReason', '')]
sdata = [c for c in shint + cdrm if c.lstrip().startswith(('echo ', 'printf ', 'claude ', 'rg '))
         and not any(o in c for o in (';', '&', '|', '$(', '\n'))]
print(f'     replay: {len(sh)} grep/find/cd+rm commands, {len(shint)} ugrep/bfs hints, {len(cdrm)} cd-then-rm denies')
check('replay: 0 shadow hints or cd-then-rm denies where the tool is data', not sdata or print('     data', sdata[:3]))
lost = [c for c, (d, _) in zip(hits, denied_many(hits)) if not d]
check(f'replay: the fast path keeps all {len(hits)} denies ({len(lost)} lost)', not lost or print('     lost', lost[:3]))

subprocess.run(['rm', '-rf', WORK])
print('PASS' if not bad else 'FAIL')
raise SystemExit(bad)
