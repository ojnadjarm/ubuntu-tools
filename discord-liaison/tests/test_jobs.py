"""T1414: work requests become background jobs; a cap on concurrent jobs, a queue, and triage keeps running meanwhile."""
import os
import sys
import unittest
from unittest import mock

from liaison.cli import App
from liaison.jobs import GRACE, JobQueue
from liaison.routing import MAX_ATTEMPTS
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

    async def other(self, text):
        """One message in a second forum thread (another conversation)."""
        mid = self.fake.say('450', '3', text)
        await self.run_cli('check')
        await self.run_cli('inbox')
        return mid


class TestJobCli(JobBase):
    async def test_unit_runtime_covers_every_attempt(self):
        env = {k: v for k, v in self.env.items() if k != 'LIAISON_JOB_LAUNCH'}
        with mock.patch('liaison.cli.subprocess.call', return_value=0) as call:
            App(dict(env, LIAISON_JOB_TIMEOUT='100'), None).launch('j1')
        self.assertIn(f'--property=RuntimeMaxSec={MAX_ATTEMPTS * 100 + 300}', call.call_args[0][0])

    async def test_job_from_inbox_starts_then_queues_over_the_cap(self):
        (a,) = await self.inbox('haz un PR con la voz')
        b = await self.other('y una imagen del héroe')
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
        (a,) = await self.inbox('haz un PR')
        b = await self.other('otra cosa')
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


class TestImageGrant(JobBase):
    """T1632: a job holds no image key; `art --asked` gets it only with a quote from the job's own messages."""

    async def test_job_worker_env_holds_no_key(self):
        (a,) = await self.inbox('dibuja una representación de ti')
        await self.run_cli('job', a, 'draw yourself')
        seen = os.path.join(self.tmp.name, 'key.seen')
        await self.run_cli('job-run', self.launches()[0], env={'LIAISON_WORKER_CMD': f'echo "$OPENROUTER_KEY_FILE" > {seen}'})
        with open(seen) as f:
            self.assertEqual(f.read().strip(), '/dev/null')

    async def test_art_passes_key_and_quote_only_when_the_quote_is_in_the_job(self):
        (a,) = await self.inbox('Hazme   una imagen con IA del héroe, porfa')
        await self.run_cli('job', a, 'AI image of the hero')
        jid = self.launches()[0]
        seen, fake = os.path.join(self.tmp.name, 'art.seen'), os.path.join(self.tmp.name, 'art.py')
        with open(fake, 'w') as f:
            f.write('import os, sys\na = sys.argv\nopen(a[a.index("--out") + 1], "wb").write(b"\\x89PNG\\r\\n\\x1a\\n")\n'
                    f'open({seen!r}, "a").write(repr((a[a.index("--asked") + 1] if "--asked" in a else None, '
                    'os.environ.get("OPENROUTER_KEY_FILE"))) + "\\n")\n')
        env = {'LIAISON_JOB': jid, 'LIAISON_ART_CMD': f'{sys.executable} {fake}', 'LIAISON_IMAGES_PER_DAY': '5',
               'LIAISON_ART_KEY_FILE': '/fx/key'}
        with mock.patch.dict(os.environ, {'OPENROUTER_KEY_FILE': '/dev/null'}):
            await self.run_cli('art', '--asked', 'hazme una imagen con IA del héroe', 'hero', env=env)
            await self.run_cli('art', '--asked', 'una imagen con IA de un dragón', 'dragon', env=env)
            await self.run_cli('art', 'hero', env=env)
        with open(seen) as f:
            rows = f.read().splitlines()
        self.assertEqual(rows, [repr(('hazme una imagen con IA del héroe', '/fx/key')), repr((None, '/dev/null')),
                                repr((None, '/dev/null'))])


class TestImageKeyMask(JobBase):
    """T1633: a job whose messages ask for no AI image cannot read the image key file at all."""

    async def asyncSetUp(self):
        await super().asyncSetUp()
        self.key, self.other = os.path.join(self.tmp.name, 'fx.key'), os.path.join(self.tmp.name, 'fx.other')
        for path, text in ((self.key, 'FXKEY-T1633'), (self.other, 'other')):
            with open(path, 'w') as f:
                f.write(text)
        self.env['LIAISON_ART_KEY_FILE'] = self.key

    def test_selftest_the_key_is_the_fixture(self):
        real = os.path.realpath(os.path.expanduser('~/agents/secrets/openrouter.key'))
        self.assertNotEqual(os.path.realpath(self.key), real)
        self.assertTrue(self.key.startswith(self.tmp.name + os.sep))

    async def reads(self, text):
        """Run one job for `text` whose worker reads the key three ways and one other file."""
        (a,) = await self.inbox(text)
        await self.run_cli('job', a, 'task')
        o = os.path.join(self.tmp.name, 'out')
        cmd = (f'wc -c < {self.key} > {o}.cat; {sys.executable} -c "import sys; print(len(open(sys.argv[1]).read()))" '
               f'{self.key} > {o}.py; cp {self.key} {o}.copy; wc -c < {o}.copy > {o}.cp; cat {self.other} > {o}.other')
        await self.run_cli('job-run', self.launches()[0], env={'LIAISON_WORKER_CMD': cmd})
        got = []
        for ext in ('cat', 'py', 'cp', 'other'):
            with open(f'{o}.{ext}') as f:
                got.append(f.read().strip())
        return got

    async def test_no_grant_job_reads_the_key_empty_three_ways_and_other_files_as_is(self):
        self.assertEqual(await self.reads('dibuja una representación de ti'), ['0', '0', '0', 'other'])
        with open(self.key) as f:
            self.assertEqual(f.read(), 'FXKEY-T1633')

    async def test_a_job_asking_for_an_ai_image_reads_the_key(self):
        n = str(len('FXKEY-T1633'))
        self.assertEqual(await self.reads('hazme una imagen con IA del héroe'), [n, n, n, 'other'])

    async def test_refused_art_keeps_the_image_slot(self):
        fake = os.path.join(self.tmp.name, 'refuse.py')
        with open(fake, 'w') as f:
            f.write('import sys\nsys.exit(int(sys.argv[1]))\n')
        for rc in ('4', '3'):
            out = await self.run_cli('art', 'hero', env={'LIAISON_ART_CMD': f'{sys.executable} {fake} {rc}'})
            self.assertEqual(out[0], 1)
            self.assertEqual(self.app_caps_used(), 0)
        await self.run_cli('art', 'hero')
        self.assertEqual(self.app_caps_used(), 1)

    def app_caps_used(self):
        from liaison.caps import Caps
        return Caps(os.path.join(self.tmp.name, 'state', 'caps.json'), os.devnull, {'img': 1}).used('img')


if __name__ == '__main__':
    unittest.main()
