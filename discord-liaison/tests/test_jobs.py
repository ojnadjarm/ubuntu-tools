"""T1414: work requests become background jobs; a cap on concurrent jobs, a queue, and triage keeps running meanwhile."""
import os
import unittest

from liaison.jobs import GRACE, JobQueue
from liaison.runlock import run_lock

from .test_liaison import Base


def msg(mid):
    return {'id': mid, 'thread_id': '400', 'thread': 't', 'author': 'u2', 'content': 'haz algo', 'channel': 'foro'}


class Clock:
    t = 1000.0

    def __call__(self):
        return self.t


class TestJobQueue(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.clock = Clock()
        self.q = JobQueue(self.tmp.name, self.clock)
        self.launched = []

    def tearDown(self):
        self.tmp.cleanup()

    def launch(self, jid):
        self.launched.append(jid)
        return 0

    def test_cap_queues_extra_jobs_and_reaped_runners_free_slots(self):
        ids = [self.q.create(msg(str(i)), 'task')['id'] for i in range(4)]
        self.assertEqual(self.q.dispatch(3, self.launch)[0], ids[:3])
        self.assertEqual(self.q.dispatch(3, self.launch)[0], [])
        self.assertEqual([j['id'] for j in self.q.list('queued')], ids[3:])
        self.assertEqual(self.q.reap(), [])
        for retried in (False, True):
            self.clock.t += GRACE + 1
            with run_lock(os.path.join(self.tmp.name, ids[0], 'lock')):
                lost = self.q.reap()
            self.assertEqual([j['id'] for j in lost], ids[1:3] if retried else [])
            self.assertEqual(self.q.dispatch(3, self.launch)[0], ids[3:] if retried else ids[1:3])
        self.assertEqual(self.launched, ids[:3] + ids[1:3] + ids[3:])

    def test_failed_launch_is_retried_once_then_fails(self):
        jid = self.q.create(msg('7'), 'task')['id']
        self.assertEqual(self.q.dispatch(3, lambda _: 1), ([], []))
        self.assertEqual((self.q.get(jid)['status'], self.q.get(jid)['attempt']), ('queued', 2))
        started, failed = self.q.dispatch(3, lambda _: 1)
        self.assertEqual((started, [j['id'] for j in failed]), ([], [jid]))
        self.assertEqual(self.q.get(jid)['status'], 'failed')


class JobBase(Base):
    async def asyncSetUp(self):
        await super().asyncSetUp()
        self.launched = os.path.join(self.tmp.name, 'launched.log')
        self.env.update(LIAISON_JOBS_MAX='1', LIAISON_JOB_LAUNCH=f'echo {{id}} >> {self.launched}',
                        LIAISON_WORKER_CMD=f'cp {{prompt}} {self.tmp.name}/prompt.seen')

    def jobs(self):
        return JobQueue(os.path.join(self.tmp.name, 'state', 'jobs'))

    def launches(self):
        if not os.path.exists(self.launched):
            return []
        with open(self.launched) as f:
            return f.read().split()

    async def inbox(self, *texts):
        await self.run_cli('tick')
        ids = [self.fake.say('400', '2', t) for t in texts]
        await self.run_cli('check')
        await self.run_cli('inbox')
        return ids


class TestJobCli(JobBase):
    async def test_job_from_inbox_starts_then_queues_over_the_cap(self):
        a, b = await self.inbox('haz un PR con la voz', 'y una imagen del héroe')
        rc, out = await self.run_cli('job', a, 'PR on ten: narrator voice')
        self.assertEqual(rc, 0, out)
        self.assertIn('started', out)
        rc, out = await self.run_cli('job', b, 'concept art of the hero')
        self.assertIn('queued', out)
        self.assertEqual((await self.run_cli('job', a, 'again'))[0], 3)
        self.assertEqual((await self.run_cli('job', '123', 'not in inbox'))[0], 2)
        first = self.launches()
        self.assertEqual(len(first), 1)
        job = self.jobs().get(first[0])
        self.assertEqual((job['message']['project'], job['message']['route']), ('ten', 'liaison'))
        _, out = await self.run_cli('status')
        self.assertIn('jobs running 1/1 queued 1', out)

    async def test_job_run_runs_worker_with_rules_then_starts_the_next(self):
        a, b = await self.inbox('haz un PR', 'otra cosa')
        await self.run_cli('job', a, 'PR on ten')
        await self.run_cli('job', b, 'second')
        first = self.launches()[0]
        rc, out = await self.run_cli('job-run', first)
        self.assertEqual(rc, 0, out)
        with open(os.path.join(self.tmp.name, 'prompt.seen')) as f:
            prompt = f.read()
        for want in ('discord-liaison worker', '## Rules', 'task (from the triage run): PR on ten', 'haz un PR',
                     f'id="{a}"'):
            self.assertIn(want, prompt)
        self.assertNotIn('## Steps\n1. `discord-liaison inbox`', prompt)
        self.assertEqual(self.jobs().get(first)['status'], 'done')
        self.assertEqual(len(self.launches()), 2)
        self.assertEqual(self.fake.sent('400'), [])

    async def test_failed_worker_posts_spanish_note_and_escalates(self):
        (a,) = await self.inbox('haz un PR')
        await self.run_cli('job', a, 'PR on ten')
        jid = self.launches()[0]
        rc, _ = await self.run_cli('job-run', jid, env={'LIAISON_WORKER_CMD': 'exit 7'})
        self.assertEqual(rc, 7)
        self.assertEqual(self.jobs().get(jid)['status'], 'failed')
        sent = self.fake.sent('400')
        self.assertEqual(len(sent), 1)
        self.assertIn('no he podido terminarlo', sent[0])
        esc = os.listdir(os.path.join(self.tmp.name, 'state', 'escalations'))
        self.assertTrue(esc[0].endswith(f'-{a}.md'))
        self.assertTrue(os.path.exists(self.pulse_log))

    async def test_triage_runs_while_a_job_runs(self):
        (a,) = await self.inbox('haz un PR largo')
        await self.run_cli('job', a, 'long PR')
        await self.run_cli('done')
        jid = self.launches()[0]
        with run_lock(os.path.join(self.tmp.name, 'state', 'jobs', jid, 'lock')) as held:
            self.assertTrue(held)
            self.fake.say('400', '3', 'hola, ¿me lees?')
            rc, out = await self.run_cli('tick', env={'LIAISON_AGENT_CMD': f'touch {self.tmp.name}/ran'})
            self.assertEqual(rc, 0)
            self.assertNotIn('run in flight', out)
            self.assertTrue(os.path.exists(f'{self.tmp.name}/ran'))
            self.assertEqual(self.jobs().get(jid)['status'], 'running')

    async def test_tick_fails_a_job_whose_runner_died(self):
        (a,) = await self.inbox('haz un PR')
        await self.run_cli('job', a, 'PR on ten')
        jid = self.launches()[0]
        q = self.jobs()
        job = q.get(jid)
        job.update(started=job['started'] - GRACE - 1, attempt=2)
        q.save(job)
        await self.run_cli('tick')
        self.assertEqual((q.get(jid)['status'], q.get(jid)['why']), ('failed', 'lost'))
        self.assertIn('no he podido terminarlo', self.fake.sent('400')[0])


if __name__ == '__main__':
    unittest.main()
