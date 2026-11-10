"""T1412 P5: messages of a project with a `po` go to that PO once (po-ask); the PO's outbox replies are posted to their thread."""
import io
import json
import os
import shlex
import subprocess
import sys
import time
import unittest
from contextlib import redirect_stdout

from liaison import po
from liaison.cli import App

from .test_liaison import Base

AGENTS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


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
        self.assertEqual(await po.handoff(App(self.env, self.rest), self.env), 1)
        self.assertEqual(await po.handoff(App(self.env, self.rest), self.env), 0)
        with open(self.asklog) as f:
            lines = f.read().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertTrue(lines[0].startswith('other|--from|liaison|--channel|discord|--thread|400|--copy|'))
        self.assertIn(f'message {mid}): quiero un sonido nuevo|', lines[0])

    async def test_liaison_project_not_handed_off(self):
        await self.message('ten')
        self.assertEqual(await po.handoff(App(self.env, self.rest), self.env), 0)
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

    async def test_relay_waits_for_a_running_relay_and_posts_once(self):
        with open(os.path.join(self.outbox, 'a.md'), 'w') as f:
            f.write('thread: 400\nPlan: primero X, luego Y')
        lock = os.path.join(self.tmp.name, 'state', 'relay.lock')
        os.makedirs(os.path.dirname(lock), exist_ok=True)
        hold = subprocess.Popen([sys.executable, '-c', 'import fcntl, sys, time; f = open(sys.argv[1], "a"); '
                                 'fcntl.flock(f, fcntl.LOCK_EX); print(1, flush=True); time.sleep(1.5)', lock],
                                stdout=subprocess.PIPE)
        hold.stdout.readline()
        t = time.monotonic()
        with redirect_stdout(io.StringIO()):
            self.assertEqual(await po.amain(['relay'], self.env, self.rest), 0)
        took = time.monotonic() - t
        hold.wait()
        self.assertGreater(took, 1.0)
        self.assertEqual(self.fake.sent('400'), ['Plan: primero X, luego Y'])

    def test_outbox_write_fires_the_relay_unit(self):
        units = os.path.join(AGENTS, 'units')
        with open(os.path.join(units, 'discord-liaison-relay@.path')) as f:
            path = f.read()
        with open(os.path.join(units, 'discord-liaison-relay.service')) as f:
            svc = f.read()
        self.assertIn('PathModified=%h/agents/po-%i/outbox/discord\n', path)
        self.assertIn('Unit=discord-liaison-relay.service\n', path)
        self.assertIn('ExecStart=%h/agents/bin/discord-liaison relay\n', svc)
        self.assertIn("'relay '*) exec \"$py\" -m liaison.po relay", open(os.path.join(AGENTS, 'bin', 'discord-liaison')).read())
        self.assertEqual(os.path.join(po.po_home({'HARNESS_HOME': '/h'}), 'po-x', 'outbox', 'discord'),
                         '/h/po-x/outbox/discord')

    def media(self, path, data=b'\x89PNG\r\n\x1a\n' + b'0' * 64):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(data)
        return path

    async def test_relay_posts_images_from_own_folder_or_clone_and_refuses_others(self):
        self.env['HOME'] = self.tmp.name
        mine = self.media(os.path.join(self.tmp.name, 'agents', 'po-other', 'state', 'shot.png'))
        clone = self.media(os.path.join(self.tmp.name, 'y', 'out', 'render.gif'), b'GIF89a' + b'0' * 64)
        foreign = self.media(os.path.join(self.tmp.name, 'agents', 'po-ten', 'secret.png'))
        loose = self.media(os.path.join(self.tmp.name, 'token.png'))
        link = os.path.join(self.tmp.name, 'agents', 'po-other', 'state', 'link.png')
        os.symlink(loose, link)
        text = self.media(os.path.join(self.tmp.name, 'agents', 'po-other', 'state', 'notes.png'), b'TOKEN=abc')
        big = self.media(os.path.join(self.tmp.name, 'y', 'big.png'),
                         b'\x89PNG\r\n\x1a\n' + b'0' * (25 * 1024 * 1024))
        bodies = {'a.md': f'thread: 400\nimage: {mine}\nimage: ~/y/out/render.gif\nMira las capturas',
                  'b.md': f'thread: 400\nimage: {foreign}\nno', 'c.md': f'thread: 400\nimage: {loose}\nno',
                  'd.md': f'thread: 400\nimage: {link}\nno', 'e.md': f'thread: 400\nimage: {text}\nno',
                  'f.md': f'thread: 400\nimage: {mine}/../../../token.png\nno', 'g.md': f'thread: 400\nimage: {big}\nno',
                  'h.md': 'thread: 400\n' + f'image: {mine}\n' * 11 + 'no'}
        for name, body in bodies.items():
            with open(os.path.join(self.outbox, name), 'w') as f:
                f.write(body)
        with redirect_stdout(io.StringIO()):
            self.assertEqual(await po.amain(['relay'], self.env, self.rest), 0)
        sent = [m for m in self.fake.messages['400'] if m['author']['id'] == '900']
        self.assertEqual([(m['content'], m['attachments']) for m in sent], [
            ('Mira las capturas', [{'filename': 'shot.png', 'size': os.path.getsize(mine)}]),
            ('', [{'filename': 'render.gif', 'size': os.path.getsize(clone)}])])
        self.assertEqual(os.listdir(os.path.join(self.outbox, 'sent')), ['a.md'])
        self.assertEqual(sorted(os.listdir(os.path.join(self.outbox, 'refused'))), sorted(bodies.keys() - {'a.md'}))


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
            self.assertIn(p['clone'] or 'no repo yet', brief)
            for q in reg['projects']:
                if q is not p and q['clone']:
                    self.assertNotIn(q['clone'], brief, f'po-{p["id"]} names {q["id"]}')

    def test_chat_mention_wakes_every_manager_without_a_daily_limit(self):
        import sys
        agents = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        sys.path.insert(0, os.path.join(agents, 'lib'))
        import chat_route
        import org
        seats = org.seats(os.path.join(agents, 'org.json'))
        for s in (s for s in seats if s['role'] == 'manager'):
            msg = {'ch': 'org', 'from': 'orchestrator', 'to': [], 'text': f'@{s["id"]} hola', 'hop': 0}
            [w] = chat_route.wakes(msg, seats)
            self.assertEqual((w['seat'], w['queue']), (s['id'], None))
