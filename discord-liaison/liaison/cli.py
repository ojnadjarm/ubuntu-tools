"""discord-liaison tick|check|inbox|done|post|map|pr|status: the liaison's tools for #foro and #general (T1409, T1411)."""
import asyncio
import glob
import json
import math
import os
import shlex
import shutil
import subprocess
import sys
import time

import aiohttp
from discordbot.cli import write_config
from discordbot.config import Config
from discordbot.rest import Rest, RestError
from discordbot.runner import SECRET_KEYS
from discordbot.sanitize import chunks, clean

from .caps import Caps
from .registry import Registry
from .state import State
from .watch import CDN, MAX_ATTACHMENT, Watcher

GENERAL = '#general'
ME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
USAGE = ('usage: discord-liaison tick [--dry-run]|check|inbox|done|post <thread> [--image <png>] <text…>|'
         'react <thread> <message> <emoji>|art <prompt…>|escalate <message> <what…>|map <thread> <project>|pr <project>|status')
IMAGE_MAGIC = (b'\x89PNG\r\n\x1a\n', b'\xff\xd8\xff')
SEEN_MAGIC = IMAGE_MAGIC + (b'GIF87a', b'GIF89a')
MAX_IMAGE = 10 * 1024 * 1024
SHEET_FRAMES, SHEET_PX = 12, 2048


