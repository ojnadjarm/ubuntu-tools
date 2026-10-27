"""T1416: a request goes to a worker; only a named blocker or two failed attempts reach the orchestrator."""
import os
import unittest

from liaison.jobs import GRACE
from liaison.routing import after_failure, route

from .test_jobs import JobBase


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


if __name__ == '__main__':
    unittest.main()
