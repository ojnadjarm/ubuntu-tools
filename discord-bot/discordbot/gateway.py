"""discord.py adapter: raw gateway dispatches go to ForumBot in order; results are polled from the spool."""
import asyncio
import json
import logging
import time

import aiohttp
import discord

from .core import ForumBot
from .jobs import Spool
from .rest import Rest
from .store import RateLimiter, Store

log = logging.getLogger('discordbot')
WANTED = {'READY', 'CHANNEL_UPDATE', 'GUILD_CREATE', 'THREAD_CREATE', 'THREAD_UPDATE', 'MESSAGE_CREATE', 'MESSAGE_REACTION_ADD'}
AUTH_CLOSE = {4004, 4010, 4011, 4012, 4013, 4014}
DROPS = (OSError, asyncio.TimeoutError, aiohttp.ClientError, discord.GatewayNotFound, discord.HTTPException,
         discord.ConnectionClosed)


def intents():
    i = discord.Intents.none()
    i.guilds = i.guild_messages = i.guild_reactions = i.message_content = True
    return i


async def stay_connected(session, sleep=asyncio.sleep, clock=time.monotonic, cap=60):
    """Run gateway sessions until an auth error; each drop logs one line and retries after 1, 2, 4 … cap s."""
    delay = 1
    while True:
        start = clock()
        try:
            await session()
            why = 'closed'
        except DROPS as e:
            if isinstance(e, discord.ConnectionClosed) and e.code in AUTH_CLOSE:
                raise
            why = f'{type(e).__name__}: {e}'
        if clock() - start >= cap:
            delay = 1
        log.warning('gateway dropped (%s); reconnecting in %ds', why, delay)
        await sleep(delay)
        delay = min(delay * 2, cap)


async def run(cfg):
    token = cfg.token()
    store = Store(cfg.state_dir)
    store.set_status(started_at=int(time.time()), connected_at=None)
    rest = Rest(cfg.api_base, token, cfg.proxy)
    bot = ForumBot(cfg, rest, store, Spool(f'{cfg.state_dir}/jobs'), RateLimiter(f'{cfg.state_dir}/ratelimit.json'))
    queue = asyncio.Queue()

    async def on_socket_raw_receive(msg):
        try:
            p = json.loads(msg)
        except (TypeError, ValueError):
            return
        if p.get('op') == 0 and p.get('t') in WANTED:
            queue.put_nowait((p['t'], p['d']))

    async def session():
        client = discord.Client(intents=intents(), proxy=cfg.proxy or None, enable_debug_events=True,
                                max_messages=None, chunk_guilds_at_startup=False,
                                member_cache_flags=discord.MemberCacheFlags.none())
        client.event(on_socket_raw_receive)
        try:
            await client.login(token)
            await client.connect(reconnect=False)
        finally:
            await client.close()

    async def consume():
        while True:
            t, d = await queue.get()
            await bot.dispatch(t, d)

    async def poll_results():
        while True:
            await asyncio.sleep(cfg.poll_seconds)
            await bot.dispatch('TICK', {})
            for res in bot.spool.results():
                await bot.deliver(res)

    tasks = [asyncio.create_task(consume()), asyncio.create_task(poll_results())]
    try:
        await stay_connected(session)
    finally:
        for t in tasks:
            t.cancel()
        await rest.close()
