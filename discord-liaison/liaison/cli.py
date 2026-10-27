"""discord-liaison tick|check|inbox|done|post|map|pr|status: the liaison's tools for #foro and #general (T1409, T1411)."""
import asyncio
import os
import subprocess
import sys

from discordbot.cli import write_config
from discordbot.config import Config
from discordbot.rest import Rest, RestError
from discordbot.runner import SECRET_KEYS
from discordbot.sanitize import chunks, clean

from .caps import Caps
from .registry import Registry
from .state import State
from .watch import Watcher

GENERAL = '#general'
ME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
USAGE = 'usage: discord-liaison tick [--dry-run]|check|inbox|done|post <thread> <text…>|map <thread> <project>|pr <project>|status'


class App:
    def __init__(self, env, rest):
        self.env, self.rest = env, rest
        self.home = env.get('LIAISON_HOME', ME)
        self.forum, self.guild = env.get('DISCORD_FORUM_ID', ''), env.get('DISCORD_GUILD_ID', '')
        self.general = env.get('DISCORD_GENERAL_ID', '')
        self.state = State(os.path.join(self.home, 'state'))
        self.registry = Registry(env.get('LIAISON_REGISTRY', os.path.join(ME, 'projects.json')))
        os.makedirs(os.path.join(self.home, 'logs'), exist_ok=True)
        self.caps = Caps(os.path.join(self.home, 'state', 'caps.json'), os.path.join(self.home, 'logs', 'caps.log'),
                         {'run': int(env.get('LIAISON_RUNS_PER_DAY', '30')), 'pr': int(env.get('LIAISON_PRS_PER_DAY', '3'))})

    async def general_id(self, save):
        """#general's id: DISCORD_GENERAL_ID, else the guild's text channel named general, stored in config.env."""
        if not self.general:
            chans = await self.rest.guild_channels(self.guild)
            self.general = next((c['id'] for c in chans if c.get('type') == 0 and c.get('name') == 'general'), '')
            if self.general and save:
                write_config({'DISCORD_GENERAL_ID': self.general}, self.env.get('HARNESS_CONFIG'))
        return self.general

    async def check(self, save=True):
        w = Watcher(self.rest, self.guild, self.forum)
        msgs, cur = await w.poll(self.state.cursor)
        gid = await self.general_id(save)
        if gid:
            mentions, cur[GENERAL] = await w.general(gid, self.state.cursor.get(GENERAL, ''))
            msgs += mentions
        for m in msgs:
            if m.get('channel') == 'general':
                continue
            th = self.state.thread(m['thread_id']) or {}
            if not th.get('project'):
                p = self.registry.match(m['thread'], m['tags'])
                if p and save:
                    self.state.put_thread(m['thread_id'], project=p['id'], title=m['thread'])
        if save:
            self.state.add(msgs)
            self.state.save_cursor(cur)
        return msgs, cur

    async def tick(self, args):
        if args == ['--dry-run']:
            msgs, cur = await self.check(save=False)
            threads = sum(1 for k in cur if k not in ('_seeded', GENERAL))
            mentions = sum(1 for m in msgs if m.get('channel') == 'general')
            seeded = not self.state.cursor
            with open(os.path.join(self.home, 'REPORT.md'), 'w') as f:
                f.write(f'# discord-liaison: dry run (read #foro and #general, posted nothing)\n\nthreads {threads}, '
                        f'#general mentions {mentions}, new messages {len(msgs)}{" (first real tick only seeds the cursor)" if seeded else ""}, inbox '
                        f'{len(self.state.inbox)}, LLM run: {"would start" if msgs or self.state.inbox else "no"}\n'
                        f'caps today: runs {self.caps.used("run")}/{self.caps.limits["run"]}, '
                        f'PRs {self.caps.used("pr")}/{self.caps.limits["pr"]}\n')
            print(f'dry run: threads {threads}, #general mentions {mentions}, {len(msgs)} new')
            return 0
        msgs, _ = await self.check()
        print(f'{len(msgs)} new, inbox {len(self.state.inbox)}')
        if not self.state.inbox:
            return 0
        if not self.caps.take('run'):
            return 0
        cmd = self.env.get('LIAISON_AGENT_CMD', 'agent-run discord-liaison')
        return subprocess.call(cmd, shell=True, stdin=subprocess.DEVNULL)

    def inbox(self):
        self.state.mark_shown()
        for m in self.state.inbox:
            pid = (self.state.thread(m['thread_id']) or {}).get('project', '')
            route = self.registry.route(pid) if pid else ''
            body = m['content'].replace('</message', '<\\/message')
            print(f'<message channel="{m.get("channel", "foro")}" thread="{m["thread_id"]}" title="{m["thread"]}" tags="{",".join(m["tags"])}" '
                  f'project="{pid}" route="{route}" author="{m["author"]}" bot="{str(m["bot"]).lower()}" id="{m["id"]}">\n'
                  f'{body}\n</message>')
        print(f'{len(self.state.inbox)} message(s); run `discord-liaison done` after answering them')
        return 0

    def done(self):
        n = len(self.state.shown)
        self.state.drop_shown()
        print(f'done: {n} cleared, {len(self.state.inbox)} still in the inbox')
        return 0

    async def post(self, args):
        if len(args) < 2:
            print(USAGE)
            return 2
        tid, text = args[0], ' '.join(args[1:])
        try:
            ch = await self.rest.channel(tid)
        except RestError:
            ch = {}
        if not (self.forum and ch.get('parent_id') == self.forum or self.general and tid == self.general):
            print(f'refused: {tid} is neither a thread of the forum nor #general')
            return 3
        parts = chunks(clean(text, [self.env.get(k, '') for k in SECRET_KEYS]))
        if self.env.get('LIAISON_DRY_RUN'):
            print(f'would post {len(parts)} message(s) to {tid}:\n' + '\n'.join(parts))
            return 0
        for part in parts:
            await self.rest.send(tid, part)
        print(f'posted {len(parts)} message(s)')
        return 0

    def map(self, args):
        if len(args) != 2 or self.registry.get(args[1]) is None:
            print(f'refused: unknown project; known: {", ".join(self.registry.projects)}')
            return 3
        self.state.put_thread(args[0], project=args[1])
        print(f'thread {args[0]} -> {args[1]}')
        return 0

    def pr(self, args):
        route = self.registry.route(args[0]) if args else None
        if route is None:
            print('refused: proyecto no registrado; responde que queda pendiente y avisa al owner (notify-owner)')
            return 3
        if route != 'liaison':
            print(f'refused: this project\'s work goes to its PO agent {route}')
            return 3
        if not self.caps.take('pr'):
            print(f'refused: PR cap reached ({self.caps.limits["pr"]} per day); say so in the thread')
            return 3
        p = self.registry.get(args[0])
        print(f'ok: one PR on {p["repo"]} (clone {p["clone"]}); rules: {p.get("rules")}; skills: {p.get("skills")}')
        return 0

    def status(self):
        print(f'inbox {len(self.state.inbox)}  threads mapped {sum(1 for t in self.state.threads.values() if t.get("project"))}'
              f'  runs {self.caps.used("run")}/{self.caps.limits["run"]}  PRs {self.caps.used("pr")}/{self.caps.limits["pr"]}')
        for p in self.registry.projects.values():
            print(f'project {p["id"]}  {p["repo"]}  route {self.registry.route(p["id"])}')
        return 0


async def amain(argv, env=None, rest=None):
    env = dict(os.environ) if env is None else env
    cmd, args = (argv[0] if argv else 'status'), argv[1:]
    own = rest is None
    if own:
        cfg = Config.from_env(env)
        rest = Rest(cfg.api_base, cfg.token())
    app = App(env, rest)
    try:
        if cmd in ('tick', 'post'):
            return await getattr(app, cmd)(args)
        if cmd == 'check':
            msgs, _ = await app.check()
            print(f'{len(msgs)} new, inbox {len(app.state.inbox)}')
            return 0
        if cmd in ('inbox', 'done', 'status'):
            return getattr(app, cmd)()
        if cmd in ('map', 'pr'):
            return getattr(app, cmd)(args)
        print(USAGE)
        return 2
    except RestError as e:
        print(f'discord-liaison: Discord API error {e.status}')
        return 1
    finally:
        if own:
            await rest.close()


def main():
    sys.exit(asyncio.run(amain(sys.argv[1:])))
