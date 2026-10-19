"""Discord REST adapter: the few endpoints the bot and runner use, with 429 retry."""
import asyncio
from urllib.parse import quote

import aiohttp


class RestError(Exception):
    def __init__(self, status, body):
        super().__init__(f'discord rest {status}')
        self.status, self.body = status, body


class Rest:
    def __init__(self, base, token, proxy=''):
        self.base, self.proxy = base.rstrip('/'), proxy or None
        self._headers = {'Authorization': f'Bot {token}', 'User-Agent': 'DiscordBot (agents, 1.0)'}
        self._session = None

    async def close(self):
        if self._session:
            await self._session.close()

    async def call(self, method, path, json=None, params=None):
        if self._session is None:
            self._session = aiohttp.ClientSession(headers=self._headers)
        for _ in range(5):
            async with self._session.request(method, self.base + path, json=json, params=params,
                                             proxy=self.proxy) as r:
                if r.status == 429:
                    body = await r.json(content_type=None)
                    await asyncio.sleep(float(body.get('retry_after', 1)))
                    continue
                body = await r.json(content_type=None) if r.status != 204 else None
                if r.status >= 400:
                    raise RestError(r.status, body)
                return body
        raise RestError(429, None)

    async def my_guilds(self):
        return await self.call('GET', '/users/@me/guilds')

    async def me(self):
        return await self.call('GET', '/users/@me')

    async def guild(self, gid):
        return await self.call('GET', f'/guilds/{gid}')

    async def guild_channels(self, gid):
        return await self.call('GET', f'/guilds/{gid}/channels')

    async def channel(self, cid):
        return await self.call('GET', f'/channels/{cid}')

    async def edit_channel(self, cid, **fields):
        return await self.call('PATCH', f'/channels/{cid}', json=fields)

    async def messages(self, cid, limit=20):
        return await self.call('GET', f'/channels/{cid}/messages', params={'limit': str(limit)})

    async def send(self, cid, content):
        return await self.call('POST', f'/channels/{cid}/messages',
                               json={'content': content, 'allowed_mentions': {'parse': []}})

    async def create_post(self, forum_id, name, content, tag_ids):
        return await self.call('POST', f'/channels/{forum_id}/threads', json={
            'name': name, 'applied_tags': list(tag_ids),
            'message': {'content': content, 'allowed_mentions': {'parse': []}}})

    async def audit_log(self, gid, action_type, limit=50):
        return await self.call('GET', f'/guilds/{gid}/audit-logs',
                               params={'action_type': str(action_type), 'limit': str(limit)})

    async def reactors(self, cid, mid, emoji):
        return await self.call('GET', f'/channels/{cid}/messages/{mid}/reactions/{quote(emoji)}',
                               params={'limit': '100'})

    async def leave_guild(self, gid):
        return await self.call('DELETE', f'/users/@me/guilds/{gid}')