def _probe(path):
    """(frames, seconds) of an animation, by decoding it with ffprobe."""
    r = subprocess.run(['ffprobe', '-v', 'error', '-count_frames', '-select_streams', 'v:0', '-show_entries',
                        'stream=nb_read_frames:format=duration', '-of', 'json', path],
                       capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
    d = json.loads(r.stdout or '{}')
    frames = int((d.get('streams') or [{}])[0].get('nb_read_frames') or 0)
    try:
        secs = float(d.get('format', {}).get('duration'))
    except (TypeError, ValueError):
        secs = 0.0
    return frames, secs


def still(path):
    """Replace a GIF/WebP with one PNG contact sheet (up to 12 evenly sampled frames, numbered, in order); return a note.

    Read takes stills only. The file is dropped when ffmpeg cannot decode it."""
    png, kind = os.path.splitext(path)[0] + '.png', os.path.splitext(path)[1][1:].upper()
    note = ''
    try:
        frames, secs = _probe(path)
        if frames:
            k = min(SHEET_FRAMES, frames)
            pick = sorted({round(i * (frames - 1) / max(k - 1, 1)) for i in range(k)})
            cols = min(4, len(pick))
            rows = math.ceil(len(pick) / cols)
            cell = SHEET_PX // cols
            vf = (f"drawtext=text='%{{eif\\:n+1\\:d}}':x=6:y=6:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.7,"
                  f"select='{'+'.join(f'eq(n\\,{n})' for n in pick)}',"
                  f"scale='min({cell},iw)':'min({cell},ih)':force_original_aspect_ratio=decrease,tile={cols}x{rows}")
            rc = subprocess.call(['ffmpeg', '-v', 'error', '-nostdin', '-y', '-i', path, '-vf', vf, '-frames:v', '1',
                                  '-fps_mode', 'passthrough', png], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
            if rc == 0:
                note = (f'{kind}, {frames} frames, {secs:.1f} s: contact sheet of {len(pick)} frames sampled evenly, '
                        'numbered, in order')
    except (subprocess.TimeoutExpired, ValueError):
        pass
    os.unlink(path)
    if not note and os.path.exists(png):
        os.unlink(png)
    return note


class App:
    def __init__(self, env, rest):
        self.env, self.rest = env, rest
        self.home = env.get('LIAISON_HOME', ME)
        self.forum, self.guild = env.get('DISCORD_FORUM_ID', ''), env.get('DISCORD_GUILD_ID', '')
        self.general = env.get('DISCORD_GENERAL_ID', '')
        self.owner = env.get('DISCORD_OWNER_ID', '')
        self.state = State(os.path.join(self.home, 'state'))
        self.registry = Registry(env.get('LIAISON_REGISTRY', os.path.join(ME, 'projects.json')))
        os.makedirs(os.path.join(self.home, 'logs'), exist_ok=True)
        self.caps = Caps(os.path.join(self.home, 'state', 'caps.json'), os.path.join(self.home, 'logs', 'caps.log'),
                         {'run': int(env.get('LIAISON_RUNS_PER_DAY', '30')), 'pr': int(env.get('LIAISON_PRS_PER_DAY', '3')),
                          'img': int(env.get('LIAISON_IMAGES_PER_DAY', '5'))})
        self.art_dir = os.path.join(self.home, 'state', 'art')
        self.work = os.path.join(self.home, 'state', 'work')
        self.cdn = tuple(env.get('LIAISON_CDN_PREFIXES', ' '.join(CDN)).split())

    async def general_id(self, save):
        """#general's id: DISCORD_GENERAL_ID, else the guild's text channel named general, stored in config.env."""
        if not self.general:
            chans = await self.rest.guild_channels(self.guild)
            self.general = next((c['id'] for c in chans if c.get('type') == 0 and c.get('name') == 'general'), '')
            if self.general and save:
                write_config({'DISCORD_GENERAL_ID': self.general}, self.env.get('HARNESS_CONFIG'))
        return self.general

    async def check(self, save=True):
        w = Watcher(self.rest, self.guild, self.forum, self.cdn)
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
        await self.fetch_images()
        cmd = self.env.get('LIAISON_AGENT_CMD', 'agent-run discord-liaison')
        try:
            return subprocess.call(cmd, shell=True, stdin=subprocess.DEVNULL)
        finally:
            shutil.rmtree(self.work, ignore_errors=True)

    async def fetch_images(self):
        """Download the inbox's images into state/work for this run: CDN only, no token, <= 8 MB, magic checked."""
        os.makedirs(self.work, exist_ok=True)
        async with aiohttp.ClientSession() as http:
            for m in self.state.inbox:
                for i, a in enumerate(m.get('attachments', [])):
                    if not a['url'].startswith(self.cdn):
                        continue
                    ext = os.path.splitext(a['filename'])[1].lower()
                    dest = os.path.join(self.work, f'{m["id"]}-{i}{ext}')
                    try:
                        async with http.get(a['url'], allow_redirects=False) as r:
                            data = b''
                            if r.status == 200:
                                async for chunk in r.content.iter_chunked(65536):
                                    data += chunk
                                    if len(data) > MAX_ATTACHMENT:
                                        break
                    except aiohttp.ClientError:
                        data = b''
                    webp = data[:4] == b'RIFF' and data[8:12] == b'WEBP'
                    if 0 < len(data) <= MAX_ATTACHMENT and (data.startswith(SEEN_MAGIC) or webp):
                        with open(dest, 'wb') as f:
                            f.write(data)
                        if ext in ('.gif', '.webp'):
                            note = still(dest)
                            if note:
                                with open(os.path.splitext(dest)[0] + '.note', 'w') as f:
                                    f.write(note)

    def images(self, mid):
        return sorted(p for p in glob.glob(os.path.join(glob.escape(self.work), f'{mid}-*')) if not p.endswith('.note'))

    def note(self, image):
        try:
            with open(os.path.splitext(image)[0] + '.note') as f:
                return f.read().strip()
        except OSError:
            return ''

    def inbox(self):
        self.state.mark_shown()
        for m in self.state.inbox:
            pid = (self.state.thread(m['thread_id']) or {}).get('project', '')
            route = self.registry.route(pid) if pid else ''
            body = m['content'].replace('</message', '<\\/message')
            imgs = self.images(m['id'])
            images = f' images="{" ".join(imgs)}"' if imgs else ''
            notes = ''.join(f'\n[{p}: {self.note(p)}]' for p in imgs if self.note(p))
            owner = str(bool(self.owner) and m.get('author_id') == self.owner).lower()
            print(f'<message channel="{m.get("channel", "foro")}" thread="{m["thread_id"]}" title="{m["thread"]}" '
                  f'tags="{",".join(m["tags"])}" project="{pid}" route="{route}" author="{m["author"]}" '
                  f'bot="{str(m["bot"]).lower()}" owner="{owner}" id="{m["id"]}"{images}>\n'
                  f'{body}{notes}\n</message>')
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

    def escalate(self, args):
        """Hand a request beyond the liaison's tools or rules to the orchestrator: state/escalations/<utc>-<msg>.md."""
        m = next((m for m in self.state.inbox if args and m['id'] == args[0]), None)
        if len(args) < 2 or m is None:
            print('usage: discord-liaison escalate <message-id from the inbox> "<what is asked; what you tried>"')
            return 2
        d = os.path.join(self.home, 'state', 'escalations')
        if glob.glob(os.path.join(glob.escape(d), f'*-{m["id"]}.md')) + glob.glob(
                os.path.join(glob.escape(d), 'done', f'*-{m["id"]}.md')):
            print(f'refused: message {m["id"]} is already escalated (open or done)')
            return 3
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, f'{time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())}-{m["id"]}.md')
        who = ' (owner)' if self.owner and m.get('author_id') == self.owner else ''
        with open(path, 'w') as f:
            f.write(f'# Discord escalation\n\nchannel: {m.get("channel", "foro")} ({m["thread_id"]})\nmessage: {m["id"]}\n'
                    f'author: {m["author"]}{who}\n\n## Request\n\n{m["content"]}\n\n## What the liaison tried\n\n'
                    f'{" ".join(args[1:])}\n\nAnswer in the channel, then move this file to done/.\n')
        cmd = self.env.get('LIAISON_PULSE_CMD', 'orchestrator-pulse')
        subprocess.call(cmd, shell=True, stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f'escalated to the orchestrator: {path}')
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
        if cmd == 'escalate':
            return app.escalate(args)
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
