"""T1546-M2: in liaison mode the owner's ✅ (recorded by the bot) reaches the thread's manager once, as his approval."""
import json
import os

from .test_liaison import Base
from .test_managers import BIN, PROJECTS
from liaison import po  # noqa: E402
from liaison.cli import App  # noqa: E402


class TestApprovals(Base):
    async def asyncSetUp(self):
        await super().asyncSetUp()
        self.home = os.path.join(self.tmp.name, 'agents')
        for name in ('po-ten', 'po-r'):
            os.makedirs(os.path.join(self.home, name, 'inbox'))
            open(os.path.join(self.home, name, 'BRIEF.md'), 'w').close()
        reg = os.path.join(self.tmp.name, 'projects.json')
        with open(reg, 'w') as f:
            json.dump(PROJECTS, f)
        self.bot_state = os.path.join(self.tmp.name, 'bot-state')
        self.env.update(LIAISON_REGISTRY=reg, LIAISON_PO_HOME=self.home, DISCORD_OWNER_ID='1',
                        LIAISON_NUDGE=os.path.join(self.bot_state, 'liaison.nudge'),
                        LIAISON_PO_ASK=f'env HARNESS_HOME={self.home} HARNESS_ENV_LOADED=1 HARNESS_CONFIG=/dev/null '
                                       f'{BIN}/po-ask')
        self.fake.channels['400']['name'] = 'Voces para el narrador'
        await self.run_cli('tick')
        self.mid = self.fake.say('400', '2', 'Propuesta: ' + 'x' * 300)
        await self.run_cli('check')

    def check_mark(self, uid, mid=None):
        """What the bot writes on a ✅ (gateway), plus the reaction Discord itself shows."""
        mid = mid or self.mid
        self.fake.reactions.setdefault(('400', mid), []).append(uid)
        os.makedirs(os.path.join(self.bot_state, 'approvals'), exist_ok=True)
        with open(os.path.join(self.bot_state, 'approvals', f'{mid}.json'), 'w') as f:
            json.dump({'channel_id': '400', 'message_id': mid, 'user_id': uid, 'at': 1}, f)

    def inbox(self, name='po-ten'):
        d = os.path.join(self.home, name, 'inbox')
        return [open(os.path.join(d, n)).read() for n in sorted(os.listdir(d)) if n.endswith('.md')]

    async def approvals(self):
        return await po.approvals(App(self.env, self.rest), self.env)

    async def test_owner_check_mark_puts_one_approval_in_the_managers_inbox(self):
        self.check_mark('1')
        self.assertEqual(await self.approvals(), 1)
        items = self.inbox()
        self.assertEqual(len(items), 1)
        self.assertIn('owner: true', items[0])
        self.assertIn(f'the owner approved this message (✅): message {self.mid}: "Propuesta: {"x" * 189}"', items[0])
        self.assertNotIn('x' * 190, items[0])
        self.assertEqual(self.inbox('po-r'), [])
        self.assertEqual(os.listdir(os.path.join(self.bot_state, 'approvals')), [])

    async def test_second_check_mark_on_the_same_message_puts_none(self):
        self.check_mark('1')
        await self.approvals()
        self.check_mark('1')
        self.assertEqual(await self.approvals(), 0)
        self.assertEqual(len(self.inbox()), 1)

    async def test_non_owner_check_mark_puts_none(self):
        self.check_mark('2')
        self.assertEqual(await self.approvals(), 0)
        self.assertEqual(self.inbox(), [])

    async def test_forged_record_without_the_owners_reaction_on_discord_puts_none(self):
        self.check_mark('1')
        self.fake.reactions[('400', self.mid)] = ['2']
        self.assertEqual(await self.approvals(), 0)
        self.assertEqual(self.inbox(), [])

    async def test_thread_of_a_project_without_a_manager_puts_none(self):
        await self.run_cli('map', '400', 'plain')
        self.check_mark('1')
        self.assertEqual(await self.approvals(), 0)
        self.assertEqual(self.inbox() + self.inbox('po-r'), [])

    async def test_tick_passes_the_owners_check_mark(self):
        self.check_mark('1')
        await self.run_cli('tick')
        self.assertEqual(sum('the owner approved this message' in i for i in self.inbox()), 1)
