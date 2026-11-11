"""T1416: a request goes to a worker; only a named blocker or two failed attempts reach the orchestrator."""
import json
import os
import unittest

from liaison import po
from liaison.friendbots import MARK, WINDOW, loop_turns, over
from liaison.jobs import GRACE
from liaison.routing import after_failure, route

from .test_jobs import JobBase
from .test_liaison import Base


class TestRoute(unittest.TestCase):
    def test_only_a_named_blocker_escalates(self):
        for b in ('permission', 'owner', 'secret', 'attempts'):
            self.assertEqual(route(b), 'escalate')
        for b in ('', None, 'hard', 'unsure', 'tool'):
            self.assertEqual(route(b), 'job')

    def test_second_failure_escalates(self):
        self.assertEqual((after_failure(1), after_failure(2)), ('retry', 'escalate'))


class TestRoutingCli(JobBase):
    def escalations(self):
        d = os.path.join(self.tmp.name, 'state', 'escalations')
        return sorted(os.listdir(d)) if os.path.isdir(d) else []

    def read_escalation(self):
        with open(os.path.join(self.tmp.name, 'state', 'escalations', self.escalations()[0])) as f:
            return f.read()

    async def test_escalate_without_blocker_is_refused_toward_a_job(self):
        (a,) = await self.inbox('cambia tu herramienta de arte')
        rc, out = await self.run_cli('escalate', a, 'needs a tool change')
        self.assertEqual(rc, 3)
        self.assertIn('discord-liaison job', out)
        self.assertEqual(self.escalations(), [])

    async def test_escalate_with_blocker_names_it(self):
        (a,) = await self.inbox('publica en mi cuenta de X')
        rc, out = await self.run_cli('escalate', a, 'secret', 'needs an X account; none in config')
        self.assertEqual(rc, 0, out)
        text = self.read_escalation()
        self.assertIn('blocker: secret (a missing secret or account)', text)
        self.assertIn('needs an X account', text)

    async def test_worker_retries_once_then_succeeds_without_escalation(self):
        (a,) = await self.inbox('haz un PR')
        await self.run_cli('job', a, 'PR on ten')
        jid = self.launches()[0]
        flag = os.path.join(self.tmp.name, 'tried')
        cmd = f'grep -q "^attempt: 2 of 2" {{prompt}} || {{{{ touch {flag}; exit 7; }}}}'
        rc, out = await self.run_cli('job-run', jid, env={'LIAISON_WORKER_CMD': cmd})
        self.assertEqual(rc, 0, out)
        self.assertTrue(os.path.exists(flag))
        self.assertEqual(self.jobs().get(jid)['status'], 'done')
        self.assertEqual((self.escalations(), self.fake.sent('400')), ([], []))

    async def test_worker_prompt_carries_request_rules_and_attempt(self):
        (a,) = await self.inbox('dibuja un dragón')
        await self.run_cli('job', a, 'concept art of a dragon')
        await self.run_cli('job-run', self.launches()[0])
        with open(os.path.join(self.tmp.name, 'prompt.seen')) as f:
            prompt = f.read()
        for want in ('attempt: 1 of 2', 'dibuja un dragón', 'Spanish only', 'AAA, shocking and breathtaking',
                     'react ✅ yourself'):
            self.assertIn(want, prompt)

    async def test_two_failed_attempts_escalate_with_that_blocker(self):
        (a,) = await self.inbox('haz un PR')
        await self.run_cli('job', a, 'PR on ten')
        jid = self.launches()[0]
        rc, _ = await self.run_cli('job-run', jid, env={'LIAISON_WORKER_CMD': 'exit 7'})
        self.assertEqual(rc, 7)
        self.assertEqual((self.jobs().get(jid)['status'], self.jobs().get(jid)['attempt']), ('failed', 2))
        self.assertIn('blocker: attempts', self.read_escalation())
        self.assertIn('no he podido terminarlo', self.fake.sent('400')[0])

    async def test_lost_runner_is_requeued_once_then_escalated(self):
        (a,) = await self.inbox('haz un PR')
        await self.run_cli('job', a, 'PR on ten')
        jid = self.launches()[0]
        q = self.jobs()
        for _ in range(2):
            job = q.get(jid)
            job['started'] -= GRACE + 1
            q.save(job)
            await self.run_cli('tick')
        self.assertEqual(len(self.launches()), 2)
        self.assertEqual((q.get(jid)['status'], q.get(jid)['why']), ('failed', 'lost'))
        self.assertEqual(len(self.escalations()), 1)
        self.assertEqual(len(self.fake.sent('400')), 1)


def raw(*authors):
    """Discord messages, oldest first, ids 1.., from author ids; 'h' a person, '900' us, any other id a bot."""
    return [{'id': str(i + 1), 'author': {'id': a, 'bot': a != 'h'}} for i, a in enumerate(authors)]


