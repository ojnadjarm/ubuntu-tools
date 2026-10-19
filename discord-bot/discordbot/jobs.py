"""File spool between the sandboxed bot and the runner: pending jobs in, results out, strict schema."""
import json
import os
import uuid

KINDS = ('answer', 'work')
MAX_TEXT = 4000
MAX_MESSAGES = 20


class BadJob(ValueError):
    pass


def _snowflake(v):
    if not (isinstance(v, str) and v.isdigit() and len(v) <= 20):
        raise BadJob('bad id')
    return v


def validate(job):
    """Return a clean copy of a job dict or raise BadJob; nothing outside the schema survives."""
    if not isinstance(job, dict) or job.get('kind') not in KINDS:
        raise BadJob('bad kind')
    if not (isinstance(job.get('id'), str) and job['id'].replace('-', '').isalnum() and len(job['id']) <= 40):
        raise BadJob('bad job id')
    msgs = job.get('messages')
    if not isinstance(msgs, list) or not msgs:
        raise BadJob('no messages')
    clean_msgs = []
    for m in msgs[-MAX_MESSAGES:]:
        if not isinstance(m, dict):
            raise BadJob('bad message')
        clean_msgs.append({'author': str(m.get('author', '?'))[:64], 'self': bool(m.get('self')),
                           'content': str(m.get('content', ''))[:MAX_TEXT]})
    out = {'id': job['id'], 'kind': job['kind'], 'thread_id': _snowflake(job.get('thread_id')),
           'requester_id': _snowflake(job.get('requester_id')), 'title': str(job.get('title', ''))[:100],
           'messages': clean_msgs}
    if job['kind'] == 'work':
        appr = job.get('approval')
        if not isinstance(appr, dict) or appr.get('kind') not in ('tag', 'reaction', 'allowlist'):
            raise BadJob('bad approval')
        out['approval'] = {'kind': appr['kind']}
        if appr['kind'] == 'reaction':
            out['approval']['message_id'] = _snowflake(appr.get('message_id'))
        out['work_summary'] = str(job.get('work_summary', ''))[:500]
    return out


class Spool:
    def __init__(self, root):
        self.pending, self.claimed, self.done = (os.path.join(root, d) for d in ('pending', 'claimed', 'done'))
        for d in (self.pending, self.claimed, self.done):
            os.makedirs(d, exist_ok=True)

    @staticmethod
    def _write(path, data):
        tmp = path + '.tmp'
        with open(tmp, 'w') as f:
            json.dump(data, f)
        os.replace(tmp, path)

    def put(self, job):
        job = dict(job, id=job.get('id') or uuid.uuid4().hex)
        self._write(os.path.join(self.pending, job['id'] + '.json'), job)
        return job['id']

    def take(self):
        """Claim pending jobs (runner side); yields (job or None, error, raw name)."""
        for name in sorted(n for n in os.listdir(self.pending) if n.endswith('.json')):
            src, dst = os.path.join(self.pending, name), os.path.join(self.claimed, name)
            try:
                os.replace(src, dst)
                with open(dst) as f:
                    raw = json.load(f)
                yield validate(raw), None, name
            except (OSError, ValueError) as e:
                yield None, str(e), name

    def finish(self, job_id, result):
        self._write(os.path.join(self.done, job_id + '.json'), dict(result, id=job_id))
        try:
            os.unlink(os.path.join(self.claimed, job_id + '.json'))
        except OSError:
            pass

    def results(self):
        """Pop finished results (bot side)."""
        for name in sorted(n for n in os.listdir(self.done) if n.endswith('.json')):
            path = os.path.join(self.done, name)
            try:
                with open(path) as f:
                    res = json.load(f)
                os.unlink(path)
            except (OSError, ValueError):
                continue
            yield res
