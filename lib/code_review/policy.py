"""Path policy: edit | retire-only | review-only | forbidden, and the swarm's own containment."""
import glob
import os

from .common import AW_REL, HOME, SKILLS, rel, absp

REVIEW_ONLY_ROOTS = ['the-dark-eye', 'moodle-harness', 'moodle-envs', 'projects']
# The swarm's own containment and evidence: never edited by a lane (the sandbox mounts them read-only too).
CONTAINMENT = ['agents/bin/code-review', 'agents/lib/code_review', 'agents/bin/code-review-sandbox',
               'agents/bin/code-review-netproxy',
               'agents/bin/guards', 'agents/bin/agent-exec', 'agents/bin/agent-run', 'agents/bin/fleetlib.sh',
               'agents/adapters/claude', 'agents/code-review/BRIEF.md', 'agents/code-review/LANES.md',
               'agents/code-review/swarm.js', 'agents/code-review/agent.env', 'agents/code-review/selftest',
               'agents/code-review/state', 'agents/bin/tests/code-review.test.sh', 'agents/bin/tests/fixtures/code-review',
               'agents/log', 'agents/FILE-CLAIMS.md', 'agents/.git']
WRITTEN_BY_CLI = ('agents/code-review/state', 'agents/log', 'agents/FILE-CLAIMS.md')  # forbidden to lanes, written by the CLI/hooks
FORBIDDEN = ['agents/backups', 'agents/secrets', 'agents/asr-corpus', f'{AW_REL}/research', f'{AW_REL}/owner', 'agents/AGENTS.md',
             'agents/ORCHESTRATOR.md', 'agents/FLEET.md', '.claude/CLAUDE.md', '.claude/settings.json', 'CLAUDE.md'] + CONTAINMENT


def harness_skills():
    return set(os.listdir(os.path.join(HOME, 'moodle-harness', 'skills'))) \
        if os.path.isdir(os.path.join(HOME, 'moodle-harness', 'skills')) else set()


def installed_skills():
    """Third-party skills: a same-named SKILL.md exists in a research skills-src checkout."""
    out = set()
    for f in glob.glob(os.path.join(HOME, AW_REL, 'research', '*', '*', 'skills-src', '**', 'SKILL.md'), recursive=True):
        out.add(os.path.basename(os.path.dirname(f)))
    return out


def skill_policy(name):
    if name == 'synced' or name in harness_skills():
        return 'review-only'
    if name in installed_skills():
        return 'retire-only'
    return 'edit'


def policy(path):
    """edit | retire-only | review-only | forbidden for one path."""
    r = rel(absp(path))
    if r.startswith('..'):
        return 'forbidden'
    under = lambda root: r == root or r.startswith(root + '/')
    if any(under(f) for f in FORBIDDEN):
        return 'forbidden'
    if any(under(f) for f in REVIEW_ONLY_ROOTS):
        return 'review-only'
    if under('.claude/skills'):
        parts = r.split('/')
        return skill_policy(parts[2]) if len(parts) > 2 else 'review-only'
    if under('agents'):
        return 'edit'
    return 'review-only'


def policy_rules():
    """Longest-prefix rules for swarm.js: [[absolute prefix, policy], ...]."""
    rules = [[os.path.join(HOME, 'agents'), 'edit']]
    rules += [[os.path.join(HOME, f), 'forbidden'] for f in FORBIDDEN]
    rules += [[os.path.join(HOME, f), 'review-only'] for f in REVIEW_ONLY_ROOTS]
    if os.path.isdir(SKILLS):
        rules.append([SKILLS, 'review-only'])
        rules += [[os.path.join(SKILLS, s), skill_policy(s)] for s in sorted(os.listdir(SKILLS))]
    return rules


def containment(real_home):
    """Absolute paths the sandbox mounts read-only (containment minus what the CLI itself writes)."""
    return [os.path.join(real_home, c) for c in CONTAINMENT if c not in WRITTEN_BY_CLI]
