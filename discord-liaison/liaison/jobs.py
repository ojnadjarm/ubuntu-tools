"""Background jobs (T1414): a request that needs real work becomes state/jobs/<id>/, run by a worker outside the run lock."""
import contextlib
import fcntl
import glob
import json
import os
import shutil
import time

from discordbot.store import save_json

from .routing import after_failure
from .threads import key

GRACE = 120
LIVE = ('queued', 'running')


class JobQueue:
    def __init__(self, d, clock=time.time):
        self.dir, self.clock = d, clock
        os.makedirs(d, exist_ok=True)

    def _p(self, jid, name='job.json'):
        return os.path.join(self.dir, jid, name)

    def get(self, jid):
        try:
            with open(self._p(jid)) as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def save(self, job):
        save_json(self._p(job['id']), job)

    def create(self, message, task, files=(), messages=()):
        """Queue one job for the newest message of a conversation (`messages`, oldest first); copy its files in."""
        jid = time.strftime('%Y%m%dT%H%M%S', time.gmtime(self.clock())) + f'-{message["id"]}'
        os.makedirs(os.path.join(self.dir, jid))
        kept = []
        for src in files:
            dest = os.path.join(self.dir, jid, os.path.basename(src))
            shutil.copy(src, dest)
            kept.append(dest)
        job = {'id': jid, 'message': message, 'messages': list(messages) or [message], 'task': task, 'files': kept,
               'status': 'queued', 'created': self.clock()}
        self.save(job)
        return job

    def list(self, *status):
        paths = glob.glob(os.path.join(glob.escape(self.dir), '*', 'job.json'))
        jobs = [self.get(os.path.basename(os.path.dirname(p))) for p in paths]
        return sorted((j for j in jobs if j and (not status or j['status'] in status)), key=lambda j: j['id'])

    def live(self, k):
        """Queued or running jobs of conversation `k`."""
        return [j for j in self.list(*LIVE) if key(j['message']) == k]

    def supersede(self, k, stop):
        """Mark the live jobs of conversation `k` superseded and stop the running ones' units; returns them."""
        with self._queue_lock():
            old = self.live(k)
            for j in old:
                was, j['status'] = j['status'], 'superseded'
                self.save(j)
                if was == 'running':
                    stop(j['id'])
            return old

    def seen(self, k, mid):
        """Triage saw message `mid` of conversation `k` and kept its live job: newer than that is not stale."""
        with self._queue_lock():
            for j in self.live(k):
                if int(mid) > int(j.get('through', j['message']['id'])):
                    j['through'] = mid
                    self.save(j)

    def locked(self, jid):
        """True while a runner holds the job's lock."""
        with open(self._p(jid, 'lock'), 'a') as f:
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return True
            fcntl.flock(f, fcntl.LOCK_UN)
            return False

    def alive(self, job):
        return self.clock() - job.get('started', 0) < GRACE or self.locked(job['id'])

    @contextlib.contextmanager
    def _queue_lock(self):
        with open(os.path.join(self.dir, '.lock'), 'a') as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            yield

    def reap(self):
        """Running jobs whose runner is gone (killed, reboot) are retried or failed; returns the failed ones."""
        with self._queue_lock():
            return [j for j in self.list('running') if not self.alive(j) and not self.retry(j, 'lost')]

    def dispatch(self, cap, launch):
        """Start queued jobs, oldest first, while fewer than `cap` run; returns (started ids, jobs whose launch failed)."""
        with self._queue_lock():
            started, failed = [], []
            for job in self.list('queued')[:max(cap - len(self.list('running')), 0)]:
                job.update(status='running', started=self.clock())
                self.save(job)
                if launch(job['id']) == 0:
                    started.append(job['id'])
                elif not self.retry(job, 'launch'):
                    failed.append(job)
            return started, failed

    def retry(self, job, why):
        """Queue the job again while attempts remain (True), else finish it failed (False)."""
        if after_failure(job.get('attempt', 1)) == 'retry':
            job.update(status='queued', attempt=job.get('attempt', 1) + 1, why=why)
            self.save(job)
            return True
        self.finish(job, 'failed', why)
        return False

    def finish(self, job, status, why=''):
        for p in job.get('files', []):
            if os.path.exists(p):
                os.unlink(p)
        job.update(status=status, ended=self.clock(), why=why)
        self.save(job)
