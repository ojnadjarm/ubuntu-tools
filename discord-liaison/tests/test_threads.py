"""T1421: one live job per conversation, the newest message wins, a stale result is not posted."""
import os
import tempfile
import unittest

from liaison.jobs import JobQueue
from liaison.threads import batch, key, newer

from .test_jobs import Clock, JobBase


def m(mid, tid='400', author='2', channel='foro'):
    return {'id': mid, 'thread_id': tid, 'thread': 't', 'author': f'u{author}', 'author_id': author,
            'content': f'msg {mid}', 'channel': channel, 'bot': False, 'tags': []}


class TestBatch(unittest.TestCase):
    def test_conversations_newest_last_ordered_by_newest(self):
        inbox = [m('12', '400'), m('10', '450'), m('11', '400'), m('13', '999', '5', 'general'),
                 m('14', '999', '6', 'general'), m('9', '450')]
        got = [[x['id'] for x in conv] for conv in batch(inbox + inbox[:1])]
        self.assertEqual(got, [['9', '10'], ['11', '12'], ['13'], ['14']])
        self.assertEqual((key(inbox[0]), key(inbox[3])), ('400', '999:5'))

    def test_newer_counts_requester_or_owner_and_only_addressed_in_general(self):
        raw = [{'id': '20', 'author': {'id': '2'}, 'content': 'viejo'},
               {'id': '22', 'author': {'id': '7'}, 'content': 'otro'},
               {'id': '23', 'author': {'id': '2'}, 'content': 'charla sin mención'}]
        self.assertEqual(newer(raw, '20', {'2', '1'})['id'], '23')
        self.assertIsNone(newer(raw, '23', {'2', '1'}))
        self.assertIsNone(newer(raw, '20', {'2'}, general=True, me='900'))
        raw.append({'id': '24', 'author': {'id': '2'}, 'content': '@agents mejor en azul'})
        self.assertEqual(newer(raw, '20', {'2'}, general=True, me='900')['id'], '24')


class TestSupersede(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.q = JobQueue(self.tmp.name, Clock())
        self.stopped = []

    def tearDown(self):
        self.tmp.cleanup()

    def test_supersede_stops_only_running_jobs_of_that_conversation(self):
        run = self.q.create(m('1'), 'a')
        other = self.q.create(m('2', '450'), 'b')
        self.q.dispatch(3, lambda _: 0)
        queued = self.q.create(m('3'), 'c')
        old = self.q.supersede('400', self.stopped.append)
        self.assertEqual(sorted(j['id'] for j in old), sorted([run['id'], queued['id']]))
        self.assertEqual(self.stopped, [run['id']])
        self.assertEqual([j['id'] for j in self.q.live('400')], [])
        self.assertEqual(self.q.get(other['id'])['status'], 'running')
        self.assertEqual(self.q.dispatch(3, lambda _: 0)[0], [])

    def test_general_conversations_are_per_author(self):
        self.q.create(m('1', '999', '5', 'general'), 'a')
        self.q.create(m('2', '999', '6', 'general'), 'b')
        self.assertEqual(len(self.q.supersede('999:5', self.stopped.append)), 1)
        self.assertEqual(len(self.q.live('999:6')), 1)


class TestOneJobPerThread(JobBase):
    async def asyncSetUp(self):
        await super().asyncSetUp()
        self.stops = os.path.join(self.tmp.name, 'stopped.log')
        self.env.update(LIAISON_JOBS_MAX='3', LIAISON_JOB_STOP=f'echo {{id}} >> {self.stops}', LIAISON_STALE_WAIT='0')

    def stopped(self):
        with open(self.stops) as f:
            return f.read().split()

    async def test_new_message_replaces_the_live_job_with_the_whole_thread(self):
        (a,) = await self.inbox('dibuja a Gamelyn')
        self.assertEqual(self.fake.acks('400', a), ['👀'])
        await self.run_cli('job', a, 'draw Gamelyn')
        await self.run_cli('done')
        first = self.launches()[0]
        b, c = await self.inbox('no, eso no', 'hazlo con código, sin modelo de imagen')
        _, out = await self.run_cli('inbox')
        self.assertIn(f'<live-job id="{first}" status="running"', out)
        self.assertIn(f'id="{b}" newest="false"', out)
        self.assertIn(f'id="{c}" newest="true"', out)
        rc, out = await self.run_cli('job', b, 'draw Gamelyn in code, animated')
        self.assertEqual(rc, 0, out)
        self.assertIn(f'the job answers {c}', out)
        self.assertIn(f'replaces {first}', out)
        self.assertEqual(self.stopped(), [first])
        self.assertEqual(self.jobs().get(first)['status'], 'superseded')
        live = self.jobs().live('400')
        self.assertEqual(len(live), 1)
        self.assertEqual(live[0]['message']['id'], c)
        self.assertEqual([x['id'] for x in live[0]['messages']], [a, b, c])
        self.assertEqual((await self.run_cli('job-run', first))[0], 3)
        rc, _ = await self.run_cli('job-run', live[0]['id'])
        with open(os.path.join(self.tmp.name, 'prompt.seen')) as f:
            prompt = f.read()
        self.assertLess(prompt.index('dibuja a Gamelyn'), prompt.index('no, eso no'))
        self.assertIn(f'id="{c}" newest="true"', prompt)
        await self.run_cli('done')
        self.assertEqual(self.fake.acks('400', b), ['👀', '✅'])

    async def test_stale_result_waits_for_triage_and_is_not_posted(self):
        (a,) = await self.inbox('haz un resumen')
        await self.run_cli('job', a, 'summary')
        await self.run_cli('done')
        jid = self.launches()[0]
        job_env = {'LIAISON_JOB': jid}
        rc, _ = await self.run_cli('post', '400', 'resumen', env=job_env)
        self.assertEqual(rc, 0)
        (b,) = await self.inbox('gracias, sin prisa')
        rc, out = await self.run_cli('post', '400', 'resumen v2', env=job_env)
        self.assertEqual(rc, 4, out)
        self.assertIn('stale', out)
        await self.run_cli('done')
        self.assertEqual(self.fake.acks('400', b), [])
        self.assertEqual((await self.run_cli('post', '400', 'resumen v3', env=job_env))[0], 0)
        self.assertEqual(self.fake.sent('400'), ['resumen', 'resumen v3'])


if __name__ == '__main__':
    unittest.main()
