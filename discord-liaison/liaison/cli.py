"""discord-liaison tick|check|inbox|done|post|map|pr|status: the liaison's tools for #foro and #general (T1409, T1411)."""
import asyncio
import os
import shlex
import subprocess
import sys
import time

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
USAGE = ('usage: discord-liaison tick [--dry-run]|check|inbox|done|post <thread> [--image <png>] <text…>|'
         'react <thread> <message> <emoji>|art <prompt…>|map <thread> <project>|pr <project>|status')
IMAGE_MAGIC = (b'\x89PNG\r\n\x1a\n', b'\xff\xd8\xff')
MAX_IMAGE = 10 * 1024 * 1024


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
                         {'run': int(env.get('LIAISON_RUNS_PER_DAY', '30')), 'pr': int(env.get('LIAISON_PRS_PER_DAY', '3')),
                          'img': int(env.get('LIAISON_IMAGES_PER_DAY', '5'))})
        self.art_dir = os.path.join(self.home, 'state', 'art')

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

    async def allowed(self, tid):
        """True for a thread of the forum or #general: the only places the liaison may post or react."""
        if self.general and tid == self.general:
            return True
        try:
            ch = await self.rest.channel(tid)
        except RestError:
            return False
        return bool(self.forum) and ch.get('parent_id') == self.forum

    def image_ok(self, path):
        """Only a PNG or JPEG made by `art`, under the size limit, may be attached."""
        real = os.path.realpath(path)
        if os.path.dirname(real) != os.path.realpath(self.art_dir) or not os.path.isfile(real):
            return False
        with open(real, 'rb') as f:
            head = f.read(8)
        return any(head.startswith(m) for m in IMAGE_MAGIC) and os.path.getsize(real) <= MAX_IMAGE

    async def post(self, args):
        image = ''
        if args[1:2] == ['--image'] and len(args) > 2:
            image, args = args[2], args[:1] + args[3:]
        if len(args) < 2:
            print(USAGE)
            return 2
        tid, text = args[0], ' '.join(args[1:])
        if not await self.allowed(tid):
            print(f'refused: {tid} is neither a thread of the forum nor #general')
            return 3
        if image and not self.image_ok(image):
            print('refused: --image takes only a PNG/JPEG made by `discord-liaison art` (max 10 MB)')
            return 3
        parts = chunks(clean(text, [self.env.get(k, '') for k in SECRET_KEYS]))
        if self.env.get('LIAISON_DRY_RUN'):
            print(f'would post {len(parts)} message(s) to {tid}{" with " + image if image else ""}:\n' + '\n'.join(parts))
            return 0
        for i, part in enumerate(parts):
            if image and i == len(parts) - 1:
                await self.rest.send_file(tid, part, image)
            else:
                await self.rest.send(tid, part)
        print(f'posted {len(parts)} message(s){" with the image" if image else ""}')
        return 0

    async def react(self, args):
        if len(args) != 3:
            print(USAGE)
            return 2
        if not await self.allowed(args[0]):
            print(f'refused: {args[0]} is neither a thread of the forum nor #general')
            return 3
        await self.rest.react(*args)
        print(f'reacted {args[2]}')
        return 0

    def art(self, args):
        if not args:
            print(USAGE)
            return 2
        if not self.caps.take('img'):
            print(f'refused: image cap reached ({self.caps.limits["img"]} per day); say so in the thread')
            return 3
        os.makedirs(self.art_dir, exist_ok=True)
        out = os.path.join(self.art_dir, time.strftime('%Y%m%d-%H%M%S') + '.png')
        with open(out + '.prompt', 'w') as f:
            f.write(' '.join(args) + '\n')
        cmd = shlex.split(self.env.get('LIAISON_ART_CMD', 'concept-img')) + [
            '--model', self.env.get('LIAISON_ART_MODEL', 'bytedance-seed/seedream-5-0-flash'),
            '--prompt-file', out + '.prompt', '--resolution', '1K', '--out', out,
            '--log', os.path.join(self.art_dir, 'spend.tsv'), '--start', '0']
        rc = subprocess.call(cmd, stdin=subprocess.DEVNULL)
        if rc != 0 or not os.path.exists(out):
            print(f'art failed (concept-img exit {rc})')
            return 1
        print(out)
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
              f'  runs {self.caps.used("run")}/{self.caps.limits["run"]}  PRs {self.caps.used("pr")}/{self.caps.limits["pr"]}'
              f'  images {self.caps.used("img")}/{self.caps.limits["img"]}')
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
        if cmd in ('tick', 'post', 'react'):
            return await getattr(app, cmd)(args)
        if cmd == 'check':
            msgs, _ = await app.check()
            print(f'{len(msgs)} new, inbox {len(app.state.inbox)}')
            return 0
        if cmd in ('inbox', 'done', 'status'):
            return getattr(app, cmd)()
        if cmd in ('map', 'pr', 'art'):
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
