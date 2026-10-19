#!/usr/bin/python3 -IS
"""Claude Code SubagentStop hook: block a ticket agent's handback (exit 2) until agent-verify left a green check.json (T419)."""
import glob, json, os, re, sys

BRIEF = re.compile(r'([^\s`\'"(]*briefs/(?:[^\s`]+/)?([Tt]\d+)[^\s/`]*\.md)')
CHECK = re.compile(r'^\s*(?:[-*]\s*)?CHECK:\s*\S', re.M)


def transcript(hook):
    """The subagent's own transcript: the hook's path, else `<session>/subagents/**/agent-<id>.jsonl`."""
    p = hook.get('agent_transcript_path')
    if p:
        return p
    tp, aid = hook.get('transcript_path') or '', hook.get('agent_id') or ''
    found = glob.glob(os.path.join(glob.escape(tp[:-6] if tp.endswith('.jsonl') else tp), 'subagents', '**',
                                   f'agent-{aid}.jsonl'), recursive=True) if aid else []
    return found[0] if found else ''


def first_prompt(path):
    """Text of the first user message in a transcript."""
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            row = json.loads(line)
            if row.get('type') == 'user':
                c = row.get('message', {}).get('content', '')
                return c if isinstance(c, str) else ' '.join(b.get('text', '') for b in c if isinstance(b, dict))
    return ''


def verdict(hook, agent_work):
    """(exit code, reason) for one SubagentStop event."""
    if hook.get('stop_hook_active'):
        return 0, ''
    m = BRIEF.search(first_prompt(transcript(hook)))
    if not m:
        return 0, ''
    brief, ticket = os.path.expanduser(m.group(1)), m.group(2).upper()
    try:
        if not CHECK.search(open(brief, encoding='utf-8', errors='replace').read()):
            return 0, ''
    except OSError:
        return 0, ''
    path = os.path.join(agent_work, 'evidence', ticket, 'check.json')
    try:
        rec = json.load(open(path))
    except FileNotFoundError:
        return 2, f'{ticket}: no {path}. Run `agent-verify {brief}` before handback; report red as red.'
    except ValueError:
        return 2, f'{ticket}: {path} is not JSON. Re-run `agent-verify {brief}`.'
    if rec.get('ok') is not True:
        return 2, (f"{ticket}: CHECK is red (rc={rec.get('rc')}). Fix it and re-run `agent-verify {brief}`, "
                   'or hand back and report it red.')
    return 0, ''


def main():
    try:
        rc, why = verdict(json.load(sys.stdin), os.environ.get('AGENT_WORK') or os.path.expanduser('~/agent-work'))
    except Exception:
        rc, why = 0, ''
    if why:
        print(why, file=sys.stderr)
    sys.exit(rc)


if __name__ == '__main__':
    main()
