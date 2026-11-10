"""One manager per Discord project (T1515 P31): `python -m liaison.managers new <project-id>` makes po-<id> under the
router with `po-new --parent`, a project block rendered from that one projects.json entry, and its own ledger."""
import os
import subprocess
import sys

from .registry import Registry
from .po import po_home

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def block(p):
    """The manager's "## Project" block: this entry's repo, clone, rules and skills, nothing from any other entry."""
    rules = '\n'.join(f'  - {k}: {v}' for k, v in p.get('rules', {}).items())
    return (f'- {p["name"]}: repo `{p["repo"]}` (owned by its maintainers), clone `{p["clone"]}`. Work only in that clone;\n'
            f'  never push main, never merge; `pr_flow` says which branch and how.\n'
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


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] != 'new':
        sys.exit('usage: python -m liaison.managers new <project-id>')
    sys.exit(make(sys.argv[2]))
