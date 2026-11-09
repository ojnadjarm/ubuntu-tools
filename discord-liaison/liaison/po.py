"""Product-owner handoff (T1412 P5, T1515 P31): inbox messages go by code to their project's manager or the router with
`po-ask`; the PO's replies in <po>/outbox/discord/ are posted to their thread. `python -m liaison.po handoff|relay`."""
import asyncio
import glob
import json
import os
import shlex
import shutil
import subprocess
import sys

from discordbot.config import Config
from discordbot.rest import Rest
from discordbot.store import save_json

from .cli import App


def po_home(env):
    return env.get('LIAISON_PO_HOME') or env.get('HARNESS_HOME') or os.path.expanduser('~/agents')


def handoff(app, env):
    """po-ask every inbox message `Registry.dispatch` gives an agent, once (state/po-asked.json); with a router set the
    handed message leaves the liaison inbox, so no triage run wakes for it. Returns the number handed off."""
    path = os.path.join(app.home, 'state', 'po-asked.json')
    with app.locked():
        app.reload()
        try:
            with open(path) as f:
                asked = set(json.load(f))
        except (OSError, ValueError):
            asked = set()
        handed = set()
        for m in app.state.inbox:
            pid = (app.state.thread(m['thread_id']) or {}).get('project', '')
            to = app.registry.dispatch(m, pid)
            if to is None:
                continue
            if m['id'] not in asked and subprocess.call(ask(env, to, m, pid), stdin=subprocess.DEVNULL,
                                                        stdout=subprocess.DEVNULL) != 0:
                continue
            handed.add(m['id'])
        n = len(handed - asked)
        save_json(path, sorted(asked | handed))
        if app.registry.router and handed:
            app.state.inbox = [m for m in app.state.inbox if m['id'] not in handed]
            save_json(os.path.join(app.home, 'state', 'inbox.json'), app.state.inbox)
    return n


def ask(env, to, m, pid):
    """The po-ask command that files one Discord message for agent `to` (the router also gets the thread's project)."""
    where = f'thread "{m["thread"]}"' + (f', project {pid or "none"}' if to != f'po-{pid}' else '')
    return shlex.split(env.get('LIAISON_PO_ASK', 'po-ask')) + [
        to.removeprefix('po-'), '--from', 'liaison', '--channel', 'discord', '--thread', m['thread_id'], '--copy',
        f'{m["author"]} (Discord, {where}, message {m["id"]}): {m["content"]}']


def outbox_files(app, env):
    agents = {p['po'] for p in app.registry.projects.values() if p.get('po')} | {app.registry.router} - {None}
    for name in sorted(agents):
        yield from sorted(glob.glob(os.path.join(glob.escape(po_home(env)), name, 'outbox', 'discord', '*.md')))


async def relay(app, env):
    """Post each PO reply (`thread: <id>` line, then the text) with the liaison's own post; move it to sent/ or refused/."""
    n = 0
    for f in outbox_files(app, env):
        with open(f) as fh:
            head, _, text = fh.read().partition('\n')
        tid = head.removeprefix('thread:').strip()
        ok = head.startswith('thread:') and tid.isdigit() and text.strip() and await app.post([tid, text.strip()]) == 0
        dest = os.path.join(os.path.dirname(f), 'sent' if ok else 'refused')
        os.makedirs(dest, exist_ok=True)
        shutil.move(f, os.path.join(dest, os.path.basename(f)))
        n += bool(ok)
    return n


async def amain(argv, env=None, rest=None):
    env = dict(os.environ) if env is None else env
    cmd = argv[0] if argv else ''
    if cmd == 'handoff':
        n = handoff(App(env, rest), env)
        if n:
            print(f'handed {n} message(s) to their PO agent')
        return 0
    if cmd != 'relay':
        print('usage: python -m liaison.po handoff|relay')
        return 2
    probe = App(env, rest)
    if not any(True for _ in outbox_files(probe, env)):
        return 0
    own = rest is None
    if own:
        cfg = Config.from_env(env)
        rest = Rest(cfg.api_base, cfg.token())
    try:
        n = await relay(App(env, rest), env)
        print(f'relayed {n} PO repl(ies)')
        return 0
    finally:
        if own:
            await rest.close()


if __name__ == '__main__':
    sys.exit(asyncio.run(amain(sys.argv[1:])))
