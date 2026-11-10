"""One manager per Discord project (T1515 P31): `python -m liaison.managers new <project-id>` makes po-<id> under the
router with `po-new --parent`, a project block rendered from that one projects.json entry, and its own ledger;
`hire` (T1547, `discord-hire`) also writes the entry, the org seat, the thread route and both units, each step once."""
import argparse
import json
import os
import re
import shlex
import subprocess
import sys

from .registry import Registry
from .po import po_home
from .runlock import run_lock
from .state import State

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'lib'))
import org  # noqa: E402


def block(p):
    """The manager's "## Project" block: this entry's repo, clone, rules and skills, nothing from any other entry."""
    rules = '\n'.join(f'  - {k}: {v}' for k, v in p.get('rules', {}).items())
    where = (f'- {p["name"]}: repo `{p["repo"]}` (owned by its maintainers), clone `{p["clone"]}`. Work only in that clone;\n'
             f'  never push main, never merge; `pr_flow` says which branch and how.\n' if p.get('repo') else
             f'- {p["name"]}: no repo yet. Design and notes only in your own `state/`; push nothing. Ask the thread which repo\n'
             f'  to use; when the maintainers name one, write `ESCALATE: repo <owner/name>` (the router adds it).\n')
    return (where +
            f'- Rules (every brief quotes them):\n{rules}\n'
            f'- Skills: {", ".join(p.get("skills", [])) or "none"}.\n'
            f'- Ledger: `~/agent-work/decisions/{p["id"]}.md`. Discord thread messages come from the liaison verbatim.')


def make(pid, env=None):
    """Create po-<pid>; returns 0, 2 for an unknown project, or po-new's exit code (3: it exists)."""
    env = dict(os.environ) if env is None else env
    reg = Registry(env.get('LIAISON_REGISTRY', os.path.join(HERE, 'projects.json')))
    p = reg.get(pid)
    if p is None:
        print(f'refused: unknown project; known: {", ".join(reg.projects)}')
        return 2
    router = reg.router or env.get('LIAISON_ROUTER', 'po-discord')
    rc = subprocess.call([env.get('PO_NEW', 'po-new'), pid, p['name'], '--parent', router.removeprefix('po-')], env=env)
    if rc:
        return rc
    brief = os.path.join(po_home(env), f'po-{pid}', 'BRIEF.md')
    with open(brief) as f:
        text = f.read()
    with open(brief, 'w') as f:
        f.write(text.replace('{{PROJECT}}', block(p)))
    ledger = os.path.join(env.get('AGENT_WORK', os.path.expanduser('~/agent-work')), 'decisions', f'{pid}.md')
    os.makedirs(os.path.dirname(ledger), exist_ok=True)
    if not os.path.exists(ledger):
        with open(ledger, 'w') as f:
            f.write(f'# {pid}: decisions ledger (his words, dated)\n')
    print(f'relay its replies at once: pc units enable discord-liaison-relay@{pid}.path --user --now --apply')
    return 0


def _cmd(env, key, default):
    return shlex.split(env.get(key, default))


def _replace(path, text):
    tmp = f'{path}.tmp'
    with open(tmp, 'w') as f:
        f.write(text)
    os.replace(tmp, path)


def dump(data):
    """projects.json in its hand style: one key per line, `rules` one per line, lists and `match` inline."""
    j = lambda v: json.dumps(v, ensure_ascii=False)  # noqa: E731

    def val(k, v):
        if k != 'rules' or not v:
            return j(v)
        return '{\n' + ',\n'.join(f'    {j(a)}: {j(b)}' for a, b in v.items()) + '\n   }'
    ents = ['  {\n' + ',\n'.join(f'   {j(k)}: {val(k, v)}' for k, v in p.items()) + '\n  }' for p in data['projects']]
    head = ''.join(f' {j(k)}: {j(v)},\n' for k, v in data.items() if k != 'projects')
    return '{\n' + head + ' "projects": [\n' + ',\n'.join(ents) + '\n ]\n}\n'


def entry(pid, name, repo, rules, words):
    """A new projects.json entry; no repo yet = repo and clone null."""
    return {'id': pid, 'name': name, 'repo': repo, 'clone': f'~/projects/collab/{repo.split("/")[1]}' if repo else None,
            'match': {'tags': [name.lower()], 'title': [name.lower()] + list(words)},
            'rules': {'language': 'es: every forum post in Spanish',
                      'pr_flow': 'feature branch, push over SSH, gh pr create, link in the thread; never push main, never merge',
                      **rules},
            'skills': [], 'po': f'po-{pid}'}


def add_seat(path, pid, name, parent):
    """Append the manager's org seat (one line, file style kept): a proper name, the project as its area; False when there."""
    with open(path) as f:
        text = f.read()
    seats = json.loads(text)['seats']
    if any(s['id'] == pid for s in seats):
        return False
    seat = {'id': pid, 'name': org.proper_name(pid, [s['name'] for s in seats]), 'area': name, 'role': 'manager', 'parent': parent, 'wake': 'po-inbox',
            'match': f'~/agents/po-{pid}'}
    cut = text.rstrip().rfind(']')
    _replace(path, text[:cut].rstrip() + ',\n  ' + json.dumps(seat, ensure_ascii=False) + '\n' + text.rstrip()[cut:] + '\n')
    return True


