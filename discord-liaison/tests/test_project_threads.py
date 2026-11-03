"""T1481: a job working on a project posts its result only in a thread mapped to that project."""
import json
import os

from liaison.placement import misplaced

from .test_jobs import JobBase

THREADS = {'400': {'project': 'ten'}, '450': {'project': 'other'}}


class TestMisplaced(JobBase):
    def test_result_goes_to_the_project_thread_one_line_note_elsewhere(self):
        self.assertEqual(misplaced([], '400', THREADS, 'largo\nestado'), [])
        self.assertEqual(misplaced(['other'], '450', THREADS, 'largo\nestado'), [])
        self.assertEqual(misplaced(['other'], '400', THREADS, 'largo\nestado'), ['450'])
        self.assertEqual(misplaced(['other'], '400', THREADS, 'Estado en su hilo: https://x/1'), [])
        self.assertEqual(misplaced(['other'], '400', THREADS, 'nota', image='a.png'), ['450'])
        self.assertEqual(misplaced(['other'], '400', THREADS, 'x' * 201), ['450'])
        self.assertEqual(misplaced(['other'], '400', {'400': {'project': 'ten'}}, 'largo\nestado'), [])

    async def test_job_for_another_project_posts_only_a_note_in_the_request_thread(self):
        [mid] = await self.inbox('ayúdame con el otro proyecto')
        self.assertEqual((await self.run_cli('map', '450', 'other'))[0], 0)
        rc, out = await self.run_cli('job', mid, '--project', 'nope', 'trabajo')
        self.assertEqual(rc, 3, out)
        rc, out = await self.run_cli('job', mid, '--project', 'other', 'Project other: estado')
        self.assertEqual(rc, 0, out)
        [job] = self.jobs().list()
        self.assertEqual((job['projects'], job['task']), (['other'], 'Project other: estado'))
        await self.run_cli('job-run', job['id'])
        with open(os.path.join(self.tmp.name, 'prompt.seen')) as f:
            self.assertIn('project: other; post the result only in its thread 450', f.read())
        env = {'LIAISON_JOB': job['id'], 'LIAISON_STALE_WAIT': '0'}
        sent = len(self.fake.sent('400'))
        rc, out = await self.run_cli('post', '400', 'Estado:\n• va bien', env=env)
        self.assertEqual((rc, len(self.fake.sent('400'))), (3, sent), out)
        self.assertIn('450', out)
        self.assertEqual((await self.run_cli('post', '450', 'Estado:\n• va bien', env=env))[0], 0)
        self.assertEqual((await self.run_cli('post', '400', 'Estado en su hilo del otro proyecto.', env=env))[0], 0)
        self.assertEqual(self.fake.sent('400')[-1], 'Estado en su hilo del otro proyecto.')

    async def test_pr_marks_the_job_project(self):
        self.env['LIAISON_PRS_PER_DAY'] = '2'
        [mid] = await self.inbox('arregla el narrador')
        await self.run_cli('job', mid, 'Project ten: un PR')
        [job] = self.jobs().list()
        self.assertNotIn('projects', job)
        self.assertEqual((await self.run_cli('pr', 'ten', env={'LIAISON_JOB': job['id']}))[0], 0)
        self.assertEqual(self.jobs().get(job['id'])['projects'], ['ten'])
        with open(os.path.join(self.tmp.name, 'state', 'threads.json')) as f:
            self.assertEqual(json.load(f)['400']['project'], 'ten')
        rc, out = await self.run_cli('post', '400', 'PR listo:\n• enlace', env={'LIAISON_JOB': job['id'],
                                                                                'LIAISON_STALE_WAIT': '0'})
        self.assertEqual(rc, 0, out)
