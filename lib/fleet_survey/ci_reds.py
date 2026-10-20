"""### ci reds alone (--measure): each FAIL file of the newest fleet-ci log re-run alone."""
import os, re, signal, subprocess, time

from .common import AG, latest

CI_BUDGET = int(os.environ.get('FLEET_SURVEY_CI_BUDGET') or 50)
QUIET_WAIT = int(os.environ.get('FLEET_SURVEY_QUIET_WAIT') or 10)


def rows(ctx):
    """Each FAIL file of the newest fleet-ci log, shortest suite time first, re-run alone (run.sh --only) after one quiet-gate wait, until CI_BUDGET."""
    f = latest(os.path.join(AG, 'log', 'fleet-ci', '*.txt'))
    with open(f, errors='replace') as fh:
        reds = re.findall(r'^FAIL (\S+\.test\.\S+) ([\d.]+)\s*$', fh.read(), re.M)
    head = f'{len(reds)} reds in {os.path.basename(f)}'
    if not reds:
        return [head]
    deadline = ctx.t0 + CI_BUDGET
    gate = os.path.join(AG, 'bin', 'quiet-gate')
    try:
        q = subprocess.run([gate, '--wait', str(QUIET_WAIT)], capture_output=True, text=True,
                           timeout=QUIET_WAIT + 5).returncode if os.access(gate, os.X_OK) else 'none'
    except subprocess.TimeoutExpired:
        q = 'timeout'
    out = [f'{head}; quiet-gate rc {q} after <= {QUIET_WAIT} s, load1 {os.getloadavg()[0]:.1f}']
    runner = os.path.join(AG, 'bin', 'tests', 'run.sh')
    for rel, suite in sorted(reds, key=lambda r: float(r[1])):
        left = deadline - time.time()
        if left < 1:
            out.append(f'skipped: budget {CI_BUDGET} s  {rel}')
            continue
        t = time.time()
        p = subprocess.Popen(['bash', runner, '--only', rel, '-j', '1'], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, start_new_session=True)
        try:
            res = p.communicate(timeout=left)[0]
            m = re.search(rf'^(?:ok|FAIL) {re.escape(rel)} ([\d.]+)', res, re.M)
            rc, took = p.returncode, float(m.group(1)) if m else time.time() - t
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGTERM)
            try:
                p.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid, signal.SIGKILL)
                p.communicate()
            rc, took = 'timeout', time.time() - t
        out.append(f'rc {rc}  {took:6.1f} s alone (suite {suite} s)  {rel}')
    return out
