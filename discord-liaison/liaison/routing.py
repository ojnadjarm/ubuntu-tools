"""Job or escalate (T1416): work goes to a worker; only a blocked worker reaches the orchestrator."""
BLOCKERS = {
    'permission': 'a permission or classifier denial',
    'owner': 'a decision only the owner can take',
    'secret': 'a missing secret or account',
    'attempts': 'two failed attempts',
}
MAX_ATTEMPTS = 2


def route(blocker):
    """'escalate' for a named blocker, else 'job'."""
    return 'escalate' if blocker in BLOCKERS else 'job'


def after_failure(attempt):
    """'retry' until MAX_ATTEMPTS attempts failed, then 'escalate'."""
    return 'retry' if attempt < MAX_ATTEMPTS else 'escalate'
