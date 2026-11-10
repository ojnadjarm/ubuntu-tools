"""T1547: discord-hire makes a new project's manager end to end on a fake HOME (fake pc, systemctl, chat), once."""
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

from liaison import managers
from liaison.registry import Registry
from liaison.state import State

from . import test_liaison  # noqa: F401  (puts discordbot on sys.path)

AGENTS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BIN = os.path.join(AGENTS, 'bin')
sys.path.insert(0, os.path.join(AGENTS, 'lib'))
import org  # noqa: E402

PROJECTS = {'router': 'po-r', 'projects': [
    {'id': 'ten', 'name': 'Ten Game', 'repo': 'Org/Ten', 'clone': '~/clone-ten', 'match': {'tags': [], 'title': ['narrador']},
     'rules': {'language': 'es'}, 'skills': [], 'po': 'po-ten'}]}
SEATS = '{"seats": [\n  {"id": "owner", "name": "You", "role": "owner", "parent": null, "wake": null, "match": null},\n' \
        '  {"id": "orchestrator", "name": "O", "role": "ceo", "parent": "owner", "wake": "channel", "match": "~"},\n' \
        '  {"id": "r", "name": "Router", "role": "po", "parent": "orchestrator", "wake": "po-inbox", "match": "~/agents/po-r"}\n]}\n'
RULE = {'copyright': 'Archmage Engine SRD/OGL content only'}


