"""Product-owner handoff (T1412 P5): inbox messages of a project whose registry entry names a `po` go to that PO with
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
    """po-ask every inbox message routed to a PO, once (state/po-asked.json); returns the number handed off."""
    path = os.path.join(app.home, 'state', 'po-asked.json')
    try:
        with open(path) as f:
            asked = set(json.load(f))
    except (OSError, ValueError):
        asked = set()
    n = 0
    for m in app.state.inbox:
        pid = (app.state.thread(m['thread_id']) or {}).get('project', '')
        route = app.registry.route(pid) if pid else None
        if m['id'] in asked or route in (None, 'liaison') or m.get('channel') == 'general':
            continue
        cmd = shlex.split(env.get('LIAISON_PO_ASK', 'po-ask')) + [
            route.removeprefix('po-'), '--from', 'liaison', '--channel', 'discord', '--thread', m['thread_id'], '--copy',
            f'{m["author"]} (Discord, thread "{m["thread"]}", message {m["id"]}): {m["content"]}']
        if subprocess.call(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL) == 0:
            asked.add(m['id'])
            n += 1
    save_json(path, sorted(asked))
    return n


def outbox_files(app, env):
    for p in app.registry.projects.values():
        if p.get('po'):
            yield from sorted(glob.glob(os.path.join(glob.escape(po_home(env)), p['po'], 'outbox', 'discord', '*.md')))


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
