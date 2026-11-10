"""T1515 P31: one manager per project; tick hands each message by code to its own manager or the router, nothing else."""
import json
import os
import shutil

from liaison import managers
from liaison.registry import Registry

from .test_liaison import PNG, Base

AGENTS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BIN = os.path.join(AGENTS, 'bin')
PROJECTS = {'router': 'po-r', 'projects': [
    {'id': 'ten', 'name': 'Ten Game', 'repo': 'Org/Ten', 'clone': '~/clone-ten', 'match': {'tags': [], 'title': ['narrador']},
     'rules': {'language': 'es: rule-of-ten'}, 'skills': ['skill-ten'], 'po': 'po-ten'},
    {'id': 'other', 'name': 'Other Game', 'repo': 'Org/Other', 'clone': '~/clone-other',
     'match': {'tags': [], 'title': ['otro']}, 'rules': {'pr_flow': 'rule-of-other'}, 'skills': ['skill-other'],
     'po': 'po-other'},
    {'id': 'plain', 'name': 'Plain', 'repo': 'Org/Plain', 'clone': '~/clone-plain', 'match': {'tags': [], 'title': ['llano']},
     'rules': {}, 'skills': [], 'po': None}]}


class TestDispatch(Base):
    def test_dispatch_is_code(self):
        reg = os.path.join(self.tmp.name, 'p.json')
        with open(reg, 'w') as f:
            json.dump(PROJECTS, f)
        r = Registry(reg)
        msg = lambda text, ch='foro': {'content': text, 'channel': ch}  # noqa: E731
        self.assertEqual(r.dispatch(msg('hola'), 'ten'), 'po-ten')
        self.assertEqual(r.dispatch(msg('hola'), ''), 'po-r')
        self.assertEqual(r.dispatch(msg('como en el otro juego'), 'ten'), 'po-r')
        self.assertEqual(r.dispatch(msg('hola'), 'plain'), None)
        self.assertEqual(r.dispatch(msg('hola', 'general'), ''), None)
        r.router = None
        self.assertEqual((r.dispatch(msg('hola'), ''), r.dispatch(msg('otro'), 'ten')), (None, 'po-ten'))


