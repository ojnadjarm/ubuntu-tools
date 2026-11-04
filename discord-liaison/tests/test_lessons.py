"""T1482: the postmortem's lessons stay in the worker prompt."""
import os
import unittest

ME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LESSONS = ('replaced by <your job id>', 'Every ask counts', 'one subject first', 'ship with sound',
           "come from the group's sources")


class TestLessons(unittest.TestCase):
    def test_job_md_keeps_every_lesson(self):
        with open(os.path.join(ME, 'JOB.md')) as f:
            job = f.read()
        self.assertEqual([x for x in LESSONS if x not in job], [])
