"""A job's model and effort from the fleet chooser `model-route` (T1728)."""
import json
import os
import shlex
import subprocess

ROUTE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'bin', 'model-route')


def pick(cls, env, run=subprocess.run):
    """(model, effort, note) for class `cls` (none: build) and the liaison's request; ValueError on an unknown class."""
    cmd = shlex.split(env.get('LIAISON_ROUTE_CMD', ROUTE)) + ['--json', '--class', cls or 'build']
    for flag, key in (('--model', 'LIAISON_JOB_MODEL'), ('--effort', 'LIAISON_JOB_EFFORT')):
        if env.get(key):
            cmd += [flag, env[key]]
    try:
        r = run(cmd, capture_output=True, text=True, stdin=subprocess.DEVNULL)
        if r.returncode == 2:
            raise ValueError(r.stderr.strip() or f'model-route: unknown class {cls!r}')
        if r.returncode == 0:
            out = json.loads(r.stdout)
            return out['model'], out['effort'], out['note']
        why = f'exit {r.returncode}'
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as e:
        why = f'{type(e).__name__}: {e}'
    model = env.get('MODEL', 'opus')
    return model, 'high', f'model-route failed ({why}): the job runs on {model} high'