class TestManagers(Base):
    async def asyncSetUp(self):
        await super().asyncSetUp()
        self.home = os.path.join(self.tmp.name, 'agents')
        os.makedirs(self.home)
        shutil.copytree(os.path.join(AGENTS, 'po-template'), os.path.join(self.home, 'po-template'))
        reg = os.path.join(self.tmp.name, 'projects.json')
        with open(reg, 'w') as f:
            json.dump(PROJECTS, f)
        self.fake.channels['450']['name'] = 'Un otro juego'
        self.fake.channels['460'] = dict(self.fake.channels['450'], id='460', name='Hola a todos')
        self.ran = os.path.join(self.tmp.name, 'ran')
        sh = dict(os.environ, HARNESS_HOME=self.home, HARNESS_ENV_LOADED='1', HARNESS_CONFIG='/dev/null',
                  PATH=f'{BIN}:{os.environ["PATH"]}', AGENT_WORK=os.path.join(self.tmp.name, 'work'))
        self.env.update(LIAISON_REGISTRY=reg, LIAISON_PO_HOME=self.home, LIAISON_AGENT_CMD=f'touch {self.ran}',
                        DISCORD_GENERAL_ID='999', LIAISON_PO_ASK=f'env HARNESS_HOME={self.home} HARNESS_ENV_LOADED=1 '
                                                                f'HARNESS_CONFIG=/dev/null {BIN}/po-ask')
        for pid in ('ten', 'other'):
            self.assertEqual(managers.make(pid, dict(sh, LIAISON_REGISTRY=reg, LIAISON_PO_HOME=self.home)), 0)
        os.makedirs(os.path.join(self.home, 'po-r', 'inbox'))
        open(os.path.join(self.home, 'po-r', 'BRIEF.md'), 'w').close()

    def given(self, name):
        """Everything a manager's run is given: its BRIEF, state, ledger and every request in its inbox."""
        d, out = os.path.join(self.home, name), []
        for root, _, files in os.walk(d):
            out += [open(os.path.join(root, f)).read() for f in files if f.endswith(('.md', '.env'))]
        ledger = os.path.join(self.tmp.name, 'work', 'decisions', f'{name.removeprefix("po-")}.md')
        if os.path.exists(ledger):
            out.append(open(ledger).read())
        return '\n'.join(out)

    async def test_a_request_for_project_a_never_reaches_manager_b(self):
        await self.run_cli('tick')
        self.fake.say('400', '2', 'pedido-A: voces nuevas')
        self.fake.say('450', '3', 'pedido-B: un mapa')
        self.fake.say('460', '4', 'pedido-sin-proyecto')
        self.fake.say('999', '5', 'pedido-general @agents', users=['900'])
        rc, out = await self.run_cli('tick')
        self.assertEqual(rc, 0, out)
        ten, other, router = self.given('po-ten'), self.given('po-other'), self.given('po-r')
        self.assertIn('pedido-A', ten)
        self.assertIn('pedido-B', other)
        self.assertIn('pedido-sin-proyecto', router)
        for text, name in ((ten, 'ten'), (other, 'other')):
            mine, theirs = ('ten', 'other') if name == 'ten' else ('other', 'ten')
            self.assertIn(f'rule-of-{mine}', text)
            self.assertIn(f'~/clone-{mine}', text)
            for leak in (f'rule-of-{theirs}', f'~/clone-{theirs}', f'skill-{theirs}', f'{theirs.title()} Game',
                         'pedido-B' if name == 'ten' else 'pedido-A', 'pedido-sin-proyecto', 'pedido-general'):
                self.assertNotIn(leak, text, f'{leak} leaked to po-{name}')
        for leak in ('rule-of-', '~/clone-', 'pedido-A', 'pedido-B', 'pedido-general'):
            self.assertNotIn(leak, router)
        self.assertEqual([m['content'] for m in self.state().inbox], ['pedido-general @agents'])
        self.assertTrue(os.path.exists(self.ran), 'the #general mention still wakes the triage')

    async def test_only_routed_messages_wake_no_triage_and_hand_off_once(self):
        await self.run_cli('tick')
        self.fake.say('400', '2', 'pedido-A')
        await self.run_cli('tick')
        await self.run_cli('tick')
        self.assertFalse(os.path.exists(self.ran))
        self.assertEqual(len(os.listdir(os.path.join(self.home, 'po-ten', 'inbox'))), 1)
        self.assertEqual(self.state().inbox, [])

    def bot_posts(self, tid):
        return [m for m in self.fake.messages.get(tid, []) if m['author']['id'] == '900']

    async def test_hand_off_posts_nothing_in_the_thread(self):
        await self.run_cli('tick')
        self.fake.say('400', '2', 'pedido-A: voces nuevas')
        self.fake.say('400', '2', 'pedido-A: y una musica')
        self.fake.say('460', '4', 'pedido-sin-proyecto')
        await self.run_cli('tick')
        self.assertEqual((self.bot_posts('400'), self.bot_posts('460')), ([], []))
        self.assertEqual(len(os.listdir(os.path.join(self.home, 'po-ten', 'inbox'))), 2, 'filed, no run yet')
        self.assertFalse(os.path.exists(self.ran))
        await self.run_cli('tick')
        self.assertEqual((self.bot_posts('400'), self.bot_posts('460')), ([], []))

    async def test_no_post_for_a_bot_or_a_failed_hand_off(self):
        await self.run_cli('tick')
        self.fake.say('400', '7', 'otro bot', bot=True)
        shutil.rmtree(os.path.join(self.home, 'po-other'))
        self.fake.say('450', '3', 'pedido-B')
        await self.run_cli('tick')
        self.assertEqual((self.bot_posts('400'), self.bot_posts('450')), ([], []))

    async def test_failed_po_ask_keeps_the_message_for_the_triage(self):
        await self.run_cli('tick')
        shutil.rmtree(os.path.join(self.home, 'po-ten'))
        self.fake.say('400', '2', 'pedido-A')
        await self.run_cli('tick')
        self.assertEqual([m['content'] for m in self.state().inbox], ['pedido-A'])
        self.assertTrue(os.path.exists(self.ran))

    async def test_an_image_reaches_its_manager_only(self):
        cdn = str(self.server.make_url('/cdn'))
        self.env['LIAISON_CDN_PREFIXES'] = cdn + '/'
        self.fake.files = {'a.png': PNG, 'b.png': PNG}
        att = lambda n: {'filename': n, 'size': len(PNG), 'url': f'{cdn}/{n}'}  # noqa: E731
        await self.run_cli('tick')
        self.fake.say('400', '2', 'pedido-A con captura', attachments=[att('a.png')])
        self.fake.say('460', '4', 'pedido-sin-proyecto con foto', attachments=[att('b.png')])
        rc, out = await self.run_cli('tick')
        self.assertEqual(rc, 0, out)
        for name, n in (('po-ten', 1), ('po-r', 1), ('po-other', 0)):
            d = os.path.join(self.home, name)
            imgs = [os.path.join(r, f) for r, _, fs in os.walk(d) for f in fs if f.endswith('.png')]
            self.assertEqual(len(imgs), n, name)
            for img in imgs:
                self.assertEqual(open(img, 'rb').read(), PNG)
                self.assertTrue(img.startswith(d + '/'))
                req = [open(os.path.join(d, 'inbox', f)).read() for f in os.listdir(os.path.join(d, 'inbox'))]
                self.assertEqual(sum(f'images: {img}' in r for r in req), 1, name)
        work = os.path.join(self.tmp.name, 'state', 'work')
        self.assertEqual(os.listdir(work) if os.path.isdir(work) else [], [], 'the liaison keeps no copy')
        self.assertFalse(os.path.exists(self.ran))

    async def test_manager_folder_contract(self):
        d = os.path.join(self.home, 'po-ten')
        with open(os.path.join(d, 'agent.env')) as f:
            self.assertIn('PARENT=r', f.read())
        with open(os.path.join(d, 'BRIEF.md')) as f:
            brief = f.read()
        self.assertNotIn('{{', brief)
        self.assertIn('po-ten, the manager of Ten Game', brief)
        self.assertIn('ESCALATE:` goes to po-r', brief)
        self.assertTrue(os.path.exists(os.path.join(self.tmp.name, 'work', 'decisions', 'ten.md')))
        self.assertEqual(managers.make('nope', dict(self.env)), 2)
