"""Who the bot answers in #general, and one tick at a time (T1413)."""
import os
import unittest

from liaison.runlock import run_lock
from liaison.watch import addressed
from tests.test_liaison import Base


def m(text='', mentions=(), roles=(), ref_author=None):
    out = {'content': text, 'mentions': [{'id': u} for u in mentions], 'mention_roles': list(roles)}
    if ref_author:
        out['referenced_message'] = {'author': {'id': ref_author}}
    return out


class TestAddressed(unittest.TestCase):
    def test_mention_role_reply_and_typed_name_count(self):
        self.assertTrue(addressed(m(mentions=['900']), '900', '950'))
        self.assertTrue(addressed(m(roles=['950']), '900', '950'))
        self.assertTrue(addressed(m('vale, gracias', ref_author='900'), '900', '950'))
        self.assertTrue(addressed(m('@agent Yo soy el owner 😩'), '900', '950'))
        self.assertTrue(addressed(m('oye @Agents, ¿qué tal?'), '900', '950'))

    def test_chatter_lookalikes_and_replies_to_others_do_not(self):
        for text in ('Parece que hay que mejorar mucho este Harness jumm', '@agentes del caos', 'x@agents.com',
                     'mira https://ejemplo.org/@agents', '`@agents` es el bot', '> @agents dijo', 'agents es un bot'):
            self.assertFalse(addressed(m(text), '900', '950'), text)
        self.assertFalse(addressed(m('jaja', ref_author='2'), '900', '950'))
        self.assertFalse(addressed(m(roles=['951']), '900', ''))


class TestGeneralTyped(Base):
    async def test_typed_name_and_reply_to_bot_reach_the_inbox(self):
        await self.run_cli('tick')
        self.fake.say('999', '1', '@agent Yo soy el owner 😩')
        self.fake.say('999', '1', 'hay que mejorar este harness')
        await self.run_cli('check')
        self.assertEqual([x['content'] for x in self.state().inbox], ['@agent Yo soy el owner 😩'])


class TestRunLock(Base):
    async def test_second_tick_while_a_run_holds_the_lock_takes_no_cap_and_keeps_work(self):
        await self.run_cli('tick')
        self.fake.say('999', '1', '<@900> hola', users=['900'])
        work = os.path.join(self.tmp.name, 'state', 'work')
        os.makedirs(work)
        with open(os.path.join(work, 'keep.png'), 'w') as f:
            f.write('x')
        with run_lock(os.path.join(self.tmp.name, 'state', 'tick.lock')) as held:
            self.assertTrue(held)
            rc, out = await self.run_cli('tick')
        self.assertEqual(rc, 0)
        self.assertIn('run in flight', out)
        self.assertTrue(os.path.exists(os.path.join(work, 'keep.png')))
        self.assertEqual(self.state().inbox, [])
        rc, out = await self.run_cli('tick')
        self.assertIn('1 new', out)
