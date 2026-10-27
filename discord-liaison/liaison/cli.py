"""discord-liaison tick|wake|check|inbox|done|post|map|pr|job|status: the liaison's tools for #foro and #general (T1409, T1411, T1414, T1421)."""
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
from urllib.parse import quote

import aiohttp
from discordbot.cli import write_config
from discordbot.config import Config
from discordbot.rest import Rest, RestError
from discordbot.runner import SECRET_KEYS
from discordbot.sanitize import chunks, clean

from .caps import Caps
from .context import ContextRenderer, self_line
from .history import History
from .jobs import JobQueue
from .routing import BLOCKERS, MAX_ATTEMPTS, after_failure, route
from .registry import Registry
from .runlock import run_lock
from .state import State
from .threads import batch, key, merge, newer
from .wake import debounce
from .watch import CDN, MAX_ATTACHMENT, Watcher

GENERAL = '#general'
ME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
USAGE = ('usage: discord-liaison tick [--dry-run]|wake|check|inbox|done|post <thread> [--image <file>] [--reply <message>] <text…>|'
         'react <thread> <message> <emoji>|art <prompt…>|escalate <message> <blocker> <what…>|map <thread> <project>|pr <project>|'
         'job <message> <task…>|job-run <id>|status')
STALE = ('refused: stale: a newer message from the requester or the owner is waiting in this conversation; do not post '
         'or react. The triage run handles it (it may replace this job). End with `stale: <what you made>`.')