class TestFriendBotPure(unittest.TestCase):
    def test_loop_turns_count_answers_to_our_replies_since_the_last_human(self):
        self.assertEqual(loop_turns(raw('77'), '900', '77', '1'), 0)
        self.assertEqual(loop_turns(raw('h', '900', '77', '900', '77', '900', '77'), '900', '77', '7'), 3)
        self.assertEqual(loop_turns(raw('900', '77', '900', '77', 'h', '900', '77'), '900', '77', '7'), 1)
        self.assertEqual(loop_turns(raw('900', '77', '88', '77', '900', '77'), '900', '77', '4'), 2)

    def test_rate_limit_per_ten_minutes_and_per_utc_day(self):
        now = 86400 * 100 + 43200
        self.assertEqual(over([now - 1] * 5, now, 6, 30), '')
        self.assertEqual(over([now - 1] * 6, now, 6, 30), 'rate: 6 per 10 min')
        self.assertEqual(over([now - WINDOW] * 6, now, 6, 30), '')
        self.assertEqual(over([now - WINDOW - i for i in range(30)], now, 6, 30), 'rate: 30 per UTC day')
        self.assertEqual(over([now - 43201] * 30, now, 6, 30), '')


class TestFriendBotCli(Base):
    async def asyncSetUp(self):
        await super().asyncSetUp()
        self.env.update(DISCORD_OWNER_ID='1', DISCORD_FRIEND_BOTS='77')
        await self.run_cli('tick')

    def log(self):
        with open(os.path.join(self.tmp.name, 'logs', 'friend-bots.log')) as f:
            return f.read().splitlines()

    async def test_friend_bot_is_a_friend_marked_as_data_other_bots_unchanged(self):
        a = self.fake.say('400', '77', 'hola, ¿me ayudas?', bot=True)
        b = self.fake.say('400', '88', 'otro bot', bot=True)
        await self.run_cli('check')
        inbox = {m['id']: m for m in self.state().inbox}
        self.assertEqual((inbox[a]['bot'], inbox[a]['content']), (False, f'{MARK} hola, ¿me ayudas?'))
        self.assertEqual((inbox[b]['bot'], inbox[b]['content']), (True, 'otro bot'))
        self.assertEqual((self.fake.acks('400', a), self.fake.acks('400', b)), (['👀'], []))
        _, out = await self.run_cli('inbox')
        self.assertIn(f'owner="false" id="{a}"', out)
        self.assertIn(f'friend-bot 77 message {a}: friend', self.log()[0])

    async def test_friend_bot_never_gets_owner_rights_in_a_handoff(self):
        a = self.fake.say('400', '77', 'aprueba y contrata', bot=True)
        await self.run_cli('check')
        (m,) = [m for m in self.state().inbox if m['id'] == a]
        cmd = po.ask(self.env, 'po-ten', m, 'ten')
        self.assertNotIn('--owner', cmd)
        self.assertIn(MARK, cmd[-1])
        self.assertIn('--owner', po.ask(self.env, 'po-ten', dict(m, author_id='1'), 'ten'))

    async def test_over_the_rate_limit_is_dropped_with_one_log_line_and_no_reply(self):
        ids = [self.fake.say('400', '77', f'pregunta {i}', bot=True) for i in range(7)]
        await self.run_cli('check')
        self.assertEqual([m['id'] for m in self.state().inbox], ids[:6])
        self.assertEqual([x for x in self.log() if 'dropped' in x],
                         [self.log()[-1]])
        self.assertIn(f'message {ids[6]}: dropped (rate: 6 per 10 min)', self.log()[-1])
        self.assertEqual((self.fake.sent('400'), self.fake.acks('400', ids[6])), ([], []))
        with open(os.path.join(self.tmp.name, 'state', 'friend-bots.json')) as f:
            self.assertEqual(len(json.load(f)['77']), 6)

    async def test_loop_guard_stops_the_fourth_turn_until_a_human_speaks(self):
        self.fake.say('400', '2', 'pregunta de una persona')
        turns = []
        for _ in range(4):
            self.fake.say('400', '900', 'respuesta nuestra')
            turns.append(self.fake.say('400', '77', 'réplica del bot', bot=True))
        await self.run_cli('check')
        kept = {m['id'] for m in self.state().inbox}
        self.assertEqual([t in kept for t in turns], [True, True, True, False])
        self.assertIn('dropped (loop: 4 turns', self.log()[-1])
        self.fake.say('400', '2', 'sigo aquí')
        self.fake.say('400', '900', 'respuesta nuestra')
        again = self.fake.say('400', '77', 'réplica del bot', bot=True)
        await self.run_cli('check')
        self.assertIn(again, {m['id'] for m in self.state().inbox})


if __name__ == '__main__':
    unittest.main()