def enable_units(pid, env):
    """Enable both path units through `pc units enable --apply` (ledgered); returns (changed, failed unit or None)."""
    changed = False
    for u in (f'po@{pid}.path', f'discord-liaison-relay@{pid}.path'):
        state = subprocess.run(_cmd(env, 'SYSTEMCTL', 'systemctl') + ['--user', 'is-enabled', u],
                               capture_output=True, text=True, env=env).stdout.strip()
        if state == 'enabled':
            continue
        if subprocess.call(_cmd(env, 'PC', 'pc') + ['units', 'enable', u, '--user', '--now', '--apply'], env=env):
            return changed, u
        changed = True
    return changed, None


def hire(pid, name, thread, repo=None, rules=None, words=(), env=None):
    """Make a new Discord project's manager end to end; each step runs once, so a re-run is a no-op. 0, 1 failed, 2 refused."""
    env = dict(os.environ) if env is None else env
    if (not re.fullmatch(r'[a-z0-9][a-z0-9-]*', pid) or not thread.isdigit() or not name.strip()
            or (repo and not re.fullmatch(r'[\w.-]+/[\w.-]+', repo))):
        print('refused: <id> [a-z0-9-], --thread digits, a name, --repo <owner>/<name>')
        return 2
    done = []
    reg = env.get('LIAISON_REGISTRY', os.path.join(HERE, 'projects.json'))
    with open(reg) as f:
        data = json.load(f)
    p = next((x for x in data['projects'] if x['id'] == pid), None)
    if p is None:
        p = entry(pid, name, repo, rules or {}, words)
        for o in data['projects']:
            hit = [w for k in ('tags', 'title') for w in o.get('match', {}).get(k, []) if w.lower() in name.lower()]
            if hit:
                print(f'warning: {o["id"]} matches "{hit[0]}" in this name: its messages would go to the router; narrow it')
        data['projects'].append(p)
        done.append('entry')
    elif repo and not p.get('repo'):
        p.update(repo=repo, clone=f'~/projects/collab/{repo.split("/")[1]}')
        done.append('repo')
    if done:
        _replace(reg, dump(data))
    brief = os.path.join(po_home(env), f'po-{pid}', 'BRIEF.md')
    if not os.path.exists(os.path.dirname(brief)):
        rc = make(pid, dict(env, LIAISON_REGISTRY=reg))
        if rc:
            return rc
        done.append('manager')
    elif 'repo' in done:
        with open(brief) as f:
            head = f.read().split('\n## Project\n')[0]
        _replace(brief, f'{head}\n## Project\n{block(p)}\n')
    parent = (data.get('router') or env.get('LIAISON_ROUTER', 'po-discord')).removeprefix('po-')
    if add_seat(env.get('ORG_FILE') or os.path.join(po_home(env), 'org.json'), pid, name, parent):
        done.append('seat')
    home = env.get('LIAISON_HOME', HERE)
    with run_lock(os.path.join(home, 'state', 'state.lock'), wait=True):
        state = State(os.path.join(home, 'state'))
        if (state.thread(thread) or {}).get('project') != pid:
            state.put_thread(thread, project=pid)
            done.append('route')
    changed, failed = enable_units(pid, env)
    done += ['units'] if changed else []
    if failed:
        print(f'failed: pc units enable {failed}; done so far: {", ".join(done) or "nothing"}')
        return 1
    if not done:
        print(f'already hired: po-{pid} (entry, manager, seat, route, units in place)')
        return 0
    note = f'Hired po-{pid}, the manager of «{name}» (Discord thread {thread}): {", ".join(done)}.'
    rc = subprocess.call(_cmd(env, 'CHAT', 'chat') + ['post', '@owner', note], env=dict(env, CHAT_SEAT=env.get('CHAT_SEAT') or parent))
    print(f'hired po-{pid}: {", ".join(done)}')
    if rc:
        print(f'failed: owner note (chat exit {rc}); post it by hand: {note}')
        return 1
    return 0


def main(argv):
    if argv[:1] == ['hire']:
        a = argparse.ArgumentParser(prog='discord-hire', description='hire a manager po-<id> for a new Discord project (T1547)')
        a.add_argument('id')
        a.add_argument('name')
        a.add_argument('--thread', required=True)
        a.add_argument('--repo')
        a.add_argument('--rule', action='append', default=[], metavar='KEY=VALUE')
        a.add_argument('--match', action='append', default=[], metavar='WORD')
        ns = a.parse_args(argv[1:])
        if not all('=' in r for r in ns.rule):
            a.error('--rule takes KEY=VALUE')
        rules = dict(r.split('=', 1) for r in ns.rule)
        return hire(ns.id, ns.name, ns.thread, ns.repo, rules, [w.lower() for w in ns.match])
    if len(argv) != 2 or argv[0] != 'new':
        sys.exit('usage: python -m liaison.managers new <project-id> | hire <id> "<name>" --thread <tid> [--repo …]')
    return make(argv[1])


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