FAILED = '{author}, no he podido terminarlo. Lo paso al orquestador y te respondo aquí.'
IMAGE_MAGIC = (b'\x89PNG\r\n\x1a\n', b'\xff\xd8\xff')
SEEN_MAGIC = IMAGE_MAGIC + (b'GIF87a', b'GIF89a')
MAX_IMAGE = 10 * 1024 * 1024
MAX_MEDIA = 25 * 1024 * 1024
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
        self.jobs = JobQueue(os.path.join(self.home, 'state', 'jobs'))
        self.job_cap = int(env.get('LIAISON_JOBS_MAX', '3'))
        self.nudge_file = env.get('LIAISON_NUDGE', os.path.join(os.path.dirname(ME), 'discord-bot', 'state', 'liaison.nudge'))

    def locked(self):
        """The state lock: `check`, `inbox` and `done` read-modify-write inbox.json one at a time."""
        return run_lock(os.path.join(self.home, 'state', 'state.lock'), wait=True)

    def reload(self):
        self.state = State(os.path.join(self.home, 'state'))

    async def general_id(self, save):
        """#general's id: DISCORD_GENERAL_ID, else the guild's text channel named general, stored in config.env."""
        if not self.general:
            chans = await self.rest.guild_channels(self.guild)
            self.general = next((c['id'] for c in chans if c.get('type') == 0 and c.get('name') == 'general'), '')
            if self.general and save:
                write_config({'DISCORD_GENERAL_ID': self.general}, self.env.get('HARNESS_CONFIG'))
        return self.general

    async def check(self, save=True):
        """Poll; with `save`, store new messages in the inbox and ack each human one with 👀 at once (T1421)."""
        if not save:
            return await self.poll(False)
        with self.locked():
            self.reload()
            msgs, cur = await self.poll(True)
        for m in msgs:
            if not m['bot']:
                try:
                    await self.rest.react(m['thread_id'], m['id'], '👀')
                except RestError:
                    pass
        return msgs, cur

    async def poll(self, save):
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
        await self.dispatch()
        with run_lock(os.path.join(self.home, 'state', 'tick.lock'), wait=args == ['--wait']) as held:
            if not held:
                print('run in flight: this tick does nothing')
                return 0
            return await self.run_tick()

    async def wake(self):
        """The bot's nudge: check (inbox + 👀) on every nudge, one tick once nudges are LIAISON_DEBOUNCE s quiet."""
        async def ack():
            msgs, _ = await self.check()
            print(f'{len(msgs)} new, inbox {len(self.state.inbox)}')
        await debounce(self.nudge_file, float(self.env.get('LIAISON_DEBOUNCE', '20')), ack, lambda: self.tick(['--wait']))
        return 0

    async def run_tick(self):
        msgs, _ = await self.check()
        print(f'{len(msgs)} new, inbox {len(self.state.inbox)}')
        self.nudge()
        if not self.state.inbox:
            return 0
        if not self.caps.take('run'):
            return 0
        await self.fetch_images()
        await self.write_context()
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

    async def write_context(self):
        """Render the inbox channels' recent turns into state/work/context.txt for this run's `inbox`."""
        me = (await self.rest.me())['id']
        names = {m['thread_id']: m['thread'] for m in self.state.inbox}
        hist = History(self.rest)
        channels = [(name, await hist.recent(tid)) for tid, name in names.items()]
        text = ContextRenderer(me, self.owner).render(
            channels, [m['id'] for m in self.state.inbox], self_line(self.caps.limits['img'] - self.caps.used('img')))
        os.makedirs(self.work, exist_ok=True)
        with open(os.path.join(self.work, 'context.txt'), 'w') as f:
            f.write(text + '\n')

    def images(self, mid):
        return sorted(p for p in glob.glob(os.path.join(glob.escape(self.work), f'{mid}-*')) if not p.endswith('.note'))

    def note(self, image):
        try:
            with open(os.path.splitext(image)[0] + '.note') as f:
                return f.read().strip()
        except OSError:
            return ''

    def inbox(self):
        with self.locked():
            self.reload()
            self.state.mark_shown()
        try:
            with open(os.path.join(self.work, 'context.txt')) as f:
                print(f.read(), end='')
        except OSError:
            print('<context kind="data">historial no disponible</context>')
        convs = batch(self.state.inbox)
        for conv in convs:
            for j in self.jobs.live(key(conv[-1])):
                task = j['task'].replace('"', '&quot;')
                print(f'<live-job id="{j["id"]}" status="{j["status"]}" message="{j["message"]["id"]}" task="{task}"/>')
            for m in conv:
                self.print_message(m, m is conv[-1])
        print(f'{len(self.state.inbox)} message(s) in {len(convs)} conversation(s); run `discord-liaison done` after '
              'answering them')
        return 0

    def print_message(self, m, newest):
        pid = (self.state.thread(m['thread_id']) or {}).get('project', '')
        route = self.registry.route(pid) if pid else ''
        body = m['content'].replace('</message', '<\\/message')
        imgs = self.images(m['id'])
        images = f' images="{" ".join(imgs)}"' if imgs else ''
        notes = ''.join(f'\n[{p}: {self.note(p)}]' for p in imgs if self.note(p))
        owner = str(bool(self.owner) and m.get('author_id') == self.owner).lower()
        print(f'<message channel="{m.get("channel", "foro")}" thread="{m["thread_id"]}" title="{m["thread"]}" '
              f'tags="{",".join(m["tags"])}" project="{pid}" route="{route}" author="{m["author"]}" '
              f'bot="{str(m["bot"]).lower()}" owner="{owner}" id="{m["id"]}" newest="{str(newest).lower()}"{images}>\n'
              f'{body}{notes}\n</message>')

    async def done(self):
        """Clear what `inbox` showed; a live job keeps its conversation's newer messages as seen; a message no job covers
        and no escalation names drops its 👀."""
        with self.locked():
            self.reload()
            shown = [m for m in self.state.inbox if m['id'] in set(self.state.shown)]
            n = len(self.state.shown)
            self.state.drop_shown()
        for conv in batch(shown):
            self.jobs.seen(key(conv[-1]), conv[-1]['id'])
        kept = {x['id'] for j in self.jobs.list() for x in j.get('messages', [j['message']])}
        esc = os.path.join(self.home, 'state', 'escalations')
        for m in shown:
            if m['bot'] or m['id'] in kept or glob.glob(os.path.join(glob.escape(esc), f'*-{m["id"]}.md')):
                continue
            try:
                await self.rest.call('DELETE', f'/channels/{m["thread_id"]}/messages/{m["id"]}/reactions/{quote("👀")}/@me')
            except RestError:
                pass
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
        """A PNG/JPEG made by `art` (<= 10 MB), or a PNG/JPEG/GIF/WebP/MP4 inside a job's folder (<= 25 MB)."""
        real = os.path.realpath(path)
        if not os.path.isfile(real):
            return False
        with open(real, 'rb') as f:
            head = f.read(12)
        size = os.path.getsize(real)
        if os.path.dirname(real) == os.path.realpath(self.art_dir):
            return head.startswith(IMAGE_MAGIC) and size <= MAX_IMAGE
        rel = os.path.relpath(real, os.path.realpath(self.jobs.dir))
        media = head.startswith(SEEN_MAGIC) or (head[:4] == b'RIFF' and head[8:12] == b'WEBP') or head[4:8] == b'ftyp'
        return not rel.startswith('..') and os.sep in rel and media and size <= MAX_MEDIA

    async def post(self, args):
        opts = {'--image': '', '--reply': ''}
        while args[1:2] and args[1] in opts and len(args) > 2:
            opts[args[1]], args = args[2], args[:1] + args[3:]
        image, reply = opts['--image'], opts['--reply']
        if len(args) < 2:
            print(USAGE)
            return 2
        tid, text = args[0], ' '.join(args[1:])
        if not await self.allowed(tid):
            print(f'refused: {tid} is neither a thread of the forum nor #general')
            return 3
        if await self.stale(tid):
            print(STALE)
            return 4
        if image and not self.image_ok(image):
            print('refused: --image takes a PNG/JPEG made by `discord-liaison art` (max 10 MB) '
                  'or a PNG/JPEG/GIF/WebP/MP4 in your job folder (max 25 MB)')
            return 3
        parts = chunks(clean(text, [self.env.get(k, '') for k in SECRET_KEYS]))
        if self.env.get('LIAISON_DRY_RUN'):
            print(f'would post {len(parts)} message(s) to {tid}{" with " + image if image else ""}:\n' + '\n'.join(parts))
            return 0
        for i, part in enumerate(parts):
            ref = reply if i == 0 else ''
            if image and i == len(parts) - 1:
                await self.rest.send_file(tid, part, image, reply=ref)
            else:
                await self.rest.send(tid, part, reply=ref)
        print(f'posted {len(parts)} message(s){" with the image" if image else ""}')
        return 0

    async def stale(self, tid):
        """From a job (LIAISON_JOB) posting in its own thread: a newer message from the requester (or the owner, in the
        forum) not yet triaged makes the result stale; wait up to LIAISON_STALE_WAIT s for the triage, then True."""
        jid = self.env.get('LIAISON_JOB', '')
        job = self.jobs.get(jid) if jid else None
        if job is None or job['message']['thread_id'] != tid:
            return False
        m, general = job['message'], job['message'].get('channel') == 'general'
        authors = {m.get('author_id')} | (set() if general else {self.owner})
        me, role = await Watcher(self.rest, self.guild, self.forum).ident() if general else ('', '')
        deadline = time.time() + float(self.env.get('LIAISON_STALE_WAIT', '90'))
        while True:
            job = self.jobs.get(jid)
            if job['status'] == 'superseded':
                break
            raw = await self.rest.messages(tid, 50)
            if not newer(raw, job.get('through', m['id']), authors - {''}, general, me, role):
                if job.pop('stale', None):
                    self.jobs.save(job)
                return False
            if time.time() >= deadline:
                break
            await asyncio.sleep(5)
        job['stale'] = True
        self.jobs.save(job)
        return True

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
        out = os.path.join(self.art_dir, time.strftime('%Y%m%d-%H%M%S') + f'-{os.getpid()}.png')
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

    def pulse(self):
        subprocess.call(self.env.get('LIAISON_PULSE_CMD', 'orchestrator-pulse'), shell=True, stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def nudge(self):
        """Pulse again while an open escalation is missing from the pulse's last-fire snapshot (it skips when busy)."""
        open_ = set(glob.glob(os.path.join(glob.escape(self.home), 'state', 'escalations', '*.md')))
        snap = self.env.get('PULSE_QUEUE', os.path.expanduser('~/agents/log/pulse-queue.json'))
        try:
            with open(snap) as f:
                sent = set(json.load(f).get('escalations', []))
        except (OSError, ValueError):
            sent = set()
        if open_ - sent:
            self.pulse()

    def escalate(self, args):
        """Hand a blocked request to the orchestrator: state/escalations/<utc>-<msg>.md naming the blocker."""
        msgs = self.state.inbox + [j['message'] for j in self.jobs.list()]
        m = next((m for m in msgs if args and m['id'] == args[0]), None)
        usage = (f'usage: discord-liaison escalate <message-id from the inbox or a job> <{"|".join(BLOCKERS)}> '
                 '"<what is asked; what was tried>"')
        if len(args) < 2 or m is None:
            print(usage)
            return 2
        if route(args[1]) == 'job':
            print(f'refused: not blocked; hand the work to a worker: discord-liaison job {m["id"]} "<task>". '
                  f'Escalate only for: {"; ".join(f"{k} = {v}" for k, v in BLOCKERS.items())}')
            return 3
        if len(args) < 3:
            print(usage)
            return 2
        path = self.write_escalation(m, args[1], ' '.join(args[2:]))
        if not path:
            print(f'refused: message {m["id"]} is already escalated (open or done)')
            return 3
        print(f'escalated to the orchestrator: {path}')
        return 0

    def write_escalation(self, m, blocker, tried):
        """Write the escalation file and pulse; None when this message was escalated before."""
        d = os.path.join(self.home, 'state', 'escalations')
        if glob.glob(os.path.join(glob.escape(d), f'*-{m["id"]}.md')) + glob.glob(
                os.path.join(glob.escape(d), 'done', f'*-{m["id"]}.md')):
            return None
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, f'{time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())}-{m["id"]}.md')
        who = ' (owner)' if self.owner and m.get('author_id') == self.owner else ''
        with open(path, 'w') as f:
            f.write(f'# Discord escalation\n\nchannel: {m.get("channel", "foro")} ({m["thread_id"]})\nmessage: {m["id"]}\n'
                    f'author: {m["author"]}{who}\nblocker: {blocker} ({BLOCKERS[blocker]})\n\n## Request\n\n{m["content"]}\n\n## What the liaison tried\n\n'
                    f'{tried}\n\nAnswer in the channel, then move this file to done/.\n')
        self.pulse()
        return path

    def job(self, args):
        """Hand a conversation to one background worker: anchored on its newest message, all its messages and images
        carried, a live job of the same conversation stopped and replaced (T1421)."""
        m = next((m for m in self.state.inbox if args and m['id'] == args[0]), None)
        if len(args) < 2 or m is None:
            print('usage: discord-liaison job <message-id from the inbox> "<task: deliverable, project, skills>"')
            return 2
        conv = [x for x in merge(self.state.inbox) if key(x) == key(m)]
        if conv[-1]['id'] != m['id']:
            print(f'note: {m["id"]} is not the newest message of its conversation; the job answers {conv[-1]["id"]}')
            m = conv[-1]
        if any(j['message']['id'] == m['id'] for j in self.jobs.list()):
            print(f'refused: message {m["id"]} already has a job')
            return 3
        old = self.jobs.supersede(key(m), self.stop)
        pid = (self.state.thread(m['thread_id']) or {}).get('project', '')
        extra = {'project': pid, 'route': self.registry.route(pid) if pid else ''}
        msgs = [dict(x, **extra, owner=bool(self.owner) and x.get('author_id') == self.owner)
                for x in merge(*[j.get('messages', [j['message']]) for j in old], conv)]
        ctx = os.path.join(self.work, 'context.txt')
        files = [f for x in conv for f in self.images(x['id'])] + [
            f for j in old for f in j.get('files', []) if os.path.exists(f) and not f.endswith('.txt')]
        job = self.jobs.create(msgs[-1], ' '.join(args[1:]), files + ([ctx] if os.path.exists(ctx) else []), msgs)
        for j in old:
            self.jobs.finish(j, 'superseded', f'replaced by {job["id"]}')
        started, failed = self.jobs.dispatch(self.job_cap, self.launch)
        print(f'job {job["id"]} {"started" if job["id"] in started else "failed to start" if failed else "queued"}'
              f' ({len(self.jobs.list("running"))}/{self.job_cap} running)'
              + (f'; it replaces {", ".join(j["id"] for j in old)}' if old else ''))
        return 0

    def stop(self, jid):
        """Stop a superseded job's transient unit and wait for it (LIAISON_JOB_STOP overrides)."""
        tmpl = self.env.get('LIAISON_JOB_STOP')
        if tmpl:
            return subprocess.call(tmpl.format(id=shlex.quote(jid)), shell=True, stdin=subprocess.DEVNULL)
        return subprocess.call(['systemctl', '--user', 'stop', f'discord-liaison-job-{jid}.service'],
                               stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def launch(self, jid):
        """Start `discord-liaison job-run <id>` outside this run: a transient user unit (LIAISON_JOB_LAUNCH overrides)."""
        tmpl = self.env.get('LIAISON_JOB_LAUNCH')
        if tmpl:
            return subprocess.call(tmpl.format(id=shlex.quote(jid)), shell=True, stdin=subprocess.DEVNULL)
        t = int(self.env.get('LIAISON_JOB_TIMEOUT', '1800'))
        return subprocess.call(['systemd-run', '--user', '--quiet', '--collect', f'--unit=discord-liaison-job-{jid}',
                                f'--property=RuntimeMaxSec={t + 300}', f'--setenv=PATH={os.environ.get("PATH", "")}',
                                os.path.join(os.path.dirname(ME), 'bin', 'discord-liaison'), 'job-run', jid],
                               stdin=subprocess.DEVNULL)

    async def dispatch(self):
        """Fail jobs whose runner died, then start queued jobs up to LIAISON_JOBS_MAX."""
        for j in self.jobs.reap():
            await self.notify_failure(j, 'runner lost')
        for j in self.jobs.dispatch(self.job_cap, self.launch)[1]:
            await self.notify_failure(j, 'launch failed')

    async def notify_failure(self, job, why):
        """After the last attempt: a short Spanish note in the request's thread, then an escalation to the orchestrator."""
        m = job['message']
        try:
            await self.post([m['thread_id'], FAILED.format(author=m['author'])])
        except RestError:
            pass
        self.write_escalation(m, 'attempts', f'background job {job["id"]} failed {job.get("attempt", 1)} times '
                                             f'(last: {why}); task: {job["task"]}')

    def job_prompt(self, job):
        """JOB.md, BRIEF.md's Rules, then the job: task, message and the triage run's context, as data."""
        with open(os.path.join(ME, 'JOB.md')) as f:
            head = f.read()
        with open(os.path.join(ME, 'BRIEF.md')) as f:
            brief = f.read()
        rules = brief[brief.index('## Rules'):]
        rules = rules[:rules.find('\n## ', 1) + 1 or None]
        m, d = job['message'], os.path.join(self.jobs.dir, job['id'])
        ctx = os.path.join(d, 'context.txt')
        context = ''
        if os.path.exists(ctx):
            with open(ctx) as f:
                context = f.read()
        imgs = [p for p in job['files'] if not p.endswith(('.txt', '.note'))]
        msgs = []
        for x in job.get('messages', [m]):
            mine = [p for p in imgs if os.path.basename(p).startswith(f'{x["id"]}-')]
            images = f' images="{" ".join(mine)}"' if mine else ''
            body = x['content'].replace('</message', '<\\/message')
            msgs.append(f'<message channel="{x.get("channel", "foro")}" thread="{x["thread_id"]}" title="{x["thread"]}" '
                        f'project="{x.get("project", "")}" route="{x.get("route", "")}" author="{x["author"]}" '
                        f'owner="{str(x.get("owner", False)).lower()}" id="{x["id"]}" '
                        f'newest="{str(x["id"] == m["id"]).lower()}"{images}>\n{body}\n</message>\n')
        text = (f'{head}\n{rules}\n## Your job\n\njob: {job["id"]}\nattempt: {job.get("attempt", 1)} of {MAX_ATTEMPTS}\n'
                f'task (from the triage run): {job["task"]}\nrequest: the <message newest="true"> below, verbatim; the '
                f'messages before it are the same conversation, oldest first: the newest wins, a correction replaces '
                f'what it corrects\nmust: reply in Spanish only; anything audiovisual is AAA, shocking and breathtaking; '
                f'post the result and react ✅ yourself\n\n{context}' + ''.join(msgs))
        path = os.path.join(d, 'prompt.md')
        with open(path, 'w') as f:
            f.write(text)
        return path

    async def job_run(self, args):
        """The worker's runner: hold the job lock, run the agent (a failed run is retried once), then start the next job."""
        job = self.jobs.get(args[0]) if args else None
        if job is None or job['status'] not in ('queued', 'running'):
            print('refused: no queued or running job with that id')
            return 3
        with run_lock(os.path.join(self.jobs.dir, job['id'], 'lock')) as held:
            if not held:
                print('job already running')
                return 0
            job.update(status='running', started=time.time())
            self.jobs.save(job)
            logs = os.path.join(self.home, 'logs', 'jobs')
            os.makedirs(logs, exist_ok=True)
            while True:
                q = {k: shlex.quote(v) for k, v in {
                    'prompt': self.job_prompt(job), 'id': job['id'], 'home': self.home, 'model': self.env.get('MODEL', 'opus'),
                    'timeout': self.env.get('LIAISON_JOB_TIMEOUT', '1800'), 'logs': logs,
                    'preamble': os.path.join(os.path.dirname(ME), 'AGENT-PREAMBLE.md')}.items()}
                cmd = self.env.get('LIAISON_WORKER_CMD', (
                    'agent-exec --prompt-file {prompt} --system-file {preamble} --model {model} --cwd {home} '
                    '--name discord-liaison-job --timeout {timeout} --raw-out {logs}/{id}.json --meta-out {logs}/{id}.meta.json '
                    '>>{logs}/{id}.log 2>&1')).format(**q)
                rc = subprocess.call(cmd, shell=True, stdin=subprocess.DEVNULL, env=dict(os.environ, LIAISON_JOB=job['id']))
                job = self.jobs.get(job['id'])
                if job['status'] == 'superseded':
                    print(f'job {job["id"]} superseded')
                    return 0
                if rc == 0 or job.get('stale') or after_failure(job.get('attempt', 1)) == 'escalate':
                    break
                job['attempt'] = job.get('attempt', 1) + 1
                self.jobs.save(job)
            if job.get('stale'):
                self.jobs.finish(job, 'stale', 'a newer message came; result not posted')
            else:
                self.jobs.finish(job, 'done' if rc == 0 else 'failed', f'exit {rc}')
            if rc == 0 and not job.get('stale'):
                for x in job.get('messages', [job['message']]):
                    try:
                        await self.rest.react(x['thread_id'], x['id'], '✅')
                    except RestError:
                        pass
            elif rc != 0 and not job.get('stale'):
                await self.notify_failure(job, f'worker exit {rc}')
        await self.dispatch()
        print(f'job {job["id"]} {job["status"]} (exit {rc})')
        return rc

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
              f'  images {self.caps.used("img")}/{self.caps.limits["img"]}'
              f'  jobs running {len(self.jobs.list("running"))}/{self.job_cap} queued {len(self.jobs.list("queued"))}')
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
        if cmd == 'job-run':
            return await app.job_run(args)
        if cmd in ('wake', 'done'):
            return await getattr(app, cmd)()
        if cmd == 'check':
            msgs, _ = await app.check()
            print(f'{len(msgs)} new, inbox {len(app.state.inbox)}')
            return 0
        if cmd in ('inbox', 'status'):
            return getattr(app, cmd)()
        if cmd in ('map', 'pr', 'art', 'job'):
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