class TestHire(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.home = os.path.join(t, 'agents')
        shutil.copytree(os.path.join(AGENTS, 'po-template'), os.path.join(self.home, 'po-template'))
        self.reg, self.org = os.path.join(t, 'projects.json'), os.path.join(self.home, 'org.json')
        with open(self.reg, 'w') as f:
            f.write(managers.dump(PROJECTS))
        with open(self.org, 'w') as f:
            f.write(SEATS)
        self.log, self.enabled = os.path.join(t, 'calls.log'), os.path.join(t, 'enabled')
        open(self.enabled, 'w').close()
        fake = os.path.join(t, 'fake')
        os.makedirs(fake)
        scripts = {
            'pc': f'echo "pc $*" >>{self.log}; [ -z "$PC_FAIL" ] || exit 5; echo "$3" >>{self.enabled}',
            'systemctl': f'grep -qx "$3" {self.enabled} && echo enabled || {{ echo disabled; exit 1; }}',
            'chat': f'echo "chat $CHAT_SEAT $*" >>{self.log}'}
        for name, body in scripts.items():
            with open(os.path.join(fake, name), 'w') as f:
                f.write(f'#!/bin/sh\n{body}\n')
            os.chmod(os.path.join(fake, name), 0o755)
        self.env = dict(os.environ, HARNESS_HOME=self.home, HARNESS_ENV_LOADED='1', HARNESS_CONFIG='/dev/null',
                        PATH=f'{BIN}:{os.environ["PATH"]}', AGENT_WORK=os.path.join(t, 'work'), PO_PAPERS=os.path.join(t, 'work', 'po'), LIAISON_REGISTRY=self.reg,
                        LIAISON_PO_HOME=self.home, LIAISON_HOME=os.path.join(t, 'liaison'), ORG_FILE=self.org,
                        PC=f'{fake}/pc', SYSTEMCTL=f'{fake}/systemctl', CHAT=f'{fake}/chat')
        self.env.pop('CHAT_SEAT', None)

    def tearDown(self):
        self.tmp.cleanup()

    def hire(self, **kw):
        out = io.StringIO()
        args = dict(pid='new-one', name='Narrador Interactivo IA', thread='555', rules=RULE, env=self.env) | kw
        with redirect_stdout(out):
            rc = managers.hire(args.pop('pid'), args.pop('name'), args.pop('thread'), **args)
        return rc, out.getvalue()

    def calls(self):
        return open(self.log).read().splitlines() if os.path.exists(self.log) else []

    def snapshot(self):
        paths = [self.reg, self.org, os.path.join(self.home, 'po-new-one', 'BRIEF.md'),
                 os.path.join(self.env['LIAISON_HOME'], 'state', 'threads.json')]
        return [open(p).read() for p in paths]

    def test_hire_makes_every_piece_once(self):
        rc, out = self.hire()
        self.assertEqual(rc, 0, out)
        self.assertIn('warning: ten matches "narrador"', out)
        r = Registry(self.reg)
        self.assertEqual(r.get('ten'), PROJECTS['projects'][0])
        p = r.get('new-one')
        self.assertEqual((p['repo'], p['clone'], p['po'], p['rules']['copyright']), (None, None, 'po-new-one', RULE['copyright']))
        brief = open(os.path.join(self.home, 'po-new-one', 'BRIEF.md')).read()
        self.assertIn('no repo yet', brief)
        self.assertIn('Archmage Engine SRD/OGL content only', brief)
        self.assertIn('PARENT=r', open(os.path.join(self.home, 'po-new-one', 'agent.env')).read())
        seat = [s for s in org.seats(self.org) if s['id'] == 'new-one']
        self.assertEqual((seat[0]['role'], seat[0]['parent'], seat[0]['match']), ('manager', 'r', '~/agents/po-new-one'))
        self.assertEqual((seat[0]['name'], seat[0]['area']), (org.proper_name('new-one', ['You', 'O', 'Router']), 'Narrador Interactivo IA'))
        self.assertNotIn('manager', seat[0]['name'].lower())
        self.assertEqual(org.abouts(org.seats(self.org), self.reg)['new-one'], 'Narrador Interactivo IA, a project from the Discord forum.')
        self.assertEqual(State(os.path.join(self.env['LIAISON_HOME'], 'state')).thread('555')['project'], 'new-one')
        self.assertEqual(r.dispatch({'content': 'hola', 'channel': 'foro'}, 'new-one'), 'po-new-one')
        calls = self.calls()
        self.assertEqual(calls[:2], ['pc units enable po@new-one.path --user --now --apply',
                                     'pc units enable discord-liaison-relay@new-one.path --user --now --apply'])
        self.assertEqual(len(calls), 3)
        self.assertTrue(calls[2].startswith('chat r post @owner Hired po-new-one'), calls[2])

    def test_about_is_asked_for(self):
        self.assertEqual(self.hire(about='An AI narrator for 13th Age.')[0], 0)
        self.assertEqual(Registry(self.reg).get('new-one')['about'], 'An AI narrator for 13th Age.')

    def test_rerun_is_a_no_op(self):
        self.assertEqual(self.hire()[0], 0)
        before, n = self.snapshot(), len(self.calls())
        rc, out = self.hire()
        self.assertEqual((rc, self.snapshot(), len(self.calls())), (0, before, n), out)
        self.assertIn('already hired', out)

    def test_repo_later_fills_entry_and_block(self):
        self.hire()
        rc, out = self.hire(repo='Org/Narrador', rules=None)
        self.assertEqual(rc, 0, out)
        p = Registry(self.reg).get('new-one')
        self.assertEqual((p['repo'], p['clone']), ('Org/Narrador', '~/projects/collab/Narrador'))
        brief = open(os.path.join(self.home, 'po-new-one', 'BRIEF.md')).read()
        self.assertIn('repo `Org/Narrador`', brief)
        self.assertNotIn('no repo yet', brief)
        self.assertEqual(brief.count('## Project'), 1)
        self.assertIn('repo', self.calls()[-1])

    def test_refusals_and_a_failed_unit(self):
        for kw in ({'pid': 'Bad Id'}, {'thread': 'abc'}, {'repo': 'no-slash'}):
            self.assertEqual(self.hire(**kw)[0], 2)
        self.assertFalse(os.path.exists(os.path.join(self.home, 'po-new-one')))
        self.env['PC_FAIL'] = '1'
        rc, out = self.hire()
        self.assertEqual(rc, 1)
        self.assertIn('failed: pc units enable po@new-one.path', out)
        self.assertFalse(any(c.startswith('chat') for c in self.calls()))
        del self.env['PC_FAIL']
        rc, out = self.hire()
        self.assertEqual(rc, 0, out)
        self.assertIn('hired po-new-one: units', out)
