"""T1412 P5: messages of a project with a `po` go to that PO once (po-ask); the PO's outbox replies are posted to their thread."""
import io
import json
import os
import shlex
import unittest
from contextlib import redirect_stdout

from liaison import po
from liaison.cli import App

from .test_liaison import Base


class TestPO(Base):
    async def asyncSetUp(self):
        await super().asyncSetUp()
        self.asklog = os.path.join(self.tmp.name, 'ask.log')
        self.env['LIAISON_PO_HOME'] = os.path.join(self.tmp.name, 'agents')
        self.env['LIAISON_PO_ASK'] = f"sh -c {shlex.quote('printf \"%s|\" \"$@\" >>' + self.asklog + '; echo >>' + self.asklog)} fake"
        self.outbox = os.path.join(self.tmp.name, 'agents', 'po-other', 'outbox', 'discord')
        os.makedirs(self.outbox)

    async def message(self, project):
        await self.run_cli('tick')
        mid = self.fake.say('400', '2', 'quiero un sonido nuevo')
        await self.run_cli('check')
        await self.run_cli('map', '400', project)
        return mid

    async def test_po_routed_message_handed_off_once(self):
        mid = await self.message('other')
        self.assertEqual(po.handoff(App(self.env, self.rest), self.env), 1)
        self.assertEqual(po.handoff(App(self.env, self.rest), self.env), 0)
        with open(self.asklog) as f:
            lines = f.read().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertTrue(lines[0].startswith('other|--from|liaison|--channel|discord|--thread|400|--copy|'))
        self.assertIn(f'message {mid}): quiero un sonido nuevo|', lines[0])

    async def test_liaison_project_not_handed_off(self):
        await self.message('ten')
        self.assertEqual(po.handoff(App(self.env, self.rest), self.env), 0)
        self.assertFalse(os.path.exists(self.asklog))

    async def test_relay_posts_replies_and_refuses_bad_files(self):
        for name, body in (('a.md', 'thread: 400\nListo, ya está'), ('b.md', 'thread: 999\nfuera del foro'),
                           ('c.md', 'sin hilo')):
            with open(os.path.join(self.outbox, name), 'w') as f:
                f.write(body)
        with redirect_stdout(io.StringIO()):
            rc = await po.amain(['relay'], self.env, self.rest)
        self.assertEqual(rc, 0)
        self.assertEqual(self.fake.sent('400'), ['Listo, ya está'])
        self.assertEqual(self.fake.sent('999'), [])
        self.assertEqual(sorted(os.listdir(os.path.join(self.outbox, 'sent'))), ['a.md'])
        self.assertEqual(sorted(os.listdir(os.path.join(self.outbox, 'refused'))), ['b.md', 'c.md'])
        self.assertEqual([f for f in os.listdir(self.outbox) if f.endswith('.md')], [])


class TestRealRegistry(unittest.TestCase):
    def test_every_po_has_a_seat_and_folder_and_every_project_a_manager(self):
        here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        agents = os.path.dirname(here)
        with open(os.path.join(here, 'projects.json')) as f:
            reg = json.load(f)
        with open(os.path.join(agents, 'org.json')) as f:
            seats = {s['id']: s for s in json.load(f)['seats']}
        router = reg.get('router')
        for name in {p['po'] for p in reg['projects'] if p.get('po')} | ({router} if router else set()):
            seat = seats.get(name.removeprefix('po-'), {})
            want = ('po', 'po-inbox', 'orchestrator') if name in (router, 'po-discord') else ('manager', 'po-inbox', 'discord')
            self.assertEqual((seat.get('role'), seat.get('wake'), seat.get('parent')), want, name)
            self.assertTrue(os.path.isfile(os.path.join(agents, name, 'BRIEF.md')), name)
        for p in reg['projects']:
            self.assertEqual(seats[p['id']]['role'], 'manager', p['id'])
            with open(os.path.join(agents, f'po-{p["id"]}', 'BRIEF.md')) as f:
                brief = f.read()
            self.assertIn(p['clone'], brief)
            for q in reg['projects']:
                if q is not p:
                    self.assertNotIn(q['clone'], brief, f'po-{p["id"]} names {q["id"]}')

    def test_chat_wake_cap_applies_to_every_manager(self):
        import sys
        agents = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        sys.path.insert(0, os.path.join(agents, 'lib'))
        import chat_route
        import org
        seats = org.seats(os.path.join(agents, 'org.json'))
        for s in (s for s in seats if s['role'] == 'manager'):
            msg = {'ch': 'org', 'from': 'orchestrator', 'to': [], 'text': f'@{s["id"]} hola', 'hop': 0}
            [w] = chat_route.wakes(msg, seats, {s['id']: chat_route.CAP})
            self.assertEqual((w['seat'], w['queue']), (s['id'], 'cap'))
            [w] = chat_route.wakes(msg, seats, {s['id']: chat_route.CAP - 1})
            self.assertIsNone(w['queue'])
