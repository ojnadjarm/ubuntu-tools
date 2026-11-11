"""Discord REST through a fixture vault broker (T1634-V8): MemorySealer, in-memory leases, fake Discord upstream."""
import asyncio
import os
import sys
import tempfile
import unittest

from aiohttp import web
from aiohttp.test_utils import TestServer

from discordbot.config import Config
from discordbot.rest import RestError
from discordbot.vault import LEASE_ENV, SECRET, LeaseSource, NoLease, make_rest
from tests.fake_rest import FakeDiscord

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'lib'))
from vault import listener, registry  # noqa: E402
from vault.audit import Audit  # noqa: E402
from vault.gate import Gate  # noqa: E402
from vault.grants import Grants  # noqa: E402
from vault.leases import Leases  # noqa: E402
from vault.proxy import Proxy  # noqa: E402
from vault.seal import MemorySealer  # noqa: E402

FAKE = b'fixture-discord-token-v8'
REPO_REGISTRY = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                             'vault', 'registry.toml')


class Broker:
    """The real gate, grants and proxy mode over a MemorySealer; grants answered in-process instead of the admin socket."""

    def __init__(self, tmp, upstream, clock):
        self.entry = registry.load(REPO_REGISTRY)[SECRET]
        self.sealer = MemorySealer()
        self.sealer.put(SECRET, FAKE)
        self.leases, self.audit = Leases(clock), Audit(os.path.join(tmp, 'uses.jsonl'))
        self.grants = Grants(self.leases, self.audit)
        self.gate = Gate(lambda: {SECRET: self.entry}, self.sealer, self.leases, self.audit,
                         {'proxy': Proxy(upstream=upstream)})
        self.server = listener.serve(self.gate, '127.0.0.1', 0)
        self.url = f'http://127.0.0.1:{self.server.server_address[1]}'
        self.asked = []

    def ask(self, path, req):
        self.asked.append(req['op'])
        if req['op'] == 'revoke':
            return self.grants.revoke(req, os.getuid())
        return self.grants.grant(self.entry, req, os.getuid())


class VaultRest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fake, self.seen = FakeDiscord(), []
        outer = web.Application(middlewares=[self.headers])
        outer.add_subapp('/api/v10/', self.fake.app())
        self.up = TestServer(outer)
        await self.up.start_server()
        self.now = [1000.0]
        self.broker = Broker(self.tmp.name, str(self.up.make_url('')), lambda: self.now[0])
        self.env = {'FLEET_VAULT_URL': self.broker.url, 'FLEET_VAULT_SOCKET': os.path.join(self.tmp.name, 'none.sock')}
        self.cfg = Config(token_file='', state_dir=self.tmp.name)
        self.rest = make_rest(self.cfg, self.env, 'T9008')
        self.rest.lease.ask, self.rest.lease.clock = self.broker.ask, lambda: self.now[0]

    async def asyncTearDown(self):
        await self.rest.close()
        self.broker.server.shutdown()
        await self.up.close()
        self.tmp.cleanup()

    @web.middleware
    async def headers(self, request, handler):
        self.seen.append(request.headers.get('Authorization', ''))
        return await handler(request)

    async def test_registry_row_is_discord_shaped(self):
        e = self.broker.entry
        self.assertEqual((e.cls, e.scheme, e.hosts), ('free', 'Bot', ('discord.com',)))
        self.assertEqual(set(e.methods), {'GET', 'POST', 'PUT', 'DELETE'})
        self.assertEqual(e.paths, ('/api/v10/',))

    async def test_calls_carry_the_bot_token_only_upstream(self):
        guilds = await self.rest.my_guilds()
        self.assertEqual(guilds[0]['name'], 'Family')
        self.assertEqual(self.seen, ['Bot ' + FAKE.decode()])
        self.assertNotIn('Authorization', self.rest._headers)
        self.assertNotIn(FAKE.decode(), self.rest.url('/x'))

    async def test_send_react_unreact_and_upload_pass(self):
        await self.rest.send('400', 'hola')
        await self.rest.react('400', '400', '👀')
        await self.rest.call('DELETE', '/users/@me/guilds/100')
        path = os.path.join(self.tmp.name, 'a.png')
        with open(path, 'wb') as f:
            f.write(b'\x89PNG\r\n\x1a\n' + b'0' * 2048)
        await self.rest.send_file('400', 'imagen', path)
        self.assertEqual(self.fake.sent('400'), ['hola', 'imagen'])
        self.assertEqual(self.fake.messages['400'][-1]['attachments'], [{'filename': 'a.png', 'size': 2056}])
        self.assertEqual((self.fake.my_emojis[('400', '400')], self.fake.left), (['👀'], ['100']))

    async def test_one_grant_renewed_before_it_ends(self):
        await self.rest.my_guilds()
        await self.rest.my_guilds()
        self.assertEqual(self.broker.asked, ['grant'])
        self.now[0] += 3600 - 299
        await self.rest.my_guilds()
        self.assertEqual(self.broker.asked, ['grant', 'grant'])

    async def test_a_launcher_lease_is_used_as_is(self):
        lid = self.broker.ask('', {'op': 'grant', 'name': SECRET, 'ticket': 'T9008', 'ttl': 60})['lease']
        src = LeaseSource({**self.env, LEASE_ENV: lid}, 'x', ask=lambda *a: self.fail('no grant with a given lease'))
        self.assertEqual(src.lease(), lid)

    async def test_refused_or_unreachable_is_a_rest_error(self):
        src = LeaseSource(self.env, 'x', ask=lambda *a: {'ok': False, 'error': 'asked from inside an agent'})
        with self.assertRaises(NoLease) as c:
            src.lease()
        self.assertIsInstance(c.exception, RestError)
        self.assertIn('inside an agent', c.exception.why)
        with self.assertRaises(NoLease):
            LeaseSource(self.env, 'x').lease()

    async def test_wrong_path_and_patch_are_refused(self):
        lid = self.rest.lease.lease()
        base = f'{self.broker.url}/{lid}/{SECRET}'
        import urllib.error
        import urllib.request
        for method, path in (('GET', '/api/v9/users/@me'), ('PATCH', '/api/v10/channels/400'), ('GET', '/api/v10/../x')):
            req = urllib.request.Request(base + path, method=method)
            with self.assertRaises(urllib.error.HTTPError) as c:
                await asyncio.to_thread(urllib.request.urlopen, req, timeout=5)
            self.assertIn(c.exception.code, (403, 405), (method, path))
        self.assertEqual(self.seen, [])

    async def test_worker_lease_minted_and_revoked(self):
        wid = self.rest.lease.mint('job-1', 900)
        self.assertTrue(wid)
        self.rest.lease.revoke(wid)
        self.assertEqual(self.broker.asked, ['grant', 'revoke'])
        with self.assertRaises(Exception):
            self.broker.leases.check(wid, SECRET)

    async def test_token_file_wins_while_it_exists(self):
        tok = os.path.join(self.tmp.name, 'tok')
        with open(tok, 'w') as f:
            f.write('file-token\n')
        r = make_rest(Config(token_file=tok, state_dir=self.tmp.name), self.env, 'x')
        try:
            self.assertIsNone(r.lease)
            self.assertEqual(r._headers['Authorization'], 'Bot file-token')
        finally:
            await r.close()
        self.assertIsNotNone(self.rest.lease)


if __name__ == '__main__':
    unittest.main()
