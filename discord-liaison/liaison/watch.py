"""Read-only forum poll: new messages in the forum's active threads since a per-thread cursor."""


class Watcher:
    def __init__(self, rest, guild_id, forum_id):
        self.rest, self.guild_id, self.forum_id = rest, guild_id, forum_id
        self.me = ''

    async def threads(self):
        act = await self.rest.call('GET', f'/guilds/{self.guild_id}/threads/active')
        return [t for t in act.get('threads', []) if t.get('parent_id') == self.forum_id]

    async def poll(self, cursor):
        """Return (messages, cursor); an empty cursor only seeds it, so old history never wakes the LLM."""
        if not self.me:
            self.me = (await self.rest.me())['id']
        names = {t['id']: t['name'] for t in (await self.rest.channel(self.forum_id)).get('available_tags', [])}
        seed, cur, out = not cursor, dict(cursor, _seeded='1'), []
        for t in await self.threads():
            tid, last = t['id'], cursor.get(t['id'], '0')
            params = {'limit': '50'} if last == '0' else {'limit': '50', 'after': last}
            msgs = await self.rest.call('GET', f'/channels/{tid}/messages', params=params)
            for m in sorted((m for m in msgs if int(m['id']) > int(last)), key=lambda m: int(m['id'])):
                cur[tid] = m['id']
                a = m.get('author', {})
                if seed or a.get('id') == self.me:
                    continue
                out.append({'id': m['id'], 'thread_id': tid, 'thread': t.get('name', ''),
                            'tags': [names[i] for i in t.get('applied_tags', []) if i in names],
                            'author': a.get('global_name') or a.get('username', '?'), 'bot': bool(a.get('bot')),
                            'content': m.get('content', '')[:1500]})
            cur.setdefault(tid, '0')
        return out, cur
