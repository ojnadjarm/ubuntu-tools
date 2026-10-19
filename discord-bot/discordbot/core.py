"""Forum logic: tag posts, acknowledge, queue answers, gate real work on the owner's approval, deliver results."""
import logging
import time

from .approval import tag_added_by
from .config import APPROVE_EMOJI, APPROVED_TAG, STATUS_TAGS
from .rest import RestError
from .sanitize import chunks, clean

log = logging.getLogger('discordbot')
FORUM = 15
ACK = ("Got it. I'm **agents**, the owner's helper bot; I'll answer here. Anything that changes his machine or runs "
       "real work waits for the owner's approval (the `approved` tag or his ✅).")
HELLO = ('agents is online', 'agents is online; post a request here')


class ForumBot:
    def __init__(self, cfg, rest, store, spool, rates, clock=time.time):
        self.cfg, self.rest, self.store, self.spool, self.rates, self.clock = cfg, rest, store, spool, rates, clock
        self.me_id = ''
        self.guild_id = ''
        self.owner_id = cfg.owner_id
        self.forum_id = ''
        self.tags = {}
        self.parent = {}
        self._tag_try = 0.0

    async def dispatch(self, t, d):
        handler = getattr(self, f'on_{t.lower()}', None)
        if handler is None:
            return
        try:
            await handler(d)
        except RestError as e:
            log.warning('%s failed: rest %s', t, e.status)
        self.store.set_status(last_event_at=int(self.clock()))

    async def on_ready(self, d):
        self.me_id = d['user']['id']
        self.store.set_status(bot_user=d['user'].get('username', ''), connected_at=int(self.clock()))

    async def on_guild_create(self, d):
        gid = d['id']
        if (self.cfg.guild_id and gid != self.cfg.guild_id) or (self.guild_id and gid != self.guild_id):
            log.warning('leaving unexpected guild %s', gid)
            await self.rest.leave_guild(gid)
            return
        self.guild_id = gid
        self.owner_id = self.cfg.owner_id or d.get('owner_id', '')
        forums = [c for c in d.get('channels', []) if c.get('type') == FORUM]
        forum = next((c for c in forums if c['id'] == self.cfg.forum_id), forums[0] if forums else None)
        if forum is None:
            self.store.set_status(guild={'id': gid, 'name': d.get('name', '')}, forum=None, problem='no forum channel')
            return
        self.forum_id = forum['id']
        for th in d.get('threads', []):
            self.parent[th['id']] = th.get('parent_id', '')
        self.store.set_status(guild={'id': gid, 'name': d.get('name', '')},
                              forum={'id': forum['id'], 'name': forum.get('name', '')}, owner_known=bool(self.owner_id))
        await self.ensure_tags()
        await self.hello()

    async def hello(self):
        """Post the hello once; tag it `done` as soon as that tag exists."""
        if not self.store.status.get('hello_thread'):
            tags = [self.tags['done']] if 'done' in self.tags else []
            post = await self.rest.create_post(self.forum_id, HELLO[0], HELLO[1], tags)
            self.store.set_status(hello_thread=post['id'], hello_tagged=bool(tags))
        elif not self.store.status.get('hello_tagged') and 'done' in self.tags:
            await self.rest.edit_channel(self.store.status['hello_thread'], applied_tags=[self.tags['done']])
            self.store.set_status(hello_tagged=True)

    async def on_tick(self, d):
        """Retry tag creation every 5 minutes while tags are missing (permission granted later)."""
        if self.forum_id and len(self.tags) < len(STATUS_TAGS) + 1 and self.clock() - self._tag_try >= 300:
            await self.ensure_tags()
            await self.hello()

    async def on_channel_update(self, d):
        if d['id'] == self.forum_id:
            self.tags = {t['name']: t['id'] for t in d.get('available_tags', [])}
            self.store.set_status(tags=sorted(self.tags))
            await self.hello()

    async def ensure_tags(self):
        self._tag_try = self.clock()
        ch = await self.rest.channel(self.forum_id)
        have = ch.get('available_tags', [])
        names = {t['name'] for t in have}
        missing = [n for n in STATUS_TAGS + (APPROVED_TAG,) if n not in names]
        if missing:
            new = [{'id': t['id'], 'name': t['name'], 'moderated': t.get('moderated', False),
                    'emoji_id': t.get('emoji_id'), 'emoji_name': t.get('emoji_name')} for t in have]
            new += [{'name': n, 'moderated': n == APPROVED_TAG} for n in missing]
            try:
                ch = await self.rest.edit_channel(self.forum_id, available_tags=new)
                have = ch.get('available_tags', [])
                self.store.set_status(problem=None)
            except RestError as e:
                err = f'{e.status} {(e.body or {}).get("code", "")} {(e.body or {}).get("message", "")}'.strip()
                log.warning('cannot create tags: rest %s', err)
                self.store.set_status(problem=f'cannot create tags {missing}: PATCH /channels/<forum> -> {err} '
                                              '(give the bot Manage Channels on the forum, or create the tags by hand)')
        self.tags = {t['name']: t['id'] for t in have}
        self.store.set_status(tags=sorted(self.tags))

    async def is_forum_thread(self, cid):
        if cid not in self.parent:
            try:
                ch = await self.rest.channel(cid)
                self.parent[cid] = ch.get('parent_id') or ''
                if self.parent[cid] == self.forum_id and not self.store.thread(cid):
                    self.store.put_thread(cid, requester=ch.get('owner_id', ''), title=ch.get('name', ''))
            except RestError:
                self.parent[cid] = ''
        return bool(self.forum_id) and self.parent[cid] == self.forum_id

    async def on_thread_create(self, d):
        self.parent[d['id']] = d.get('parent_id', '')
        if d.get('parent_id') != self.forum_id or d.get('owner_id') == self.me_id or not d.get('newly_created'):
            return
        self.store.put_thread(d['id'], requester=d.get('owner_id', ''), title=d.get('name', ''))
        await self.set_tag(d['id'], 'new')
        await self.rest.send(d['id'], ACK)

    async def on_message_create(self, d):
        author = d.get('author', {})
        if author.get('id') == self.me_id or d.get('type', 0) not in (0, 19):
            return
        tid = d['channel_id']
        if not await self.is_forum_thread(tid) or tid == self.store.status.get('hello_thread'):
            return
        if not d.get('content') and not d.get('attachments'):
            self.store.set_status(content_intent=False)
            log.warning('empty message content: Message Content intent off?')
            return
        self.store.set_status(content_intent=True)
        uid = author['id']
        if uid != self.owner_id and not self.rates.take('req', uid, self.cfg.requests_per_day):
            if self.rates.take('note', uid, 1):
                await self.rest.send(tid, f'Daily limit reached ({self.cfg.requests_per_day} requests). '
                                          'I will answer again tomorrow (UTC).')
            return
        th = self.store.thread(tid) or {}
        self.spool.put({'kind': 'answer', 'thread_id': tid, 'requester_id': th.get('requester') or uid,
                        'title': th.get('title', ''), 'messages': await self.history(tid)})

    async def history(self, tid):
        msgs = await self.rest.messages(tid, 20)
        return [{'author': m.get('author', {}).get('username', '?'), 'self': m.get('author', {}).get('id') == self.me_id,
                 'content': m.get('content', '')} for m in reversed(msgs)]

    async def on_thread_update(self, d):
        if d.get('parent_id') != self.forum_id or APPROVED_TAG not in self.tags:
            return
        tag = self.tags[APPROVED_TAG]
        if tag in d.get('applied_tags', []):
            th = self.store.thread(d['id']) or {}
            if th.get('work') in ('queued', 'done') or not self.owner_id:
                return
            try:
                who = await tag_added_by(self.rest, self.guild_id, d['id'], tag)
            except RestError as e:
                self.store.set_status(problem=f'cannot read the audit log (rest {e.status}): give the bot View Audit Log')
                return
            if who != self.owner_id:
                log.warning('thread %s: approved tag not set by the owner; ignored', d['id'])
                return
            if not th:
                self.store.put_thread(d['id'], requester=d.get('owner_id', ''), title=d.get('name', ''))
            await self.start_work(d['id'], {'kind': 'tag'})

    async def on_message_reaction_add(self, d):
        if d.get('emoji', {}).get('name') != APPROVE_EMOJI or not self.owner_id or d.get('user_id') != self.owner_id:
            return
        if await self.is_forum_thread(d['channel_id']):
            await self.start_work(d['channel_id'], {'kind': 'reaction', 'message_id': d['message_id']})

    async def start_work(self, tid, approval):
        th = self.store.thread(tid)
        if th is None or th.get('work') in ('queued', 'done'):
            return
        req = th.get('requester', '')
        if req != self.owner_id and not self.rates.take('job', req, self.cfg.jobs_per_day):
            await self.rest.send(tid, f'Approved, but this member has reached {self.cfg.jobs_per_day} jobs today; '
                                      'approve it again tomorrow (UTC).')
            return
        self.store.put_thread(tid, work='queued')
        await self.set_tag(tid, 'in progress')
        await self.rest.send(tid, 'Approved. Working on it; I will report back here.')
        self.spool.put({'kind': 'work', 'thread_id': tid, 'requester_id': req or '0', 'title': th.get('title', ''),
                        'messages': await self.history(tid), 'approval': approval,
                        'work_summary': th.get('work_summary', '')})

    async def set_tag(self, tid, name):
        if name not in self.tags:
            return
        ch = await self.rest.channel(tid)
        status_ids = {self.tags[n] for n in STATUS_TAGS if n in self.tags}
        keep = [t for t in ch.get('applied_tags', []) if t not in status_ids]
        await self.rest.edit_channel(tid, applied_tags=(keep + [self.tags[name]])[-5:])
        self.store.put_thread(tid, tag=name)

    async def say(self, tid, text):
        for part in chunks(clean(text)):
            await self.rest.send(tid, part)

    async def deliver(self, res):
        tid = res.get('thread_id', '')
        th = self.store.thread(tid)
        if th is None:
            return
        try:
            if res.get('kind') == 'work':
                self.store.put_thread(tid, work='done')
                await self.say(tid, res.get('reply') or 'The job finished without a report.')
                await self.set_tag(tid, 'done' if res.get('ok') else 'accepted')
                return
            await self.say(tid, res.get('reply') or 'Sorry, I could not answer that one.')
            if res.get('needs_work') and th.get('work') is None:
                summary = clean(str(res.get('work_summary', '')))[:300]
                self.store.put_thread(tid, needs_work=True, work_summary=summary)
                await self.set_tag(tid, 'accepted')
                if th.get('requester') in self.cfg.allowlist:
                    await self.start_work(tid, {'kind': 'allowlist'})
                else:
                    await self.rest.send(tid, f'This needs real work ({summary or "see above"}); '
                                              'it runs after the owner approves.')
            elif th.get('tag') == 'new':
                await self.set_tag(tid, 'done')
        except RestError as e:
            log.warning('deliver failed: rest %s', e.status)
